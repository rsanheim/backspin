# frozen_string_literal: true

module Backspin
  # Represents a single captured execution snapshot.
  class Snapshot
    attr_reader :command_type, :args, :env, :stdout, :stderr, :status, :recorded_at

    def initialize(command_type:, args:, env: nil, stdout: "", stderr: "", status: 0, recorded_at: nil)
      @command_type = command_type
      @args = args
      @env = env
      @stdout = stdout || ""
      @stderr = stderr || ""
      @status = status || 0
      @recorded_at = recorded_at
    end

    def success?
      status.zero?
    end

    def failure?
      !success?
    end

    def to_h(filter: nil)
      return base_hash if filter.nil?

      filter.call(deep_dup(base_hash))
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

    def base_hash
      @base_hash ||= begin
        data = {
          "command_type" => command_type.name,
          "args" => scrub_args(args),
          "stdout" => Backspin.scrub_text(stdout),
          "stderr" => Backspin.scrub_text(stderr),
          "status" => status,
          "recorded_at" => recorded_at
        }
        data["env"] = scrub_env(env) if env
        deep_freeze(data)
      end
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
        value.transform_values { |v| deep_dup(v) }
      when Array
        value.map { |v| deep_dup(v) }
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
