require "open3"
require "ostruct"
require "rspec/mocks"

module Backspin
  # Handles stubbing and recording of command executions
  class Recorder
    include RSpec::Mocks::ExampleMethods

    attr_reader :commands, :verification_data, :mode, :record

    def initialize(mode: :record, record: nil)
      @mode = mode
      @record = record
      @commands = []
      @verification_data = {}
    end

    def record_calls(*command_types)
      command_types = [:capture3, :system] if command_types.empty?

      command_types.each do |command_type|
        record_call(command_type)
      end
    end

    def record_call(command_type)
      case command_type
      when :system
        setup_system_call_stub
      when :capture3
        setup_capture3_call_stub
      else
        raise ArgumentError, "Unknown command type: #{command_type}"
      end
    end

    # Setup stubs for playback mode - just return recorded values
    def setup_playback_stub(command)
      if command.method_class == Open3::Capture3
        actual_status = OpenStruct.new(exitstatus: command.status)
        allow(Open3).to receive(:capture3).and_return([command.stdout, command.stderr, actual_status])
      elsif command.method_class == ::Kernel::System
        # For system, return true if exit status was 0
        allow_any_instance_of(Object).to receive(:system).and_return(command.status == 0)
      end
    end

    # Setup stubs for verification - capture actual output
    def setup_verification_stub(command)
      @verification_data = {}

      if command.method_class == Open3::Capture3
        allow(Open3).to receive(:capture3).and_wrap_original do |original_method, *args|
          stdout, stderr, status = original_method.call(*args)
          @verification_data["stdout"] = stdout
          @verification_data["stderr"] = stderr
          @verification_data["status"] = status.exitstatus
          [stdout, stderr, status]
        end
      elsif command.method_class == ::Kernel::System
        allow_any_instance_of(Object).to receive(:system).and_wrap_original do |original_method, receiver, *args|
          # Execute the real system call
          result = original_method.call(receiver, *args)

          # For system calls, we only track the exit status
          @verification_data["stdout"] = ""
          @verification_data["stderr"] = ""
          # Derive exit status from result: true = 0, false = non-zero
          @verification_data["status"] = result ? 0 : 1

          result
        end
      end
    end

    # Setup stubs for replay mode - returns recorded values for multiple commands
    def setup_replay_stubs
      raise ArgumentError, "Record required for replay mode" unless @record

      setup_capture3_replay_stub
      setup_system_replay_stub
    end

    private

    def setup_capture3_replay_stub
      allow(Open3).to receive(:capture3) do |*args|
        command = @record.next_command

        # Make sure this is a capture3 command
        unless command.method_class == Open3::Capture3
          raise RecordNotFoundError, "Expected Open3::Capture3 command but got #{command.method_class.name}"
        end

        recorded_stdout = command.stdout
        recorded_stderr = command.stderr
        recorded_status = OpenStruct.new(exitstatus: command.status)

        [recorded_stdout, recorded_stderr, recorded_status]
      rescue NoMoreRecordingsError => e
        raise RecordNotFoundError, e.message
      end
    end

    def setup_system_replay_stub
      allow_any_instance_of(Object).to receive(:system) do |receiver, *args|
        command = @record.next_command

        # Make sure this is a system command
        unless command.method_class == ::Kernel::System
          raise RecordNotFoundError, "Expected Kernel::System command but got #{command.method_class.name}"
        end

        # Return true if exit status was 0, false otherwise
        command.status == 0
      rescue NoMoreRecordingsError => e
        raise RecordNotFoundError, e.message
      end
    end

    def setup_capture3_call_stub
      allow(Open3).to receive(:capture3).and_wrap_original do |original_method, *args|
        # Execute the real command
        stdout, stderr, status = original_method.call(*args)

        # Parse command args
        cmd_args = if args.length == 1 && args.first.is_a?(String)
          args.first.split(" ")
        else
          args
        end

        # Create command with interaction data
        command = Command.new(
          method_class: Open3::Capture3,
          args: cmd_args,
          stdout: stdout,
          stderr: stderr,
          status: status.exitstatus,
          recorded_at: Time.now.iso8601
        )
        @commands << command

        # Return original result
        [stdout, stderr, status]
      end
    end

    def setup_system_call_stub
      allow_any_instance_of(Object).to receive(:system).and_wrap_original do |original_method, receiver, *args|
        # Execute the real system call
        result = original_method.call(receiver, *args)

        # Parse command args based on how system was called
        parsed_args = if args.empty? && receiver.is_a?(String)
          # Single string form - split the command string
          receiver.split(" ")
        else
          # Multi-arg form - already an array
          args
        end

        # For system calls, stdout and stderr are not captured
        # The caller of system() doesn't have access to them
        stdout = ""
        stderr = ""
        # Derive exit status from result: true = 0, false = non-zero, nil = command failed
        status = result ? 0 : 1

        # Create command with interaction data
        command = Command.new(
          method_class: ::Kernel::System,
          args: parsed_args,
          stdout: stdout,
          stderr: stderr,
          status: status,
          recorded_at: Time.now.iso8601
        )
        @commands << command

        # Return the original result (true/false/nil)
        result
      end
    end
  end
end
