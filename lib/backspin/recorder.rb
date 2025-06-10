require "open3"
require "ostruct"
require "rspec/mocks"
require "backspin/command_result"
require "backspin/command_diff"

module Backspin
  # Handles stubbing and recording of command executions
  class Recorder
    include RSpec::Mocks::ExampleMethods
    SUPPORTED_COMMAND_TYPES = [:capture3, :system]

    attr_reader :commands, :verification_data, :mode, :record, :options

    def initialize(mode: :record, record: nil, options: {})
      @mode = mode
      @record = record
      @options = options
      @commands = []
      @verification_data = {}
      @playback_index = 0
      @command_diffs = []
    end

    def setup_recording_stubs(*command_types)
      command_types = SUPPORTED_COMMAND_TYPES if command_types.empty?

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
        raise ArgumentError, "Unsupported command type: #{command_type} - currently supported types: #{SUPPORTED_COMMAND_TYPES.join(", ")}"
      end
    end

    # Records registered commands, adds them to the record, saves the record, and returns the overall RecordResult
    def perform_recording
      result = yield
      record.save(filter: options[:filter])
      RecordResult.new(output: result, mode: :record, record_path: record.path, commands: record.commands)
    end

    # Performs verification by executing commands and comparing with recorded values
    def perform_verification
      raise RecordNotFoundError, "Record not found: #{record.path}" unless record.exists?
      raise RecordNotFoundError, "No commands found in record" if record.empty?

      # Initialize tracking variables
      @command_diffs = []
      @command_index = 0

      # Setup verification stubs for capture3
      allow(Open3).to receive(:capture3).and_wrap_original do |original_method, *args|
        recorded_command = record.commands[@command_index]

        if recorded_command.nil?
          raise RecordNotFoundError, "No more recorded commands, but tried to execute: #{args.inspect}"
        end

        if recorded_command.method_class != Open3::Capture3
          raise RecordNotFoundError, "Expected #{recorded_command.method_class.name} but got Open3.capture3"
        end

        # Execute the actual command
        stdout, stderr, status = original_method.call(*args)

        # Create verification result
        actual_result = CommandResult.new(
          stdout: stdout,
          stderr: stderr,
          status: status.exitstatus
        )

        # Create CommandDiff to track the comparison
        @command_diffs << CommandDiff.new(
          recorded_command: recorded_command,
          actual_result: actual_result,
          matcher: options[:matcher],
          match_on: options[:match_on]
        )

        @command_index += 1
        [stdout, stderr, status]
      end

      # Setup verification stubs for system
      allow_any_instance_of(Object).to receive(:system).and_wrap_original do |original_method, receiver, *args|
        recorded_command = record.commands[@command_index]

        if recorded_command.nil?
          raise RecordNotFoundError, "No more recorded commands, but tried to execute: system #{args.inspect}"
        end

        if recorded_command.method_class != ::Kernel::System
          raise RecordNotFoundError, "Expected #{recorded_command.method_class.name} but got system"
        end

        # Execute the actual command
        result = original_method.call(receiver, *args)

        # Create verification result (system only gives us exit status)
        actual_result = CommandResult.new(
          stdout: "",
          stderr: "",
          status: result ? 0 : 1
        )

        # Create CommandDiff to track the comparison
        @command_diffs << CommandDiff.new(
          recorded_command: recorded_command,
          actual_result: actual_result,
          matcher: options[:matcher],
          match_on: options[:match_on]
        )

        @command_index += 1
        result
      end

      # Execute block
      output = yield

      # Check if all commands were executed
      if @command_index < record.commands.size
        raise RecordNotFoundError, "Expected #{record.commands.size} commands but only #{@command_index} were executed"
      end

      # Overall verification status
      all_verified = @command_diffs.all?(&:verified?)

      RecordResult.new(
        output: output,
        mode: :verify,
        verified: all_verified,
        record_path: record.path,
        commands: record.commands,
        command_diffs: @command_diffs
      )
    end

    # Performs playback by returning recorded values without executing actual commands
    def perform_playback
      raise RecordNotFoundError, "Record not found: #{record.path}" unless record.exists?
      raise RecordNotFoundError, "No commands found in record" if record.empty?

      # Setup replay stubs
      setup_replay_stubs

      # Execute block (all commands will be stubbed with recorded values)
      output = yield

      RecordResult.new(
        output: output,
        mode: :playback,
        verified: true, # Always true for playback
        record_path: record.path,
        commands: record.commands
      )
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

        unless command.method_class == ::Kernel::System
          raise RecordNotFoundError, "Expected Kernel::System command but got #{command.method_class.name}"
        end

        command.status == 0
      rescue NoMoreRecordingsError => e
        raise RecordNotFoundError, e.message
      end
    end

    def setup_capture3_call_stub
      allow(Open3).to receive(:capture3).and_wrap_original do |original_method, *args|
        stdout, stderr, status = original_method.call(*args)

        cmd_args = if args.length == 1 && args.first.is_a?(String)
          args.first.split(" ")
        else
          args
        end

        command = Command.new(
          method_class: Open3::Capture3,
          args: cmd_args,
          stdout: stdout,
          stderr: stderr,
          status: status.exitstatus,
          recorded_at: Time.now.iso8601
        )
        record.add_command(command)

        [stdout, stderr, status]
      end
    end

    def setup_system_call_stub
      allow_any_instance_of(Object).to receive(:system).and_wrap_original do |original_method, receiver, *args|
        result = original_method.call(receiver, *args)

        # Parse command args based on how system was called
        parsed_args = if args.empty? && receiver.is_a?(String)
          # Single string form - split the command string
          receiver.split(" ")
        else
          # Multi-arg form - already an array
          args
        end

        stdout, stderr = "", ""
        status = result ? 0 : 1

        command = Command.new(
          method_class: ::Kernel::System,
          args: parsed_args,
          stdout: stdout,
          stderr: stderr,
          status: status,
          recorded_at: Time.now.iso8601
        )
        record.add_command(command)

        result
      end
    end
  end
end
