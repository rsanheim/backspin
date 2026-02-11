# frozen_string_literal: true

module Backspin
  # Represents the difference between expected and actual snapshots.
  class CommandDiff
    attr_reader :expected, :actual, :matcher

    def initialize(expected:, actual:, matcher: nil)
      @expected = expected
      @actual = actual
      @matcher = Matcher.new(
        config: matcher,
        expected: expected,
        actual: actual
      )
    end

    # @return [Boolean] true if the snapshot output matches.
    def verified?
      return false unless command_types_match?

      @matcher.match?
    end

    # @return [String, nil] Human-readable diff if not verified
    def diff
      return nil if verified?

      parts = []
      expected_hash = expected.to_h
      actual_hash = actual.to_h

      unless command_types_match?
        parts << "Command type mismatch: expected #{expected.command_type.name}, got #{actual.command_type.name}"
      end

      if expected_hash["stdout"] != actual_hash["stdout"]
        parts << stdout_diff(expected_hash["stdout"], actual_hash["stdout"])
      end

      if expected_hash["stderr"] != actual_hash["stderr"]
        parts << stderr_diff(expected_hash["stderr"], actual_hash["stderr"])
      end

      if expected_hash["status"] != actual_hash["status"]
        parts << "Exit status: expected #{expected_hash["status"]}, got #{actual_hash["status"]}"
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

    def command_types_match?
      expected.command_type == actual.command_type
    end

    def failure_reason
      unless command_types_match?
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
