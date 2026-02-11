# frozen_string_literal: true

module Backspin
  # Handles matching logic between expected and actual snapshots.
  class Matcher
    attr_reader :config, :expected, :actual

    def initialize(config:, expected:, actual:)
      @config = normalize_config(config)
      @expected = expected
      @actual = actual
    end

    # @return [Boolean] true if snapshots match according to configured matcher
    def match?
      evaluation[:match]
    end

    # @return [String] reason why matching failed
    def failure_reason
      evaluation[:reason]
    end

    private

    def normalize_config(config)
      return nil if config.nil?
      return config if config.is_a?(Proc)

      raise ArgumentError, "Matcher must be a Proc or Hash, got #{config.class}" unless config.is_a?(Hash)

      # Validate hash keys and values
      config.each do |key, value|
        unless %i[all stdout stderr status].include?(key)
          raise ArgumentError, "Invalid matcher key: #{key}. Must be one of: :all, :stdout, :stderr, :status"
        end
        raise ArgumentError, "Matcher for #{key} must be callable (Proc/Lambda)" unless value.respond_to?(:call)
      end
      config
    end

    def evaluation
      @evaluation ||= if config.nil?
        evaluate_default
      elsif config.is_a?(Proc)
        evaluate_proc
      elsif config.is_a?(Hash)
        evaluate_hash
      else
        raise ArgumentError, "Invalid matcher type: #{config.class}"
      end
    end

    def evaluate_default
      reasons = []
      reasons << "stdout differs" if expected.stdout != actual.stdout
      reasons << "stderr differs" if expected.stderr != actual.stderr
      reasons << "exit status differs" if expected.status != actual.status

      {match: reasons.empty?, reason: reasons.join(", ")}
    end

    def evaluate_proc
      match = !!config.call(deep_dup(expected_hash), deep_dup(actual_hash))
      reason = match ? "" : "custom matcher failed"
      {match: match, reason: reason}
    end

    def evaluate_hash
      reasons = []

      config.each do |field, matcher_proc|
        passed = case field
        when :all
          matcher_proc.call(deep_dup(expected_hash), deep_dup(actual_hash))
        when :stdout, :stderr, :status
          matcher_proc.call(deep_dup(expected.public_send(field)), deep_dup(actual.public_send(field)))
        else
          raise ArgumentError, "Unknown field: #{field}"
        end

        next if passed

        reasons << ":all matcher failed" if field == :all
        reasons << "#{field} custom matcher failed" if %i[stdout stderr status].include?(field)
      end

      {match: reasons.empty?, reason: reasons.join(", ")}
    end

    def expected_hash
      @expected_hash ||= expected.to_h
    end

    def actual_hash
      @actual_hash ||= actual.to_h
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
  end
end
