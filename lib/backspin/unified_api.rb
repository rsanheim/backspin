# frozen_string_literal: true

require_relative "unified_result"
require_relative "command_result"

module Backspin
  class << self
    # Primary API - records on first run, verifies on subsequent runs
    #
    # @param record_name [String] Name for the record file
    # @param options [Hash] Options for recording/verification
    # @option options [Symbol] :mode (:auto) Recording mode - :auto, :record, :verify, :playback
    # @option options [Proc] :filter Custom filter for recorded data
    # @option options [Proc] :matcher Custom matcher for verification
    # @return [UnifiedResult] Result object with output and status
    def run(record_name, options = {}, &block)
      raise ArgumentError, "record_name is required" if record_name.nil? || record_name.empty?
      raise ArgumentError, "block is required" unless block_given?

      record_path = build_record_path(record_name)
      mode = determine_mode(options[:mode], record_path)

      case mode
      when :record
        perform_recording(record_name, record_path, options, &block)
      when :verify
        perform_verification(record_name, record_path, options, &block)
      when :playback
        perform_playback(record_name, record_path, options, &block)
      else
        raise ArgumentError, "Unknown mode: #{mode}"
      end
    end

    # Strict version of run that raises on verification failure
    #
    # @param record_name [String] Name for the record file
    # @param options [Hash] Options for recording/verification
    # @return [UnifiedResult] Result object with output and status
    # @raise [RSpec::Expectations::ExpectationNotMetError] If verification fails
    def run!(record_name, options = {}, &block)
      result = run(record_name, options, &block)

      if result.verified? == false
        error_message = "Backspin verification failed!\n"
        error_message += "Record: #{result.record_path}\n"

        if result.multiple_commands?
          error_message += "#{result.commands.size} commands recorded\n"

          # Show details for each failed command
          result.verified_commands&.each_with_index do |vc, idx|
            next if vc[:verified]

            error_message += "\nCommand #{idx + 1} failed:\n"
            error_message += "Expected: #{vc[:command].stdout.inspect}\n"
            error_message += "Actual: #{vc[:actual].stdout.inspect}\n"
          end
        elsif result.expected_output && result.actual_output
          error_message += "Expected output:\n#{result.expected_output}\n"
          error_message += "Actual output:\n#{result.actual_output}\n"
        end

        error_message += "\nDiff:\n#{result.diff}\n" if result.diff && !result.diff.empty?

        raise RSpec::Expectations::ExpectationNotMetError, error_message
      end

      result
    end

    private

    def determine_mode(mode_option, record_path)
      return mode_option if mode_option && mode_option != :auto

      # Auto mode: record if file doesn't exist, verify if it does
      File.exist?(record_path) ? :verify : :record
    end

    def perform_recording(_record_name, record_path, options)
      recorder = Recorder.new
      recorder.record_calls(:capture3, :system)

      # Execute the block and capture output
      output = yield

      # Normalize status if it's a capture3 result
      if output.is_a?(Array) && output.size == 3
        stdout, stderr, status = output
        status_int = status.respond_to?(:exitstatus) ? status.exitstatus : status
        output = [stdout, stderr, status_int]
      end

      # Save the recording
      FileUtils.mkdir_p(File.dirname(record_path))
      record = Record.new(record_path)
      record.clear
      recorder.commands.each { |cmd| record.add_command(cmd) }
      record.save(filter: options[:filter])

      # Return result
      UnifiedResult.new(
        output: output,
        mode: :record,
        record_path: Pathname.new(record_path),
        commands: recorder.commands
      )
    end

    def perform_verification(_record_name, record_path, options)
      record = Record.load_or_create(record_path)

      raise RecordNotFoundError, "Record not found: #{record_path}" unless record.exists?
      raise RecordNotFoundError, "No commands found in record" if record.empty?

      # For verification, we need to track all commands executed
      recorder = Recorder.new(mode: :verify, record: record)
      recorder.setup_replay_stubs

      # Track verification results for each command
      verified_commands = []
      command_index = 0

      # Override stubs to verify each command as it's executed
      allow(Open3).to receive(:capture3).and_wrap_original do |original_method, *args|
        recorded_command = record.commands[command_index]

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

        # Check if it matches
        command_verified = if options[:matcher]
          options[:matcher].call(recorded_command.to_h, actual_result.to_h)
        else
          recorded_command.result == actual_result
        end

        verified_commands << {
          command: recorded_command,
          actual: actual_result,
          verified: command_verified
        }

        command_index += 1
        [stdout, stderr, status]
      end

      allow_any_instance_of(Object).to receive(:system).and_wrap_original do |original_method, receiver, *args|
        recorded_command = record.commands[command_index]

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

        # For system calls, we only verify the exit status
        command_verified = recorded_command.result.status == actual_result.status

        verified_commands << {
          command: recorded_command,
          actual: actual_result,
          verified: command_verified
        }

        command_index += 1
        result
      end

      # Execute block
      output = yield

      # Check if all commands were executed
      if command_index < record.commands.size
        raise RecordNotFoundError, "Expected #{record.commands.size} commands but only #{command_index} were executed"
      end

      # Overall verification status
      all_verified = verified_commands.all? { |vc| vc[:verified] }

      # Build diff for failed commands
      diff = nil
      if !all_verified && !options[:matcher]
        diff_parts = []
        verified_commands.each_with_index do |vc, idx|
          next if vc[:verified]

          diff_parts << "Command #{idx + 1}:"
          diff_parts << generate_simple_diff(vc[:command].stdout, vc[:actual].stdout)
        end
        diff = diff_parts.join("\n\n")
      end

      UnifiedResult.new(
        output: output,
        mode: :verify,
        verified: all_verified,
        record_path: Pathname.new(record_path),
        commands: record.commands,
        verified_commands: verified_commands,
        diff: diff,
        # Keep backwards compatibility for single command
        expected_output: record.commands.first&.stdout,
        actual_output: verified_commands.first&.[](:actual)&.stdout
      )
    end

    def perform_playback(_record_name, record_path, _options)
      record = Record.load_or_create(record_path)

      raise RecordNotFoundError, "Record not found: #{record_path}" unless record.exists?
      raise RecordNotFoundError, "No commands found in record" if record.empty?

      # Setup replay mode - this will handle returning values for all commands
      recorder = Recorder.new(mode: :replay, record: record)
      recorder.setup_replay_stubs

      # Execute block (all commands will be stubbed with recorded values)
      output = yield

      UnifiedResult.new(
        output: output,
        mode: :playback,
        verified: true, # Always true for playback
        record_path: Pathname.new(record_path),
        commands: record.commands
      )
    end

    def generate_simple_diff(expected, actual)
      return nil if expected == actual

      diff_lines = []
      expected_lines = (expected || "").lines
      actual_lines = (actual || "").lines

      max_lines = [expected_lines.length, actual_lines.length].max

      max_lines.times do |i|
        expected_line = expected_lines[i]
        actual_line = actual_lines[i]

        if expected_line != actual_line
          diff_lines << "-#{expected_line.chomp}" if expected_line
          diff_lines << "+#{actual_line.chomp}" if actual_line
        end
      end

      diff_lines.join("\n")
    end
  end
end
