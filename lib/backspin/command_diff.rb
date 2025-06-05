# frozen_string_literal: true

module Backspin
  # Represents the difference between a recorded command and actual execution
  # Handles verification and diff generation for a single command
  class CommandDiff
    attr_reader :recorded_command, :actual_result, :matcher

    def initialize(recorded_command:, actual_result:, matcher: nil)
      @recorded_command = recorded_command
      @actual_result = actual_result
      @matcher = matcher
    end

    # @return [Boolean] true if the command output matches
    def verified?
      if matcher
        # Use custom matcher if provided
        matcher.call(recorded_command.to_h, actual_result.to_h)
      else
        # Default strict comparison
        recorded_command.result == actual_result
      end
    end

    # @return [String, nil] Human-readable diff if not verified
    def diff
      return nil if verified?

      parts = []

      parts << stdout_diff if recorded_command.stdout != actual_result.stdout

      parts << stderr_diff if recorded_command.stderr != actual_result.stderr

      if recorded_command.status != actual_result.status
        parts << "Exit status: expected #{recorded_command.status}, got #{actual_result.status}"
      end

      parts.join("\n\n")
    end

    # @return [String] Single line summary for error messages
    def summary
      if verified?
        "✓ Command verified"
      else
        "✗ Command failed: #{failure_reason}"
      end
    end

    private

    def failure_reason
      reasons = []
      reasons << "stdout differs" if recorded_command.stdout != actual_result.stdout
      reasons << "stderr differs" if recorded_command.stderr != actual_result.stderr
      reasons << "exit status differs" if recorded_command.status != actual_result.status
      reasons.join(", ")
    end

    def stdout_diff
      "stdout diff:\n#{generate_line_diff(recorded_command.stdout, actual_result.stdout)}"
    end

    def stderr_diff
      "stderr diff:\n#{generate_line_diff(recorded_command.stderr, actual_result.stderr)}"
    end

    def generate_line_diff(expected, actual)
      expected_lines = (expected || "").lines
      actual_lines = (actual || "").lines

      diff_lines = []
      max_lines = [expected_lines.length, actual_lines.length].max

      max_lines.times do |i|
        expected_line = expected_lines[i]
        actual_line = actual_lines[i]

        if expected_line != actual_line
          diff_lines << "-#{expected_line.chomp}" if expected_line
          diff_lines << "+#{actual_line.chomp}" if actual_line
        end
      end

      diff_lines.join("\n")
    end
  end
end
