# frozen_string_literal: true

module Backspin
  # Result object for all Backspin record operations
  # Provides a consistent interface whether recording, verifying, or playing back
  class RecordResult
    attr_reader :output, :record_path, :commands, :mode, :command_diffs

    def initialize(output:, mode:, record_path:, commands:, verified: nil, command_diffs: nil)
      @output = output
      @mode = mode
      @record_path = record_path
      @commands = commands
      @verified = verified
      @command_diffs = command_diffs || []
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
      commands.first&.result&.stdout
    end

    # @return [String, nil] stderr from the first command
    def stderr
      commands.first&.result&.stderr
    end

    # @return [Integer, nil] exit status from the first command
    def status
      commands.first&.result&.status
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

      # Include number of failed commands if in verify mode
      hash[:failed_commands] = command_diffs.count { |d| !d.verified? } if mode == :verify && command_diffs.any?

      hash
    end

    # def inspect
    #   "#<Backspin::RecordResult mode=#{mode} verified=#{verified?.inspect} status=#{status}>"
    # end
  end
end
