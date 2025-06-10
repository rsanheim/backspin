require "yaml"
require "fileutils"
require "open3"
require "pathname"
require "ostruct"
require "rspec/mocks"
require "backspin/version"
require "backspin/command_result"
require "backspin/command"
require "backspin/command_diff"
require "backspin/record"
require "backspin/recorder"
require "backspin/record_result"

module Backspin
  class RecordNotFoundError < StandardError; end

  # Include RSpec mocks methods
  extend RSpec::Mocks::ExampleMethods

  # Configuration for Backspin
  class Configuration
    attr_accessor :scrub_credentials
    # The directory where backspin will store its files - defaults to fixtures/backspin
    attr_accessor :backspin_dir
    # Regex patterns to scrub from saved output
    attr_reader :credential_patterns

    def initialize
      @scrub_credentials = true
      @credential_patterns = default_credential_patterns
      @backspin_dir = Pathname(Dir.pwd).join("fixtures", "backspin")
    end

    def add_credential_pattern(pattern)
      @credential_patterns << pattern
    end

    def clear_credential_patterns
      @credential_patterns = []
    end

    def reset_credential_patterns
      @credential_patterns = default_credential_patterns
    end

    private

    # Some default patterns for common credential types
    def default_credential_patterns
      [
        # AWS credentials
        /AKIA[0-9A-Z]{16}/,                                    # AWS Access Key ID
        /aws_secret_access_key\s*[:=]\s*["']?([A-Za-z0-9\/+=]{40})["']?/i,  # AWS Secret Key
        /aws_session_token\s*[:=]\s*["']?([A-Za-z0-9\/+=]+)["']?/i,         # AWS Session Token

        # Google Cloud credentials
        /AIza[0-9A-Za-z\-_]{35}/,                              # Google API Key
        /[0-9]+-[0-9A-Za-z_]{32}\.apps\.googleusercontent\.com/, # Google OAuth2 client ID
        /-----BEGIN (RSA )?PRIVATE KEY-----/,                  # Private keys

        # Generic patterns
        /api[_-]?key\s*[:=]\s*["']?([A-Za-z0-9\-_]{20,})["']?/i,  # Generic API keys
        /auth[_-]?token\s*[:=]\s*["']?([A-Za-z0-9\-_]{20,})["']?/i, # Auth tokens
        /Bearer\s+([A-Za-z0-9\-_]+)/,                               # Bearer tokens
        /password\s*[:=]\s*["']?([^"'\s]{8,})["']?/i,             # Passwords
        /-p([^"'\s]{8,})/,                                          # MySQL-style password args
        /secret\s*[:=]\s*["']?([A-Za-z0-9\-_]{20,})["']?/i       # Generic secrets
      ]
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
          # Replace with asterisks of the same length
          "*" * match.length
        end
      end
      scrubbed
    end

    # Primary API - records on first run, verifies on subsequent runs
    #
    # @param record_name [String] Name for the record file
    # @param options [Hash] Options for recording/verification
    # @option options [Symbol] :mode (:auto) Recording mode - :auto, :record, :verify, :playback
    # @option options [Proc] :filter Custom filter for recorded data
    # @option options [Proc] :matcher Custom matcher for verification
    # @option options [Array] :match_on Field-specific matchers - format: [:field, matcher] or [[:field1, matcher1], [:field2, matcher2]]
    # @return [RecordResult] Result object with output and status
    def run(record_name, options = {}, &block)
      raise ArgumentError, "record_name is required" if record_name.nil? || record_name.empty?
      raise ArgumentError, "block is required" unless block_given?

      record_path = Record.build_record_path(record_name)
      mode = determine_mode(options[:mode], record_path)

      # Create or load the record based on mode
      record = if mode == :record
        Record.create(record_name)
      else
        Record.load_or_create!(record_path)
      end

      # Create recorder with all needed context
      recorder = Recorder.new(record: record, options: options, mode: mode)

      # Execute the appropriate mode
      case mode
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
    end

    # Strict version of run that raises on verification failure
    #
    # @param record_name [String] Name for the record file
    # @param options [Hash] Options for recording/verification
    # @return [RecordResult] Result object with output and status
    # @raise [RSpec::Expectations::ExpectationNotMetError] If verification fails
    def run!(record_name, options = {}, &block)
      result = run(record_name, options, &block)

      if result.verified? == false
        error_message = "Backspin verification failed!\n"
        error_message += "Record: #{result.record_path}\n"

        # Use the error_message from the result which is now properly formatted
        error_message += "\n#{result.error_message}" if result.error_message

        raise RSpec::Expectations::ExpectationNotMetError, error_message
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
