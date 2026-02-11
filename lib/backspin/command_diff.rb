# frozen_string_literal: true

module Backspin
  # Represents the difference between expected and actual snapshots.
  class CommandDiff
    attr_reader :expected, :actual, :matcher

    def initialize(expected:, actual:, matcher: nil, filter: nil, filter_on: :both)
      @expected = expected
      @actual = actual
      @expected_compare = build_comparison_snapshot(expected, filter: filter, filter_on: filter_on)
      @actual_compare = build_comparison_snapshot(actual, filter: filter, filter_on: filter_on)
      @matcher = Matcher.new(
        config: matcher,
        expected: @expected_compare,
        actual: @actual_compare
      )
      @verified = nil
    end

    # @return [Boolean] true if the snapshot output matches.
    def verified?
      return @verified unless @verified.nil?
      return @verified = false unless command_types_match?

      @verified = @matcher.match?
    end

    # @return [String, nil] Human-readable diff if not verified
    def diff
      return nil if verified?

      parts = []

      unless command_types_match?
        parts << "Command type mismatch: expected #{expected.command_type.name}, got #{actual.command_type.name}"
      end

      if expected_compare.stdout != actual_compare.stdout
        parts << stdout_diff(expected_compare.stdout, actual_compare.stdout)
      end

      if expected_compare.stderr != actual_compare.stderr
        parts << stderr_diff(expected_compare.stderr, actual_compare.stderr)
      end

      if expected_compare.status != actual_compare.status
        parts << "Exit status: expected #{expected_compare.status}, got #{actual_compare.status}"
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

    attr_reader :expected_compare

    attr_reader :actual_compare

    def build_comparison_snapshot(snapshot, filter:, filter_on:)
      data = deep_dup(snapshot.to_h)
      if filter && filter_on == :both
        data = filter.call(data)
      end

      ComparisonSnapshot.new(
        command_type: snapshot.command_type,
        data: deep_freeze(data)
      )
    end

    def deep_dup(value)
      case value
      when Hash
        value.transform_values { |entry| deep_dup(entry) }
      when Array
        value.map { |entry| deep_dup(entry) }
      when String
        value.dup
      else
        value
      end
    end

    def deep_freeze(value)
      case value
      when Hash
        value.each_value { |entry| deep_freeze(entry) }
      when Array
        value.each { |entry| deep_freeze(entry) }
      end
      value.freeze
    end

    class ComparisonSnapshot
      attr_reader :command_type, :stdout, :stderr, :status

      def initialize(command_type:, data:)
        @command_type = command_type
        @data = data
        @stdout = data["stdout"]
        @stderr = data["stderr"]
        @status = data["status"]
      end

      def to_h
        @data
      end
    end
  end
end
