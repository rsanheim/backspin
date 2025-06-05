# frozen_string_literal: true

module Backspin
  # Unified result object for all Backspin operations
  # Provides a consistent interface whether recording, verifying, or playing back
  class UnifiedResult
    attr_reader :output, :record_path, :commands, :mode, :expected_output, :actual_output, :expected_stderr,
                :actual_stderr, :expected_status, :actual_status, :diff, :verified_commands

    def initialize(output:, mode:, record_path:, commands:, verified: nil,
                   expected_output: nil, actual_output: nil,
                   expected_stderr: nil, actual_stderr: nil,
                   expected_status: nil, actual_status: nil,
                   diff: nil, verified_commands: nil)
      @output = output
      @mode = mode
      @record_path = record_path
      @commands = commands
      @verified = verified
      @expected_output = expected_output
      @actual_output = actual_output
      @expected_stderr = expected_stderr
      @actual_stderr = actual_stderr
      @expected_status = expected_status
      @actual_status = actual_status
      @diff = diff
      @verified_commands = verified_commands
    end

    # @return [Boolean] true if this result is from recording
    def recorded?
      mode == :record
    end

    # @return [Boolean, nil] true/false for verification results, nil for recording
    def verified?
      @verified
    end

    # @return [Boolean] true if this result is from playback mode
    def playback?
      mode == :playback
    end

    # @return [String, nil] Human-readable error message if verification failed
    def error_message
      return nil unless verified? == false

      msg = 'Output verification failed'
      msg += "\nExpected: #{expected_output.inspect}" if expected_output
      msg += "\nActual: #{actual_output.inspect}" if actual_output
      msg += "\n#{diff}" if diff
      msg
    end

    # Convenience accessors for command output
    # For single command (common case), these provide direct access
    # For multiple commands, use all_stdout, all_stderr, etc.

    # @return [String, nil] stdout from the first command
    def stdout
      return commands.first.result.stdout if commands.any?
      return actual_output if actual_output # backwards compatibility

      nil
    end

    # @return [String, nil] stderr from the first command
    def stderr
      return commands.first.result.stderr if commands.any?
      return actual_stderr if actual_stderr # backwards compatibility

      nil
    end

    # @return [Integer, nil] exit status from the first command
    def status
      return commands.first.result.status if commands.any?
      return actual_status if actual_status # backwards compatibility

      nil
    end

    # Multiple command accessors

    # @return [Array<String>] stdout from all commands
    def all_stdout
      commands.map { |cmd| cmd.result.stdout }
    end

    # @return [Array<String>] stderr from all commands
    def all_stderr
      commands.map { |cmd| cmd.result.stderr }
    end

    # @return [Array<Integer>] exit status from all commands
    def all_status
      commands.map { |cmd| cmd.result.status }
    end

    # @return [Boolean] true if this result contains multiple commands
    def multiple_commands?
      commands.size > 1
    end

    # @return [Boolean] true if all commands succeeded (exit status 0)
    def success?
      if multiple_commands?
        # Check all commands - if any command has non-zero status, we're not successful
        commands.all? { |cmd| cmd.result.status.zero? }
      else
        status&.zero? || false
      end
    end

    # @return [Boolean] true if any command failed (non-zero exit status)
    def failure?
      !success?
    end

    # @return [Hash] Summary of the result for debugging
    def to_h
      hash = {
        mode: mode,
        recorded: recorded?,
        playback: playback?,
        stdout: stdout,
        stderr: stderr,
        status: status,
        record_path: record_path.to_s
      }

      # Only include verified if it's not nil
      hash[:verified] = verified? unless verified?.nil?

      # Only include diff if present
      hash[:diff] = diff if diff

      hash
    end

    def inspect
      "#<Backspin::UnifiedResult mode=#{mode} verified=#{verified?.inspect} status=#{status}>"
    end
  end
end
