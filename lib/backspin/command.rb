# frozen_string_literal: true

require_relative "command_result"

module Backspin
  class Command
    attr_reader :args, :env, :result, :recorded_at, :method_class

    def initialize(method_class:, args:, env: nil, stdout: nil, stderr: nil, status: nil, result: nil, recorded_at: nil)
      @method_class = method_class
      @args = args
      @env = env
      @recorded_at = recorded_at

      # Accept either a CommandResult or individual stdout/stderr/status
      @result = result || CommandResult.new(stdout: stdout || "", stderr: stderr || "", status: status || 0)
    end

    def stdout
      @result.stdout
    end

    def stderr
      @result.stderr
    end

    def status
      @result.status
    end

    # Convert to hash for YAML serialization
    def to_h(filter: nil)
      data = {
        "command_type" => @method_class.name,
        "args" => scrub_args(@args),
        "stdout" => Backspin.scrub_text(@result.stdout),
        "stderr" => Backspin.scrub_text(@result.stderr),
        "status" => @result.status,
        "recorded_at" => @recorded_at
      }

      data["env"] = scrub_env(@env) if @env

      # Apply filter if provided
      data = filter.call(data) if filter

      data
    end

    # Create from hash (for loading from YAML)
    def self.from_h(data)
      # Determine method class from command_type
      method_class = case data["command_type"]
      when "Open3::Capture3"
        Open3::Capture3
      when "Backspin::Capturer"
        Backspin::Capturer
      else
        raise RecordFormatError, "Unknown command type: #{data["command_type"]}"
      end

      new(
        method_class: method_class,
        args: data["args"],
        env: data["env"],
        stdout: data["stdout"],
        stderr: data["stderr"],
        status: data["status"],
        recorded_at: data["recorded_at"]
      )
    end

    private

    def scrub_args(args)
      return args unless Backspin.configuration.scrub_credentials && args

      case args
      when String
        Backspin.scrub_text(args)
      when Array
        args.map do |arg|
          case arg
          when String
            Backspin.scrub_text(arg)
          when Array
            scrub_args(arg)
          when Hash
            arg.transform_values { |v| v.is_a?(String) ? Backspin.scrub_text(v) : v }
          else
            arg
          end
        end
      when Hash
        args.transform_values { |v| v.is_a?(String) ? Backspin.scrub_text(v) : v }
      else
        args
      end
    end

    def scrub_env(env)
      return env unless Backspin.configuration.scrub_credentials && env

      env.transform_values { |value| value.is_a?(String) ? Backspin.scrub_text(value) : value }
    end
  end
end

# Define the Open3::Capture3 class for identification
module Open3
  class Capture3; end
end

# Define the Backspin::Capturer class for identification
module Backspin
  class Capturer; end
end
