# frozen_string_literal: true

module Backspin
  # Represents the difference between a recorded command and actual execution
  # Handles verification and diff generation for a single command
  class CommandDiff
    attr_reader :recorded_command, :actual_command, :matcher

    def initialize(recorded_command:, actual_command:, matcher: nil)
      @recorded_command = recorded_command
      @actual_command = actual_command
      @matcher = Matcher.new(
        config: matcher,
        recorded_command: recorded_command,
        actual_command: actual_command
      )
    end

    # @return [Boolean] true if the command output matches
    def verified?
      return false unless method_classes_match?

      @matcher.match?
    end

    # @return [String, nil] Human-readable diff if not verified
    def diff
      return nil if verified?

      parts = []
      recorded_hash = recorded_command.to_h
      actual_hash = actual_command.to_h

      unless method_classes_match?
        parts << "Command type mismatch: expected #{recorded_command.method_class.name}, got #{actual_command.method_class.name}"
      end

      if recorded_hash["stdout"] != actual_hash["stdout"]
        parts << stdout_diff(recorded_hash["stdout"], actual_hash["stdout"])
      end

      if recorded_hash["stderr"] != actual_hash["stderr"]
        parts << stderr_diff(recorded_hash["stderr"], actual_hash["stderr"])
      end

      if recorded_hash["status"] != actual_hash["status"]
        parts << "Exit status: expected #{recorded_hash["status"]}, got #{actual_hash["status"]}"
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

    def method_classes_match?
      recorded_command.method_class == actual_command.method_class
    end

    def failure_reason
      unless method_classes_match?
        return "command type mismatch"
      end

      @matcher.failure_reason
    end

    def stdout_diff(expected, actual)
      "[stdout]\n#{generate_line_diff(expected, actual)}"
    end

    def stderr_diff(expected, actual)
      "[stderr]\n#{generate_line_diff(expected, actual)}"
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
