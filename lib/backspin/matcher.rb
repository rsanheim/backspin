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
      if config.nil?
        default_matcher.call(expected.to_h, actual.to_h)
      elsif config.is_a?(Proc)
        config.call(expected.to_h, actual.to_h)
      elsif config.is_a?(Hash)
        verify_with_hash_matcher
      else
        raise ArgumentError, "Invalid matcher type: #{config.class}"
      end
    end

    # @return [String] reason why matching failed
    def failure_reason
      reasons = []

      if config.nil?
        expected_hash = expected.to_h
        actual_hash = actual.to_h

        reasons << "stdout differs" if expected_hash["stdout"] != actual_hash["stdout"]
        reasons << "stderr differs" if expected_hash["stderr"] != actual_hash["stderr"]
        reasons << "exit status differs" if expected_hash["status"] != actual_hash["status"]
      elsif config.is_a?(Hash)
        expected_hash = expected.to_h
        actual_hash = actual.to_h

        config.each do |field, matcher_proc|
          case field
          when :all
            reasons << ":all matcher failed" unless matcher_proc.call(expected_hash, actual_hash)
          when :stdout, :stderr, :status
            unless matcher_proc.call(expected_hash[field.to_s], actual_hash[field.to_s])
              reasons << "#{field} custom matcher failed"
            end
          end
        end
      else
        # Proc matcher
        reasons << "custom matcher failed"
      end

      reasons.join(", ")
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

    def verify_with_hash_matcher
      expected_hash = expected.to_h
      actual_hash = actual.to_h

      results = config.map do |field, matcher_proc|
        case field
        when :all
          matcher_proc.call(expected_hash, actual_hash)
        when :stdout, :stderr, :status
          matcher_proc.call(expected_hash[field.to_s], actual_hash[field.to_s])
        else
          raise ArgumentError, "Unknown field: #{field}"
        end
      end

      results.all?
    end

    def default_matcher
      @default_matcher ||= lambda do |recorded, actual|
        recorded["stdout"] == actual["stdout"] &&
          recorded["stderr"] == actual["stderr"] &&
          recorded["status"] == actual["status"]
      end
    end
  end
end
