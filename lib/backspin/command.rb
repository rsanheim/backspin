module Backspin
  class Command
    attr_reader :args, :stdout, :stderr, :status, :recorded_at, :method_class

    def initialize(method_class:, args:, stdout: nil, stderr: nil, status: nil, recorded_at: nil)
      @method_class = method_class
      @args = args
      @stdout = stdout
      @stderr = stderr
      @status = status
      @recorded_at = recorded_at
    end

    # Convert to hash for YAML serialization
    def to_h(filter: nil)
      data = {
        "command_type" => @method_class.name,
        "args" => scrub_args(@args),
        "stdout" => Backspin.scrub_text(@stdout),
        "stderr" => Backspin.scrub_text(@stderr),
        "status" => @status,
        "recorded_at" => @recorded_at
      }

      # Apply filter if provided
      if filter
        data = filter.call(data)
      end

      data
    end

    # Create from hash (for loading from YAML)
    def self.from_h(data)
      # Determine method class from command_type
      method_class = case data["command_type"]
      when "Open3::Capture3"
        Open3::Capture3
      when "Kernel::System"
        ::Kernel::System
      else
        # Default to capture3 for backwards compatibility
        Open3::Capture3
      end

      new(
        method_class: method_class,
        args: data["args"],
        stdout: data["stdout"],
        stderr: data["stderr"],
        status: data["status"],
        recorded_at: data["recorded_at"]
      )
    end

    private

    def scrub_args(args)
      return args unless Backspin.configuration.scrub_credentials && args

      args.map do |arg|
        if arg.is_a?(String)
          Backspin.scrub_text(arg)
        elsif arg.is_a?(Array)
          scrub_args(arg)
        elsif arg.is_a?(Hash)
          arg.transform_values { |v| v.is_a?(String) ? Backspin.scrub_text(v) : v }
        else
          arg
        end
      end
    end
  end
end

# Define the Open3::Capture3 class for identification
module Open3
  class Capture3; end
end

# Define the Kernel::System class for identification
module ::Kernel
  class System; end
end
