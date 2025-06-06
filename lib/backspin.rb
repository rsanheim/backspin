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
    # @return [RecordResult] Result object with output and status
    def run(record_name, options = {}, &block)
      raise ArgumentError, "record_name is required" if record_name.nil? || record_name.empty?
      raise ArgumentError, "block is required" unless block_given?

      record_path = build_record_path(record_name)
      mode = determine_mode(options[:mode], record_path)

      case mode
      when :record
        perform_recording(record_name, record_path, options, &block)
      when :verify
        perform_verification(record_name, record_path, options, &block)
      when :playback
        perform_playback(record_name, record_path, options, &block)
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

    def perform_recording(_record_name, record_path, options)
      recorder = Recorder.new
      recorder.record_calls(:capture3, :system)

      output = yield

      if output.is_a?(Array) && output.size == 3
        stdout, stderr, status = output
        status_int = status.respond_to?(:exitstatus) ? status.exitstatus : status
        output = [stdout, stderr, status_int]
      end

      # Save the recording
      FileUtils.mkdir_p(File.dirname(record_path))
      record = Record.new(record_path)
      record.clear
      recorder.commands.each { |cmd| record.add_command(cmd) }
      record.save(filter: options[:filter])

      # Return result
      RecordResult.new(
        output: output,
        mode: :record,
        record_path: Pathname.new(record_path),
        commands: recorder.commands
      )
    end

    def perform_verification(_record_name, record_path, options)
      record = Record.load_or_create(record_path)

      raise RecordNotFoundError, "Record not found: #{record_path}" unless record.exists?
      raise RecordNotFoundError, "No commands found in record" if record.empty?

      # For verification, we need to track all commands executed
      recorder = Recorder.new(mode: :verify, record: record)
      recorder.setup_replay_stubs

      # Track verification results for each command
      command_diffs = []
      command_index = 0

      # Override stubs to verify each command as it's executed
      allow(Open3).to receive(:capture3).and_wrap_original do |original_method, *args|
        recorded_command = record.commands[command_index]

        if recorded_command.nil?
          raise RecordNotFoundError, "No more recorded commands, but tried to execute: #{args.inspect}"
        end

        if recorded_command.method_class != Open3::Capture3
          raise RecordNotFoundError, "Expected #{recorded_command.method_class.name} but got Open3.capture3"
        end

        # Execute the actual command
        stdout, stderr, status = original_method.call(*args)

        # Create verification result
        actual_result = CommandResult.new(
          stdout: stdout,
          stderr: stderr,
          status: status.exitstatus
        )

        # Create CommandDiff to track the comparison
        command_diffs << CommandDiff.new(
          recorded_command: recorded_command,
          actual_result: actual_result,
          matcher: options[:matcher]
        )

        command_index += 1
        [stdout, stderr, status]
      end

      allow_any_instance_of(Object).to receive(:system).and_wrap_original do |original_method, receiver, *args|
        recorded_command = record.commands[command_index]

        if recorded_command.nil?
          raise RecordNotFoundError, "No more recorded commands, but tried to execute: system #{args.inspect}"
        end

        if recorded_command.method_class != ::Kernel::System
          raise RecordNotFoundError, "Expected #{recorded_command.method_class.name} but got system"
        end

        # Execute the actual command
        result = original_method.call(receiver, *args)

        # Create verification result (system only gives us exit status)
        actual_result = CommandResult.new(
          stdout: "",
          stderr: "",
          status: result ? 0 : 1
        )

        # Create CommandDiff to track the comparison
        command_diffs << CommandDiff.new(
          recorded_command: recorded_command,
          actual_result: actual_result,
          matcher: options[:matcher]
        )

        command_index += 1
        result
      end

      # Execute block
      output = yield

      # Check if all commands were executed
      if command_index < record.commands.size
        raise RecordNotFoundError, "Expected #{record.commands.size} commands but only #{command_index} were executed"
      end

      # Overall verification status
      all_verified = command_diffs.all?(&:verified?)

      RecordResult.new(
        output: output,
        mode: :verify,
        verified: all_verified,
        record_path: Pathname.new(record_path),
        commands: record.commands,
        command_diffs: command_diffs
      )
    end

    def perform_playback(_record_name, record_path, _options)
      record = Record.load_or_create(record_path)

      raise RecordNotFoundError, "Record not found: #{record_path}" unless record.exists?
      raise RecordNotFoundError, "No commands found in record" if record.empty?

      # Setup replay mode - this will handle returning values for all commands
      recorder = Recorder.new(mode: :replay, record: record)
      recorder.setup_replay_stubs

      # Execute block (all commands will be stubbed with recorded values)
      output = yield

      RecordResult.new(
        output: output,
        mode: :playback,
        verified: true, # Always true for playback
        record_path: Pathname.new(record_path),
        commands: record.commands
      )
    end

    def build_record_path(name)
      backspin_dir = configuration.backspin_dir
      backspin_dir.mkpath

      File.join(backspin_dir, "#{name}.yml")
    end
  end
end
