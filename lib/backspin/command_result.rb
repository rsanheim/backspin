# frozen_string_literal: true

module Backspin
  # Represents the result of executing a command
  # Stores stdout, stderr, and exit status
  class CommandResult
    attr_reader :stdout, :stderr, :status

    def initialize(stdout:, stderr:, status:)
      @stdout = stdout
      @stderr = stderr
      @status = normalize_status(status)
    end

    # @return [Boolean] true if the command succeeded (exit status 0)
    def success?
      status.zero?
    end

    # @return [Boolean] true if the command failed (non-zero exit status)
    def failure?
      !success?
    end

    # @return [Hash] Hash representation of the result
    def to_h
      {
        'stdout' => stdout,
        'stderr' => stderr,
        'status' => status
      }
    end

    # Compare two results for equality
    def ==(other)
      return false unless other.is_a?(CommandResult)

      stdout == other.stdout &&
        stderr == other.stderr &&
        status == other.status
    end

    def inspect
      "#<Backspin::CommandResult status=#{status} stdout=#{stdout.inspect.truncate(50)} stderr=#{stderr.inspect.truncate(50)}>"
    end

    private

    def normalize_status(status)
      case status
      when Integer
        status
      when Process::Status
        status.exitstatus
      else
        status.respond_to?(:exitstatus) ? status.exitstatus : status.to_i
      end
    end
  end
end
