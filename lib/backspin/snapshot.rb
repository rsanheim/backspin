# frozen_string_literal: true

module Backspin
  # Represents a single captured execution snapshot.
  class Snapshot
    attr_reader :command_type, :args, :env, :stdin, :stdout, :stderr, :status, :recorded_at

    def initialize(command_type:, args:, env: nil, stdin: "", stdout: "", stderr: "", status: 0, recorded_at: nil, scrub: Backspin.configuration.scrub_credentials)
      @scrub = scrub
      @command_type = command_type
      @args = sanitize_args(args)
      @env = env.nil? ? nil : sanitize_env(env)
      @stdin = scrub_string((stdin || "").dup).freeze
      @stdout = scrub_string((stdout || "").dup).freeze
      @stderr = scrub_string((stderr || "").dup).freeze
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
        stdin: data["stdin"],
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
        "stdin" => stdin,
        "stdout" => stdout,
        "stderr" => stderr,
        "status" => status,
        "recorded_at" => recorded_at
      }
      data["env"] = env if env
      deep_freeze(data)
    end

    def scrub_string(text)
      @scrub ? Backspin.scrub_text(text) : text
    end

    def scrub_args(value)
      case value
      when String
        scrub_string(value)
      when Array
        value.map { |entry| scrub_args(entry) }
      when Hash
        value.transform_values { |entry| entry.is_a?(String) ? scrub_string(entry) : entry }
      else
        value
      end
    end

    def scrub_env(value)
      value.transform_values { |entry| entry.is_a?(String) ? scrub_string(entry) : entry }
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
