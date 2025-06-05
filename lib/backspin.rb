require "yaml"
require "fileutils"
require "open3"
require "pathname"
require "ostruct"
require "rspec/mocks"
require "backspin/version"
require "backspin/command"
require "backspin/record"
require "backspin/recorder"

module Backspin
  class RecordNotFoundError < StandardError; end

  # Include RSpec mocks methods
  extend RSpec::Mocks::ExampleMethods

  # Configuration for Backspin
  class Configuration
    attr_accessor :scrub_credentials
    # The directory where backspin will store its files - defaults to spec/backspin_data
    attr_accessor :backspin_dir
    # Regex patterns to scrub from saved output
    attr_reader :credential_patterns

    def initialize
      @scrub_credentials = true
      @credential_patterns = default_credential_patterns
      @backspin_dir = Pathname(Dir.pwd).join("spec", "backspin_data")
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
        /password\s*[:=]\s*["']?([^"'\s]{8,})["']?/i,             # Passwords
        /secret\s*[:=]\s*["']?([A-Za-z0-9\-_]{20,})["']?/i       # Generic secrets
      ]
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end

  class Result
    attr_reader :commands, :record_path

    def initialize(commands:, record_path:)
      @commands = commands
      @record_path = record_path
    end
  end

  class VerifyResult
    attr_reader :record_path, :expected_output, :actual_output, :diff, :stderr_diff

    def initialize(verified:, record_path:, expected_output: nil, actual_output: nil,
      expected_stderr: nil, actual_stderr: nil, expected_status: nil, actual_status: nil,
      command_executed: true)
      @verified = verified
      @record_path = record_path
      @expected_output = expected_output
      @actual_output = actual_output
      @expected_stderr = expected_stderr
      @actual_stderr = actual_stderr
      @expected_status = expected_status
      @actual_status = actual_status
      @command_executed = command_executed

      if !verified && expected_output && actual_output
        @diff = generate_diff(expected_output, actual_output)
      end

      if !verified && expected_stderr && actual_stderr && expected_stderr != actual_stderr
        @stderr_diff = generate_diff(expected_stderr, actual_stderr)
      end
    end

    def verified?
      @verified
    end

    def output
      @actual_output
    end

    def error_message
      return nil if verified?

      "Output verification failed\nExpected: #{@expected_output.chomp}\nActual: #{@actual_output.chomp}"
    end

    def command_executed?
      @command_executed
    end

    private

    def generate_diff(expected, actual)
      expected_lines = expected.lines
      actual_lines = actual.lines
      diff = []

      # Simple diff for now
      expected_lines.each do |line|
        unless actual_lines.include?(line)
          diff << "-#{line.chomp}"
        end
      end

      actual_lines.each do |line|
        unless expected_lines.include?(line)
          diff << "+#{line.chomp}"
        end
      end

      diff.join("\n")
    end
  end

  class << self
    attr_accessor :last_output

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

    def call(record_name, filter: nil)
      raise ArgumentError, "record_name is required" if record_name.nil? || record_name.empty?

      record_path = build_record_path(record_name)

      # Create recorder to handle stubbing and command recording
      recorder = Recorder.new
      recorder.record_calls(:capture3, :system)

      yield

      # Save commands using new format
      FileUtils.mkdir_p(File.dirname(record_path))
      # Don't load existing data when creating new record
      record = Record.new(record_path)
      record.clear  # Clear any loaded data
      recorder.commands.each { |cmd| record.add_command(cmd) }
      record.save(filter: filter)

      Result.new(commands: recorder.commands, record_path: Pathname.new(record_path))
    end

    def output
      last_output
    end

    def use_record(record_name, options = {}, &block)
      raise ArgumentError, "record_name is required" if record_name.nil? || record_name.empty?

      record_path = build_record_path(record_name)
      record_mode = options[:record] || :once
      filter = options[:filter]

      case record_mode
      when :none
        # Never record, only replay
        unless File.exist?(record_path)
          raise RecordNotFoundError, "Record not found: #{record_path}"
        end
        replay_record(record_path, &block)
      when :all
        # Always record
        record_and_save_record(record_path, filter: filter, &block)
      when :once
        # Record if doesn't exist, replay if exists
        if File.exist?(record_path)
          replay_record(record_path, &block)
        else
          record_and_save_record(record_path, filter: filter, &block)
        end
      when :new_episodes
        # Record new commands not in record
        # For now, simplified: just append new recordings
        record_new_episode(record_path, filter: filter, &block)
      else
        raise ArgumentError, "Unknown record mode: #{record_mode}"
      end
    end

    def verify(record_name, mode: :strict, matcher: nil, &block)
      record_path = build_record_path(record_name)

      record = Record.load_or_create(record_path)
      unless record.exists?
        raise RecordNotFoundError, "Record not found: #{record_path}"
      end

      if record.empty?
        raise RecordNotFoundError, "No commands found in record"
      end

      # For verify, we only handle single command verification for now
      # Use the first command
      command = record.commands.first

      # Create recorder for verification
      recorder = Recorder.new

      if mode == :playback
        # Playback mode: return recorded output without running command
        recorder.setup_playback_stub(command)

        yield

        # In playback mode, always verified
        VerifyResult.new(
          verified: true,
          record_path: Pathname.new(record_path),
          expected_output: command.stdout,
          actual_output: command.stdout,
          expected_stderr: command.stderr,
          actual_stderr: command.stderr,
          expected_status: command.status,
          actual_status: command.status,
          command_executed: false
        )
      elsif matcher
        # Custom matcher verification
        recorder.setup_verification_stub(command)

        yield

        # Call custom matcher - convert command back to hash format for matcher
        recorded_data = command.to_h
        verified = matcher.call(recorded_data, recorder.verification_data)

        VerifyResult.new(
          verified: verified,
          record_path: Pathname.new(record_path),
          expected_output: command.stdout,
          actual_output: recorder.verification_data["stdout"],
          expected_stderr: command.stderr,
          actual_stderr: recorder.verification_data["stderr"],
          expected_status: command.status,
          actual_status: recorder.verification_data["status"]
        )
      else
        # Default strict mode
        recorder.setup_verification_stub(command)

        yield

        # Compare outputs
        actual_stdout = recorder.verification_data["stdout"]
        actual_stderr = recorder.verification_data["stderr"]
        actual_status = recorder.verification_data["status"]

        verified =
          command.stdout == actual_stdout &&
          command.stderr == actual_stderr &&
          command.status == actual_status

        VerifyResult.new(
          verified: verified,
          record_path: Pathname.new(record_path),
          expected_output: command.stdout,
          actual_output: actual_stdout,
          expected_stderr: command.stderr,
          actual_stderr: actual_stderr,
          expected_status: command.status,
          actual_status: actual_status
        )
      end
    end

    def verify!(record_name, mode: :strict, matcher: nil, &block)
      result = verify(record_name, mode: mode, matcher: matcher, &block)

      unless result.verified?
        error_message = "Backspin verification failed!\n"
        error_message += "Record: #{result.record_path}\n"
        error_message += "Expected output:\n#{result.expected_output}\n"
        error_message += "Actual output:\n#{result.actual_output}\n"

        if result.diff && !result.diff.empty?
          error_message += "Diff:\n#{result.diff}\n"
        end

        if result.stderr_diff && !result.stderr_diff.empty?
          error_message += "Stderr diff:\n#{result.stderr_diff}\n"
        end

        # Raise RSpec's expectation failure for proper integration
        raise RSpec::Expectations::ExpectationNotMetError, error_message
      end

      result
    end

    private

    def replay_record(record_path, &block)
      record = Record.load_or_create(record_path)
      unless record.exists?
        raise RecordNotFoundError, "Record not found: #{record_path}"
      end

      if record.empty?
        raise RecordNotFoundError, "No commands found in record"
      end

      # Create recorder in replay mode
      recorder = Recorder.new(mode: :replay, record: record)
      recorder.setup_replay_stubs

      block_return_value = yield

      # Return stdout, stderr, status if the block returned capture3 results
      # Otherwise return the block's return value
      if block_return_value.is_a?(Array) && block_return_value.size == 3 &&
          block_return_value[0].is_a?(String) && block_return_value[1].is_a?(String)
        # Convert status to integer for consistency
        stdout, stderr, status = block_return_value
        status_int = status.respond_to?(:exitstatus) ? status.exitstatus : status
        [stdout, stderr, status_int]
      else
        block_return_value
      end
    end

    def record_and_save_record(record_path, filter: nil, &block)
      # Create recorder to handle stubbing and command recording
      recorder = Recorder.new
      recorder.record_calls(:capture3, :system)

      block_return_value = yield

      # Save commands using new format
      FileUtils.mkdir_p(File.dirname(record_path))
      # Don't load existing data when creating new record
      record = Record.new(record_path)
      record.clear  # Clear any loaded data
      recorder.commands.each { |cmd| record.add_command(cmd) }
      record.save(filter: filter)

      # Return appropriate value
      if block_return_value.is_a?(Array) && block_return_value.size == 3
        # Return stdout, stderr, status as integers
        stdout, stderr, status = block_return_value
        [stdout, stderr, status.respond_to?(:exitstatus) ? status.exitstatus : status]
      else
        block_return_value
      end
    end

    def record_new_episode(record_path, filter: nil, &block)
      # For new_episodes mode, we'd need to track which commands have been seen
      # For now, simplified implementation that just appends
      record = Record.load_or_create(record_path)

      # Create recorder to handle stubbing and command recording
      recorder = Recorder.new
      recorder.record_calls(:capture3, :system)

      result = yield

      # Save all recordings (existing + new)
      if recorder.commands.any?
        recorder.commands.each { |cmd| record.add_command(cmd) }
        record.save(filter: filter)
      end

      # Return appropriate value
      if result.is_a?(Array) && result.size == 3
        stdout, stderr, status = result
        [stdout, stderr, status.respond_to?(:exitstatus) ? status.exitstatus : status]
      else
        result
      end
    end

    def build_record_path(name)
      backspin_dir = configuration.backspin_dir
      backspin_dir.mkpath

      File.join(backspin_dir, "#{name}.yaml")
    end
  end
end
