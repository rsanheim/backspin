# frozen_string_literal: true

module Backspin
  # Represents the difference between a recorded command and actual execution
  # Handles verification and diff generation for a single command
  class CommandDiff
    attr_reader :recorded_command, :actual_result, :matcher, :match_on

    def initialize(recorded_command:, actual_result:, matcher: nil, match_on: nil)
      @recorded_command = recorded_command
      @actual_result = actual_result
      @matcher = matcher
      @match_on = normalize_match_on(match_on)
    end

    # @return [Boolean] true if the command output matches
    def verified?
      if matcher
        matcher.call(recorded_command.to_h, actual_result.to_h)
      elsif match_on
        verify_with_match_on
      else
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
      if match_on
        recorded_hash = recorded_command.to_h
        actual_hash = actual_result.to_h

        %w[stdout stderr status].each do |field|
          field_sym = field.to_sym
          custom_matcher = match_on.find { |f, _| f == field_sym }

          if custom_matcher
            _, matcher_proc = custom_matcher
            unless matcher_proc.call(recorded_hash[field], actual_hash[field])
              reasons << "#{field} custom matcher failed"
            end
          else
            unless recorded_hash[field] == actual_hash[field]
              reasons << "#{field} differs"
            end
          end
        end
      else
        reasons << "stdout differs" if recorded_command.stdout != actual_result.stdout
        reasons << "stderr differs" if recorded_command.stderr != actual_result.stderr
        reasons << "exit status differs" if recorded_command.status != actual_result.status
      end
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

    def normalize_match_on(match_on)
      return nil if match_on.nil?

      raise ArgumentError, "match_on must be an array" unless match_on.is_a?(Array)

      # Handle single field case: [:field, matcher]
      if match_on.length == 2 && match_on[0].is_a?(Symbol) && match_on[1].respond_to?(:call)
        [[match_on[0], match_on[1]]]
      else
        # Handle multiple fields case: [[:field1, matcher1], [:field2, matcher2]]
        match_on.map do |entry|
          unless entry.is_a?(Array) && entry.length == 2 && entry[0].is_a?(Symbol) && entry[1].respond_to?(:call)
            raise ArgumentError, "Each match_on entry must be [field_name, matcher_proc]"
          end
          entry
        end
      end
    end

    def verify_with_match_on
      recorded_hash = recorded_command.to_h
      actual_hash = actual_result.to_h

      # Validate field names
      match_on.each do |field_name, _|
        unless %i[stdout stderr status].include?(field_name)
          raise ArgumentError, "Invalid field name: #{field_name}. Must be one of: stdout, stderr, status"
        end
      end

      # Check each field
      %w[stdout stderr status].all? do |field|
        field_sym = field.to_sym
        custom_matcher = match_on.find { |f, _| f == field_sym }

        if custom_matcher
          # Use custom matcher for this field
          _, matcher_proc = custom_matcher
          matcher_proc.call(recorded_hash[field], actual_hash[field])
        else
          # Use exact equality for non-matched fields
          recorded_hash[field] == actual_hash[field]
        end
      end
    end
  end
end
