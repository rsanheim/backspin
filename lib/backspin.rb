# frozen_string_literal: true

require "yaml"
require "fileutils"
require "open3"
require "pathname"
require "ostruct"
require "rspec/mocks"
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

  # Include RSpec mocks methods
  extend RSpec::Mocks::ExampleMethods

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
    # @param record_name [String] Name for the record file
    # @param mode [Symbol] Recording mode - :auto, :record, :verify, :playback
    # @param matcher [Proc, Hash] Custom matcher for verification
    #   - Proc: ->(recorded, actual) { ... } for full command matching
    #   - Hash: { stdout: ->(recorded, actual) { ... }, stderr: ->(recorded, actual) { ... } } for field-specific matching
    #     Only specified fields are checked - fields without matchers are ignored
    #   - Hash with :all key: { all: ->(recorded, actual) { ... } } receives full command hashes
    #     Can be combined with field matchers - all specified matchers must pass
    # @param filter [Proc] Custom filter for recorded data
    # @return [RecordResult] Result object with output and status
    def run(record_name, mode: :auto, matcher: nil, filter: nil, &block)
      raise ArgumentError, "record_name is required" if record_name.nil? || record_name.empty?
      raise ArgumentError, "block is required" unless block_given?

      record_path = Record.build_record_path(record_name)
      mode = determine_mode(mode, record_path)

      # Create or load the record based on mode
      record = if mode == :record
        Record.create(record_name)
      else
        Record.load_or_create(record_path)
      end

      # Create recorder with all needed context
      recorder = Recorder.new(record: record, mode: mode, matcher: matcher, filter: filter)

      # Execute the appropriate mode
      result = case mode
      when :record
        recorder.setup_recording_stubs(:capture3, :system)
        recorder.perform_recording(&block)
      when :verify
        recorder.perform_verification(&block)
      when :playback
        recorder.perform_playback(&block)
      else
        raise ArgumentError, "Unknown mode: #{mode}"
      end

      # Check if we should raise on verification failure
      if configuration.raise_on_verification_failure && result.verified? == false
        error_message = "Backspin verification failed!\n"
        error_message += "Record: #{result.record.path}\n"
        error_message += "\n#{result.error_message}" if result.error_message

        raise RSpec::Expectations::ExpectationNotMetError, error_message
      end

      result
    end

    # Strict version of run that raises on verification failure
    #
    # @param record_name [String] Name for the record file
    # @param mode [Symbol] Recording mode - :auto, :record, :verify, :playback
    # @param matcher [Proc, Hash] Custom matcher for verification
    # @param filter [Proc] Custom filter for recorded data
    # @return [RecordResult] Result object with output and status
    # @raise [RSpec::Expectations::ExpectationNotMetError] If verification fails
    def run!(record_name, mode: :auto, matcher: nil, filter: nil, &block)
      result = run(record_name, mode: mode, matcher: matcher, filter: filter, &block)

      if result.verified? == false
        error_message = "Backspin verification failed!\n"
        error_message += "Record: #{result.record.path}\n"

        # Use the error_message from the result which is now properly formatted
        error_message += "\n#{result.error_message}" if result.error_message

        raise RSpec::Expectations::ExpectationNotMetError, error_message
      end

      result
    end

    # Captures all stdout/stderr output from a block
    #
    # @param record_name [String] Name for the record file
    # @param mode [Symbol] Recording mode - :auto, :record, :verify, :playback
    # @param matcher [Proc, Hash] Custom matcher for verification
    # @param filter [Proc] Custom filter for recorded data
    # @return [RecordResult] Result object with captured output
    def capture(record_name, mode: :auto, matcher: nil, filter: nil, &block)
      raise ArgumentError, "record_name is required" if record_name.nil? || record_name.empty?
      raise ArgumentError, "block is required" unless block_given?

      record_path = Record.build_record_path(record_name)
      mode = determine_mode(mode, record_path)

      # Create or load the record based on mode
      record = if mode == :record
        Record.create(record_name)
      else
        Record.load_or_create(record_path)
      end

      # Create recorder with all needed context
      recorder = Recorder.new(record: record, mode: mode, matcher: matcher, filter: filter)

      # Execute the appropriate mode
      result = case mode
      when :record
        recorder.perform_capture_recording(&block)
      when :verify
        recorder.perform_capture_verification(&block)
      when :playback
        recorder.perform_capture_playback(&block)
      else
        raise ArgumentError, "Unknown mode: #{mode}"
      end

      # Check if we should raise on verification failure
      if configuration.raise_on_verification_failure && result.verified? == false
        error_message = "Backspin verification failed!\n"
        error_message += "Record: #{result.record.path}\n"
        error_message += result.error_message || "Output verification failed"

        # Include diff if available
        if result.diff
          error_message += "\n\nDiff:\n#{result.diff}"
        end

        raise VerificationError.new(error_message, result: result)
      end

      result
    end

    private

    def determine_mode(mode_option, record_path)
      return mode_option if mode_option && mode_option != :auto

      # Auto mode: record if file doesn't exist, verify if it does
      File.exist?(record_path) ? :verify : :record
    end
  end
end
