# frozen_string_literal: true

module Backspin
  # Aggregate result returned by Backspin.run/capture.
  class BackspinResult
    attr_reader :mode, :record_path, :actual, :expected, :output

    def initialize(mode:, record_path:, actual:, expected: nil, verified: nil, command_diff: nil, output: nil)
      @mode = mode
      @record_path = record_path
      @actual = actual
      @expected = expected
      @verified = verified
      @command_diff = command_diff
      @output = output
    end

    def recorded?
      mode == :record
    end

    # true/false for verify mode, nil for record mode
    def verified?
      return nil if mode == :record

      @verified
    end

    def diff
      return nil unless verified? == false

      @command_diff&.diff
    end

    def error_message
      return nil unless verified? == false
      return "Output verification failed" unless @command_diff

      msg = "Output verification failed:\n\n"
      msg += @command_diff.summary
      msg += "\n#{@command_diff.diff}" if @command_diff.diff
      msg
    end

    def success?
      actual&.success? || false
    end

    def failure?
      !success?
    end

    def to_h
      hash = {
        mode: mode,
        record_path: record_path,
        actual: actual&.to_h
      }

      hash[:expected] = expected&.to_h
      hash[:verified] = verified? unless verified?.nil?
      hash[:diff] = diff if diff
      hash
    end
  end
end
