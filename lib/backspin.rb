# frozen_string_literal: true

require "yaml"
require "fileutils"
require "open3"
require "pathname"
require "backspin/version"
require "backspin/configuration"
require "backspin/command_result"
require "backspin/command"
require "backspin/matcher"
require "backspin/command_diff"
require "backspin/record"
require "backspin/recorder"
require "backspin/record_result"

module Backspin
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

    def recorded_commands
      result.command_diffs.map(&:recorded_command)
    end

    def actual_commands
      result.command_diffs.map(&:actual_command)
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
    # @param filter [Proc] Custom filter for recorded data
    # @return [RecordResult] Result object with output and status
    def run(command = nil, name:, env: nil, mode: :auto, matcher: nil, filter: nil, &block)
      if block_given?
        raise ArgumentError, "command must be omitted when using a block" unless command.nil?
        raise ArgumentError, "env is not supported when using a block" unless env.nil?

        return perform_capture(name, mode: mode, matcher: matcher, filter: filter, &block)
      end

      raise ArgumentError, "command is required" if command.nil?

      perform_command_run(command, name: name, env: env, mode: mode, matcher: matcher, filter: filter)
    end

    # Captures all stdout/stderr output from a block
    #
    # @param record_name [String] Name for the record file
    # @param mode [Symbol] Recording mode - :auto, :record, :verify
    # @param matcher [Proc, Hash] Custom matcher for verification
    # @param filter [Proc] Custom filter for recorded data
    # @return [RecordResult] Result object with captured output
    def capture(record_name, mode: :auto, matcher: nil, filter: nil, &block)
      raise ArgumentError, "record_name is required" if record_name.nil? || record_name.empty?
      raise ArgumentError, "block is required" unless block_given?

      perform_capture(record_name, mode: mode, matcher: matcher, filter: filter, &block)
    end

    private

    def perform_capture(record_name, mode:, matcher:, filter:, &block)
      record_path = Record.build_record_path(record_name)
      mode = determine_mode(mode, record_path)
      validate_mode!(mode)

      record = if mode == :record
        Record.create(record_name)
      else
        Record.load_or_create(record_path)
      end

      recorder = Recorder.new(record: record, mode: mode, matcher: matcher, filter: filter)

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

    def perform_command_run(command, name:, env:, mode:, matcher:, filter:)
      record_path = Record.build_record_path(name)
      mode = determine_mode(mode, record_path)
      validate_mode!(mode)

      record = if mode == :record
        Record.create(name)
      else
        Record.load_or_create(record_path)
      end

      normalized_env = env.nil? ? nil : normalize_env(env)

      result = case mode
      when :record
        stdout, stderr, status = execute_command(command, normalized_env)
        command_result = Command.new(
          method_class: Open3::Capture3,
          args: command,
          env: normalized_env,
          stdout: stdout,
          stderr: stderr,
          status: status.exitstatus,
          recorded_at: Time.now.iso8601
        )
        record.add_command(command_result)
        record.save(filter: filter)
        RecordResult.new(output: [stdout, stderr, status], mode: :record, record: record)
      when :verify
        raise RecordNotFoundError, "Record not found: #{record.path}" unless record.exists?
        raise RecordNotFoundError, "No commands found in record #{record.path}" if record.empty?
        if record.commands.size != 1
          raise RecordFormatError, "Invalid record format: expected 1 command for run, found #{record.commands.size}"
        end

        recorded_command = record.commands.first
        unless recorded_command.method_class == Open3::Capture3
          raise RecordFormatError, "Invalid record format: expected Open3::Capture3 for run"
        end

        stdout, stderr, status = execute_command(command, normalized_env)
        actual_command = Command.new(
          method_class: Open3::Capture3,
          args: command,
          env: normalized_env,
          stdout: stdout,
          stderr: stderr,
          status: status.exitstatus
        )
        command_diff = CommandDiff.new(recorded_command: recorded_command, actual_command: actual_command, matcher: matcher)
        RecordResult.new(
          output: [stdout, stderr, status],
          mode: :verify,
          verified: command_diff.verified?,
          record: record,
          command_diffs: [command_diff],
          actual_commands: [actual_command]
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
      error_message += "Record: #{result.record.path}\n"
      details = result.error_message || result.diff
      error_message += "\n#{details}" if details

      raise VerificationError.new(error_message, result: result)
    end

    def determine_mode(mode_option, record_path)
      return mode_option if mode_option && mode_option != :auto

      # Auto mode: record if file doesn't exist, verify if it does
      File.exist?(record_path) ? :verify : :record
    end

    def validate_mode!(mode)
      return if %i[record verify].include?(mode)

      raise ArgumentError, "Playback mode is not supported" if mode == :playback

      raise ArgumentError, "Unknown mode: #{mode}"
    end
  end
end
