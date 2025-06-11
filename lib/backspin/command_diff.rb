# frozen_string_literal: true

module Backspin
  # Represents the difference between a recorded command and actual execution
  # Handles verification and diff generation for a single command
  class CommandDiff
    attr_reader :recorded_command, :actual_command, :matcher

    def initialize(recorded_command:, actual_command:, matcher: nil)
      @recorded_command = recorded_command
      @actual_command = actual_command
      @matcher = normalize_matcher(matcher)
    end

    # @return [Boolean] true if the command output matches
    def verified?
      # First check if method classes match
      return false unless method_classes_match?

      if matcher.nil?
        recorded_command.result == actual_command.result
      elsif matcher.is_a?(Proc) # basic all matcher: lambda { |recorded, actual| ...}
        matcher.call(recorded_command.to_h, actual_command.to_h)
      elsif matcher.is_a?(Hash) # matcher: {all: lambda { |recorded, actual| ...}, stdout: lambda { |recorded, actual| ...}}
        verify_with_hash_matcher
      else
        raise ArgumentError, "Invalid matcher type: #{matcher.class}"
      end
    end

    # @return [String, nil] Human-readable diff if not verified
    def diff
      return nil if verified?

      parts = []

      # Check method class mismatch first
      unless method_classes_match?
        parts << "Command type mismatch: expected #{recorded_command.method_class.name}, got #{actual_command.method_class.name}"
      end

      parts << stdout_diff if recorded_command.stdout != actual_command.stdout

      parts << stderr_diff if recorded_command.stderr != actual_command.stderr

      if recorded_command.status != actual_command.status
        parts << "Exit status: expected #{recorded_command.status}, got #{actual_command.status}"
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

    def normalize_matcher(matcher)
      return nil if matcher.nil?
      return matcher if matcher.is_a?(Proc)

      raise ArgumentError, "Matcher must be a Proc or Hash, got #{matcher.class}" unless matcher.is_a?(Hash)

      # Validate hash keys and values
      matcher.each do |key, value|
        unless %i[all stdout stderr status].include?(key)
          raise ArgumentError, "Invalid matcher key: #{key}. Must be one of: :all, :stdout, :stderr, :status"
        end
        raise ArgumentError, "Matcher for #{key} must be callable (Proc/Lambda)" unless value.respond_to?(:call)
      end
      matcher
    end

    def verify_with_hash_matcher
      recorded_hash = recorded_command.to_h
      actual_hash = actual_command.to_h

      all_passed = matcher[:all].nil? || matcher[:all].call(recorded_hash, actual_hash)

      fields_passed = %w[stdout stderr status].all? do |field|
        field_sym = field.to_sym
        if matcher[field_sym]
          matcher[field_sym].call(recorded_hash[field], actual_hash[field])
        else
          recorded_hash[field] == actual_hash[field]
        end
      end

      all_passed && fields_passed
    end

    def failure_reason
      reasons = []

      # Check method class first
      unless method_classes_match?
        reasons << "command type mismatch"
        return reasons.join(", ")
      end

      if matcher.nil?
        reasons << "stdout differs" if recorded_command.stdout != actual_command.stdout
        reasons << "stderr differs" if recorded_command.stderr != actual_command.stderr
        reasons << "exit status differs" if recorded_command.status != actual_command.status
      elsif matcher.is_a?(Hash)
        recorded_hash = recorded_command.to_h
        actual_hash = actual_command.to_h

        # Check :all matcher first
        reasons << ":all matcher failed" if matcher[:all] && !matcher[:all].call(recorded_hash, actual_hash)

        # Check field-specific matchers
        %w[stdout stderr status].each do |field|
          field_sym = field.to_sym
          if matcher[field_sym]
            unless matcher[field_sym].call(recorded_hash[field], actual_hash[field])
              reasons << "#{field} custom matcher failed"
            end
          elsif recorded_hash[field] != actual_hash[field]
            # Always check exact equality for fields without matchers
            reasons << "#{field} differs"
          end
        end
      else
        # Proc matcher
        reasons << "custom matcher failed"
      end

      reasons.join(", ")
    end

    def stdout_diff
      "stdout diff:\n#{generate_line_diff(recorded_command.stdout, actual_command.stdout)}"
    end

    def stderr_diff
      "stderr diff:\n#{generate_line_diff(recorded_command.stderr, actual_command.stderr)}"
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
