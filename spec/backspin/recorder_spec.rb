# frozen_string_literal: true

require "spec_helper"

RSpec.describe Backspin::Recorder do
  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  it "records captured output and block return value" do
    record = Backspin::Record.create("recorder_capture_recording")
    recorder = described_class.new(mode: :record, record: record)

    result = recorder.perform_capture_recording do
      puts "hello"
      warn "err"
      :ok
    end

    expect(result).to be_recorded
    expect(result.output).to eq(:ok)
    expect(record.commands.size).to eq(1)
    expect(record.commands.first.stdout).to include("hello\n")
    expect(record.commands.first.stderr).to include("err\n")
  end

  it "restores stdout and stderr when capture block raises" do
    record = Backspin::Record.create("recorder_capture_raises")
    recorder = described_class.new(mode: :record, record: record)

    outer_stdout = Tempfile.new("backspin_outer_stdout")
    outer_stderr = Tempfile.new("backspin_outer_stderr")
    original_stdout_fd = $stdout.dup
    original_stderr_fd = $stderr.dup

    begin
      $stdout.reopen(outer_stdout)
      $stderr.reopen(outer_stderr)

      expect do
        recorder.perform_capture_recording do
          puts "inside"
          warn "inside_err"
          raise "boom"
        end
      end.to raise_error(RuntimeError, "boom")

      puts "after_stdout"
      warn "after_stderr"
      $stdout.flush
      $stderr.flush

      outer_stdout.rewind
      outer_stderr.rewind
      expect(outer_stdout.read).to include("after_stdout\n")
      expect(outer_stderr.read).to include("after_stderr\n")
    ensure
      $stdout.reopen(original_stdout_fd)
      $stderr.reopen(original_stderr_fd)
      original_stdout_fd.close
      original_stderr_fd.close
      outer_stdout.close!
      outer_stderr.close!
    end
  end
end
