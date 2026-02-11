# frozen_string_literal: true

require "tempfile"
require "backspin/command_diff"

module Backspin
  # Handles capture-mode recording and verification
  class Recorder
    attr_reader :mode, :record, :matcher, :filter

    def initialize(mode: :record, record: nil, matcher: nil, filter: nil)
      @mode = mode
      @record = record
      @matcher = matcher
      @filter = filter
    end

    # Performs capture recording by intercepting all stdout/stderr output
    def perform_capture_recording
      captured_stdout, captured_stderr, output = capture_output { yield }

      actual_snapshot = Snapshot.new(
        command_type: Backspin::Capturer,
        args: ["<captured block>"],
        stdout: captured_stdout,
        stderr: captured_stderr,
        status: 0,
        recorded_at: Time.now.iso8601
      )

      record.set_snapshot(actual_snapshot)
      record.save(filter: @filter)

      BackspinResult.new(
        mode: :record,
        record_path: record.path,
        actual: actual_snapshot,
        output: output
      )
    end

    # Performs capture verification by capturing output and comparing with recorded values
    def perform_capture_verification
      raise RecordNotFoundError, "Record not found: #{record.path}" unless record.exists?
      raise RecordNotFoundError, "No snapshot found in record #{record.path}" if record.empty?

      expected_snapshot = record.snapshot
      unless expected_snapshot.command_type == Backspin::Capturer
        raise RecordFormatError, "Invalid record format: expected Backspin::Capturer for capture"
      end

      captured_stdout, captured_stderr, output = capture_output { yield }

      actual_snapshot = Snapshot.new(
        command_type: Backspin::Capturer,
        args: ["<captured block>"],
        stdout: captured_stdout,
        stderr: captured_stderr,
        status: 0
      )

      command_diff = CommandDiff.new(
        expected: expected_snapshot,
        actual: actual_snapshot,
        matcher: @matcher
      )

      BackspinResult.new(
        mode: :verify,
        record_path: record.path,
        actual: actual_snapshot,
        expected: expected_snapshot,
        verified: command_diff.verified?,
        command_diff: command_diff,
        output: output
      )
    end

    private

    def capture_output
      stdout_tempfile = Tempfile.new("backspin_stdout")
      stderr_tempfile = Tempfile.new("backspin_stderr")
      original_stdout_fd = $stdout.dup
      original_stderr_fd = $stderr.dup

      begin
        $stdout.reopen(stdout_tempfile)
        $stderr.reopen(stderr_tempfile)

        output = yield

        $stdout.flush
        $stderr.flush
        stdout_tempfile.rewind
        stderr_tempfile.rewind

        captured_stdout = stdout_tempfile.read
        captured_stderr = stderr_tempfile.read

        [captured_stdout, captured_stderr, output]
      ensure
        $stdout.reopen(original_stdout_fd)
        $stderr.reopen(original_stderr_fd)
        original_stdout_fd.close
        original_stderr_fd.close

        stdout_tempfile.close!
        stderr_tempfile.close!
      end
    end
  end
end
