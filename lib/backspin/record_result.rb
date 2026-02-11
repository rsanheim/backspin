# frozen_string_literal: true

module Backspin
  # Result object for all Backspin record operations
  # Provides a consistent interface whether recording, verifying, or playing back
  class RecordResult
    attr_reader :output, :mode, :command_diffs, :record, :recorded_commands, :actual_commands

    def initialize(output:, mode:, record:, verified: nil, command_diffs: nil, actual_commands: nil)
      @output = output
      @mode = mode
      @record = record
      @recorded_commands = record.commands
      @actual_commands = actual_commands || []
      @verified = verified
      @command_diffs = command_diffs || []
    end

    # Backwards-compatible alias for recorded commands.
    def commands
      recorded_commands
    end

    # @return [Boolean] true if this result is from recording
    def recorded?
      mode == :record
    end

    def record_path
      record.path
    end

    # @return [Boolean, nil] true/false for verification results, nil for recording
    def verified?
      return @verified unless mode == :verify

      return false if command_diffs.size < recorded_commands.size

      @verified
    end

    # @return [String, nil] Human-readable error message if verification failed
    def error_message
      return nil unless verified? == false

      # Check for command count mismatch first
      if command_diffs.size < recorded_commands.size
        return "Expected #{recorded_commands.size} commands but only #{command_diffs.size} were executed"
      end

      return "No commands to verify" if command_diffs.empty?

      failed_diffs = command_diffs.reject(&:verified?)
      return "All commands verified" if failed_diffs.empty?

      msg = "Output verification failed for #{failed_diffs.size} command(s):\n\n"

      command_diffs.each_with_index do |diff, idx|
        next if diff.verified?

        msg += "Command #{idx + 1}: #{diff.summary}\n"
        msg += diff.diff
        msg += "\n\n" if idx < command_diffs.size - 1
      end

      msg
    end

    # @return [String, nil] Combined diff from all failed commands
    def diff
      return nil if command_diffs.empty?

      failed_diffs = command_diffs.reject(&:verified?)
      return nil if failed_diffs.empty?

      diff_parts = []
      command_diffs.each_with_index do |cmd_diff, idx|
        diff_parts << "Command #{idx + 1}:\n#{cmd_diff.diff}" unless cmd_diff.verified?
      end

      diff_parts.join("\n\n")
    end

    # Convenience accessors for command output
    # For single command (common case), these provide direct access
    # For multiple commands, use all_stdout, all_stderr, etc.

    # @return [String, nil] stdout from the first command
    def stdout
      output_commands.first&.result&.stdout
    end

    # @return [String, nil] stderr from the first command
    def stderr
      output_commands.first&.result&.stderr
    end

    # @return [Integer, nil] exit status from the first command
    def status
      output_commands.first&.result&.status
    end

    # Multiple command accessors

    # @return [Array<String>] stdout from all commands
    def all_stdout
      output_commands.map { |cmd| cmd.result.stdout }
    end

    # @return [Array<String>] stderr from all commands
    def all_stderr
      output_commands.map { |cmd| cmd.result.stderr }
    end

    # @return [Array<Integer>] exit status from all commands
    def all_status
      output_commands.map { |cmd| cmd.result.status }
    end

    # Explicit accessors for the recorded (expected) command output.
    def expected_stdout
      recorded_commands.first&.result&.stdout
    end

    def expected_stderr
      recorded_commands.first&.result&.stderr
    end

    def expected_status
      recorded_commands.first&.result&.status
    end

    # Explicit accessors for the actual command output from this run.
    def actual_stdout
      actual_commands.first&.result&.stdout
    end

    def actual_stderr
      actual_commands.first&.result&.stderr
    end

    def actual_status
      actual_commands.first&.result&.status
    end

    # @return [Boolean] true if this result contains multiple commands
    def multiple_commands?
      output_commands.size > 1
    end

    # @return [Boolean] true if all commands succeeded (exit status 0)
    def success?
      if multiple_commands?
        # Check all commands - if any command has non-zero status, we're not successful
        output_commands.all? { |cmd| cmd.result.status.zero? }
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
        stdout: stdout,
        stderr: stderr,
        status: status
      }

      hash[:verified] = verified? unless verified?.nil?
      hash[:diff] = diff if diff
      # Include number of failed commands if in verify mode
      hash[:failed_commands] = command_diffs.count { |d| !d.verified? } if mode == :verify && command_diffs.any?

      hash
    end

    private

    def output_commands
      return actual_commands if mode == :verify && actual_commands.any?

      recorded_commands
    end
  end
end
