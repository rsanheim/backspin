# frozen_string_literal: true

require "open3"
require "ostruct"
require "rspec/mocks"
require "backspin/command_result"
require "backspin/command_diff"

module Backspin
  # Handles stubbing and recording of command executions
  class Recorder
    include RSpec::Mocks::ExampleMethods
    SUPPORTED_COMMAND_TYPES = %i[capture3 system].freeze

    attr_reader :commands, :mode, :record, :options

    def initialize(mode: :record, record: nil, options: {})
      @mode = mode
      @record = record
      @options = options
      @commands = []
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
        raise ArgumentError,
          "Unsupported command type: #{command_type} - currently supported types: #{SUPPORTED_COMMAND_TYPES.join(", ")}"
      end
    end

    # Records registered commands, adds them to the record, saves the record, and returns the overall RecordResult
    def perform_recording
      result = yield
      record.save(filter: options[:filter])
      RecordResult.new(output: result, mode: :record, record: record)
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

        stdout, stderr, status = original_method.call(*args)

        actual_command = Command.new(
          method_class: Open3::Capture3,
          args: args,
          stdout: stdout,
          stderr: stderr,
          status: status.exitstatus
        )

        @command_diffs << CommandDiff.new(recorded_command: recorded_command, actual_command: actual_command, matcher: options[:matcher])
        @command_index += 1
        [stdout, stderr, status]
      end

      # Setup verification stubs for system
      allow_any_instance_of(Object).to receive(:system).and_wrap_original do |original_method, receiver, *args|
        recorded_command = record.commands[@command_index]

        result = original_method.call(receiver, *args)

        actual_command = Command.new(
          method_class: ::Kernel::System,
          args: args,
          stdout: "",
          stderr: "",
          status: result ? 0 : 1
        )

        # Create CommandDiff to track the comparison
        @command_diffs << CommandDiff.new(recorded_command: recorded_command, actual_command: actual_command, matcher: options[:matcher])

        @command_index += 1
        result
      end

      output = yield

      all_verified = @command_diffs.all?(&:verified?)

      RecordResult.new(
        output: output,
        mode: :verify,
        verified: all_verified,
        record: record,
        command_diffs: @command_diffs
      )
    end

    # Performs playback by returning recorded values without executing actual commands
    def perform_playback
      raise RecordNotFoundError, "Record not found: #{record.path}" unless record.exists?
      raise RecordNotFoundError, "No commands found in record" if record.empty?

      # Setup replay stubs
      setup_capture3_replay_stub
      setup_system_replay_stub

      # Execute block (all commands will be stubbed with recorded values)
      output = yield

      RecordResult.new(
        output: output,
        mode: :playback,
        verified: true, # Always true for playback
        record: record
      )
    end

    private

    def setup_capture3_replay_stub
      allow(Open3).to receive(:capture3) do |*_args|
        command = @record.next_command

        recorded_stdout = command.stdout
        recorded_stderr = command.stderr
        recorded_status = OpenStruct.new(exitstatus: command.status)

        [recorded_stdout, recorded_stderr, recorded_status]
      rescue NoMoreRecordingsError => e
        raise RecordNotFoundError, e.message
      end
    end

    def setup_system_replay_stub
      allow_any_instance_of(Object).to receive(:system) do |_receiver, *_args|
        command = @record.next_command

        command.status.zero?
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

        stdout = ""
        stderr = ""
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
