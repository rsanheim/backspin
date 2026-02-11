# frozen_string_literal: true

require "yaml"
require "fileutils"
require "open3"
require "pathname"
require "backspin/version"
require "backspin/configuration"
require "backspin/snapshot"
require "backspin/matcher"
require "backspin/command_diff"
require "backspin/record"
require "backspin/backspin_result"
require "backspin/recorder"

module Backspin
  VALID_MODES = %i[auto record verify].freeze

  class RecordNotFoundError < StandardError; end

  class VerificationError < StandardError
    attr_reader :result

    def initialize(message, result: nil)
      super(message)
      @result = result
    end

    def diff
      result.diff
    end

    def expected_snapshot
      result.expected
    end

    def actual_snapshot
      result.actual
    end
  end

  class << self
    def configuration
      return @configuration if @configuration

      @configuration = Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    def scrub_text(text)
      return text unless configuration.scrub_credentials && text

      scrubbed = text.dup
      configuration.credential_patterns.each do |pattern|
        scrubbed.gsub!(pattern) do |match|
          "*" * match.length
        end
      end
      scrubbed
    end

    # Primary API - records on first run, verifies on subsequent runs
    #
    # @param command [String, Array] Command to execute via Open3.capture3
    # @param name [String] Name for the record file
    # @param env [Hash] Environment variables to pass to Open3.capture3
    # @param mode [Symbol] Recording mode - :auto, :record, :verify
    # @param matcher [Proc, Hash] Custom matcher for verification
    # @param filter [Proc] Custom filter for recorded data/canonicalization
    # @param filter_on [Symbol] Filter application mode - :both (default), :record
    # @return [BackspinResult] Aggregate result for this run
    def run(command = nil, name:, env: nil, mode: :auto, matcher: nil, filter: nil, filter_on: :both, &block)
      validate_filter_on!(filter_on)

      if block_given?
        raise ArgumentError, "command must be omitted when using a block" unless command.nil?
        raise ArgumentError, "env is not supported when using a block" unless env.nil?

        return perform_capture(name, mode: mode, matcher: matcher, filter: filter, filter_on: filter_on, &block)
      end

      raise ArgumentError, "command is required" if command.nil?

      perform_command_run(
        command,
        name: name,
        env: env,
        mode: mode,
        matcher: matcher,
        filter: filter,
        filter_on: filter_on
      )
    end

    # Captures all stdout/stderr output from a block
    #
    # @param record_name [String] Name for the record file
    # @param mode [Symbol] Recording mode - :auto, :record, :verify
    # @param matcher [Proc, Hash] Custom matcher for verification
    # @param filter [Proc] Custom filter for recorded data/canonicalization
    # @param filter_on [Symbol] Filter application mode - :both (default), :record
    # @return [BackspinResult] Aggregate result for this run
    def capture(record_name, mode: :auto, matcher: nil, filter: nil, filter_on: :both, &block)
      raise ArgumentError, "record_name is required" if record_name.nil? || record_name.empty?
      raise ArgumentError, "block is required" unless block_given?
      validate_filter_on!(filter_on)

      perform_capture(record_name, mode: mode, matcher: matcher, filter: filter, filter_on: filter_on, &block)
    end

    private

    def perform_capture(record_name, mode:, matcher:, filter:, filter_on:, &block)
      record_path = Record.build_record_path(record_name)
      mode = determine_mode(mode, record_path)
      validate_mode!(mode)

      record = Record.load_or_create(record_path)

      recorder = Recorder.new(record: record, mode: mode, matcher: matcher, filter: filter, filter_on: filter_on)

      result = case mode
      when :record
        recorder.perform_capture_recording(&block)
      when :verify
        recorder.perform_capture_verification(&block)
      else
        raise ArgumentError, "Unknown mode: #{mode}"
      end

      raise_on_verification_failure!(result)

      result
    end

    def perform_command_run(command, name:, env:, mode:, matcher:, filter:, filter_on:)
      record_path = Record.build_record_path(name)
      mode = determine_mode(mode, record_path)
      validate_mode!(mode)

      record = Record.load_or_create(record_path)

      normalized_env = env.nil? ? nil : normalize_env(env)

      result = case mode
      when :record
        stdout, stderr, status = execute_command(command, normalized_env)
        actual_snapshot = Snapshot.new(
          command_type: Open3::Capture3,
          args: command,
          env: normalized_env,
          stdout: stdout,
          stderr: stderr,
          status: status.exitstatus,
          recorded_at: Time.now.iso8601
        )
        record.set_snapshot(actual_snapshot)
        record.save(filter: filter)
        BackspinResult.new(
          mode: :record,
          record_path: record.path,
          actual: actual_snapshot,
          output: [stdout, stderr, status]
        )
      when :verify
        raise RecordNotFoundError, "Record not found: #{record.path}" unless record.exists?
        raise RecordNotFoundError, "No snapshot found in record #{record.path}" if record.empty?

        expected_snapshot = record.snapshot
        unless expected_snapshot.command_type == Open3::Capture3
          raise RecordFormatError, "Invalid record format: expected Open3::Capture3 for run"
        end

        stdout, stderr, status = execute_command(command, normalized_env)
        actual_snapshot = Snapshot.new(
          command_type: Open3::Capture3,
          args: command,
          env: normalized_env,
          stdout: stdout,
          stderr: stderr,
          status: status.exitstatus
        )
        command_diff = CommandDiff.new(
          expected: expected_snapshot,
          actual: actual_snapshot,
          matcher: matcher,
          filter: filter,
          filter_on: filter_on
        )
        BackspinResult.new(
          mode: :verify,
          record_path: record.path,
          actual: actual_snapshot,
          expected: expected_snapshot,
          verified: command_diff.verified?,
          command_diff: command_diff,
          output: [stdout, stderr, status]
        )
      else
        raise ArgumentError, "Unknown mode: #{mode}"
      end

      raise_on_verification_failure!(result)

      result
    end

    def normalize_env(env)
      raise ArgumentError, "env must be a Hash" unless env.is_a?(Hash)

      env.empty? ? nil : env
    end

    def execute_command(command, env)
      case command
      when String
        env ? Open3.capture3(env, command) : Open3.capture3(command)
      when Array
        raise ArgumentError, "command array cannot be empty" if command.empty?
        env ? Open3.capture3(env, *command) : Open3.capture3(*command)
      else
        raise ArgumentError, "command must be a String or Array"
      end
    end

    def raise_on_verification_failure!(result)
      return unless configuration.raise_on_verification_failure && result.verified? == false

      error_message = "Backspin verification failed!\n"
      error_message += "Record: #{result.record_path}\n"
      details = result.error_message || result.diff
      error_message += "\n#{details}" if details

      raise VerificationError.new(error_message, result: result)
    end

    def determine_mode(mode_option, record_path)
      return mode_option if mode_option && mode_option != :auto

      env_mode = mode_from_env
      if env_mode && env_mode != :auto
        configuration.logger.debug { "event=mode_resolved mode=#{env_mode} source=env record=#{record_path}" }
        return env_mode
      end

      resolved = File.exist?(record_path) ? :verify : :record
      configuration.logger.debug { "event=mode_resolved mode=#{resolved} source=auto record=#{record_path}" }
      resolved
    end

    def mode_from_env
      raw = ENV["BACKSPIN_MODE"]
      return if raw.nil? || raw.strip.empty?

      mode = raw.strip.downcase.to_sym
      return mode if VALID_MODES.include?(mode)

      raise ArgumentError,
        "Invalid BACKSPIN_MODE value: #{raw.inspect}. Allowed values: auto, record, verify"
    end

    def validate_mode!(mode)
      return if %i[record verify].include?(mode)

      raise ArgumentError, "Playback mode is not supported" if mode == :playback

      raise ArgumentError, "Unknown mode: #{mode}"
    end

    def validate_filter_on!(filter_on)
      return if %i[both record].include?(filter_on)

      raise ArgumentError, "Unknown filter_on: #{filter_on}. Must be :both or :record"
    end
  end
end
