# frozen_string_literal: true

module Backspin
  # Handles matching logic between recorded and actual commands
  class Matcher
    attr_reader :config, :recorded_command, :actual_command

    def initialize(config:, recorded_command:, actual_command:)
      @config = normalize_config(config)
      @recorded_command = recorded_command
      @actual_command = actual_command
    end

    # @return [Boolean] true if commands match according to the configured matcher
    def match?
      if config.nil?
        # Default behavior: check all fields for equality
        default_matcher.call(recorded_command.to_h, actual_command.to_h)
      elsif config.is_a?(Proc)
        config.call(recorded_command.to_h, actual_command.to_h)
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
        # Default matcher checks all fields
        recorded_hash = recorded_command.to_h
        actual_hash = actual_command.to_h

        reasons << "stdout differs" if recorded_hash["stdout"] != actual_hash["stdout"]
        reasons << "stderr differs" if recorded_hash["stderr"] != actual_hash["stderr"]
        reasons << "exit status differs" if recorded_hash["status"] != actual_hash["status"]
      elsif config.is_a?(Hash)
        recorded_hash = recorded_command.to_h
        actual_hash = actual_command.to_h

        # Only check matchers that were provided
        config.each do |field, matcher_proc|
          case field
          when :all
            reasons << ":all matcher failed" unless matcher_proc.call(recorded_hash, actual_hash)
          when :stdout, :stderr, :status
            unless matcher_proc.call(recorded_hash[field.to_s], actual_hash[field.to_s])
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
      recorded_hash = recorded_command.to_h
      actual_hash = actual_command.to_h

      # Override-based: only run matchers that are explicitly provided
      # Use map to ensure all matchers run, then check if all passed
      results = config.map do |field, matcher_proc|
        case field
        when :all
          matcher_proc.call(recorded_hash, actual_hash)
        when :stdout, :stderr, :status
          matcher_proc.call(recorded_hash[field.to_s], actual_hash[field.to_s])
        else
          # This should never happen due to normalize_config validation
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
