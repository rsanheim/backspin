# frozen_string_literal: true

module Backspin
  # Represents the difference between expected and actual snapshots.
  class CommandDiff
    CONTEXT_LINES = 3
    MAX_DIFF_LINES = 50

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

    # @return [Array<String>] Per-field change status lines
    def field_summary
      lines = []
      lines << stdout_field_summary
      lines << stderr_field_summary
      lines << status_field_summary
      lines
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

      result = parts.join("\n\n")
      maybe_truncate(result)
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

    def stdout_field_summary
      if expected_compare.stdout == actual_compare.stdout
        "stdout: unchanged"
      else
        "stdout: changed"
      end
    end

    def stderr_field_summary
      if expected_compare.stderr == actual_compare.stderr
        "stderr: unchanged"
      else
        "stderr: changed"
      end
    end

    def status_field_summary
      if expected_compare.status == actual_compare.status
        "status: unchanged"
      else
        "status: changed (expected #{expected_compare.status}, actual #{actual_compare.status})"
      end
    end

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
      expected_lines = split_lines(expected)
      actual_lines = split_lines(actual)
      max_lines = [expected_lines.length, actual_lines.length].max

      changed = Array.new(max_lines, false)
      max_lines.times do |i|
        changed[i] = (expected_lines[i] != actual_lines[i])
      end

      visible = Array.new(max_lines, false)
      max_lines.times do |i|
        next unless changed[i]
        range_start = [i - CONTEXT_LINES, 0].max
        range_end = [i + CONTEXT_LINES, max_lines - 1].min
        (range_start..range_end).each { |j| visible[j] = true }
      end

      diff_lines = []
      in_hunk = false

      max_lines.times do |i|
        unless visible[i]
          if in_hunk
            diff_lines << "..."
            in_hunk = false
          end
          next
        end

        in_hunk = true

        if changed[i]
          diff_lines << "-#{render_line(expected_lines[i])}" if i < expected_lines.length
          diff_lines << "+#{render_line(actual_lines[i])}" if i < actual_lines.length
        else
          line = expected_lines[i] || actual_lines[i]
          diff_lines << " #{render_line(line)}"
        end
      end

      diff_lines.join("\n")
    end

    def split_lines(value)
      (value || "").lines
    end

    def render_line(line)
      line.to_s.chomp
    end

    def maybe_truncate(diff_text)
      return diff_text if full_diff?

      lines = diff_text.lines
      return diff_text if lines.length <= MAX_DIFF_LINES

      truncated = lines.first(MAX_DIFF_LINES).join
      truncated.chomp!
      truncated + "\n(diff truncated, set BACKSPIN_FULL_DIFF=1 for full output)"
    end

    def full_diff?
      ENV["BACKSPIN_FULL_DIFF"] == "1"
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
