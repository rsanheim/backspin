# frozen_string_literal: true

module Backspin
  # Represents a single captured execution snapshot.
  class Snapshot
    attr_reader :command_type, :args, :env, :stdout, :stderr, :status, :recorded_at

    def initialize(command_type:, args:, env: nil, stdout: "", stderr: "", status: 0, recorded_at: nil)
      @command_type = command_type
      @args = sanitize_args(args)
      @env = env.nil? ? nil : sanitize_env(env)
      @stdout = Backspin.scrub_text((stdout || "").dup).freeze
      @stderr = Backspin.scrub_text((stderr || "").dup).freeze
      @status = status || 0
      @recorded_at = recorded_at.nil? ? nil : recorded_at.dup.freeze
      @serialized_hash = build_serialized_hash
    end

    def success?
      status.zero?
    end

    def failure?
      !success?
    end

    def to_h
      @serialized_hash
    end

    def self.from_h(data)
      command_type = case data["command_type"]
      when "Open3::Capture3"
        Open3::Capture3
      when "Backspin::Capturer"
        Backspin::Capturer
      else
        raise RecordFormatError, "Unknown command type: #{data["command_type"]}"
      end

      new(
        command_type: command_type,
        args: data["args"],
        env: data["env"],
        stdout: data["stdout"],
        stderr: data["stderr"],
        status: data["status"],
        recorded_at: data["recorded_at"]
      )
    end

    private

    def build_serialized_hash
      data = {
        "command_type" => command_type.name,
        "args" => args,
        "stdout" => stdout,
        "stderr" => stderr,
        "status" => status,
        "recorded_at" => recorded_at
      }
      data["env"] = env if env
      deep_freeze(data)
    end

    def scrub_args(value)
      return value unless Backspin.configuration.scrub_credentials && value

      case value
      when String
        Backspin.scrub_text(value)
      when Array
        value.map { |entry| scrub_args(entry) }
      when Hash
        value.transform_values { |entry| entry.is_a?(String) ? Backspin.scrub_text(entry) : entry }
      else
        value
      end
    end

    def scrub_env(value)
      return value unless Backspin.configuration.scrub_credentials && value

      value.transform_values { |entry| entry.is_a?(String) ? Backspin.scrub_text(entry) : entry }
    end

    def sanitize_args(value)
      deep_freeze(scrub_args(deep_dup(value)))
    end

    def sanitize_env(value)
      deep_freeze(scrub_env(deep_dup(value)))
    end

    def deep_freeze(value)
      case value
      when Hash
        value.each_value { |v| deep_freeze(v) }
      when Array
        value.each { |v| deep_freeze(v) }
      end
      value.freeze
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

# Define the Open3::Capture3 class for identification.
module Open3
  class Capture3; end
end

# Define the Backspin::Capturer class for identification.
module Backspin
  class Capturer; end
end
