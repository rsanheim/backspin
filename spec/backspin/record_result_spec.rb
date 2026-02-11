# frozen_string_literal: true

require "spec_helper"

RSpec.describe Backspin::RecordResult do
  it "returns a command count mismatch message when commands are missing" do
    record = Backspin::Record.new("record.yml")
    record.add_command(Backspin::Command.new(
      method_class: Open3::Capture3,
      args: ["echo", "one"],
      stdout: "one\n",
      stderr: "",
      status: 0
    ))
    record.add_command(Backspin::Command.new(
      method_class: Open3::Capture3,
      args: ["echo", "two"],
      stdout: "two\n",
      stderr: "",
      status: 0
    ))

    result = described_class.new(
      output: nil,
      mode: :verify,
      record: record,
      verified: false,
      command_diffs: []
    )

    expect(result.error_message).to eq("Expected 2 commands but only 0 were executed")
  end

  it "returns a detailed message for content mismatches" do
    recorded_command = Backspin::Command.new(
      method_class: Open3::Capture3,
      args: ["echo", "recorded"],
      stdout: "one\n",
      stderr: "",
      status: 0
    )
    actual_command = Backspin::Command.new(
      method_class: Open3::Capture3,
      args: ["echo", "actual"],
      stdout: "two\n",
      stderr: "",
      status: 0
    )
    diff = Backspin::CommandDiff.new(
      recorded_command: recorded_command,
      actual_command: actual_command
    )

    record = Backspin::Record.new("record.yml")
    record.add_command(recorded_command)

    result = described_class.new(
      output: nil,
      mode: :verify,
      record: record,
      verified: false,
      command_diffs: [diff]
    )

    expect(result.error_message).to include("Output verification failed for 1 command(s):")
    expect(result.error_message).to include("Command 1:")
    expect(result.error_message).to include("[stdout]")
  end

  it "exposes actual output by default in verify mode while keeping expected output available" do
    recorded_command = Backspin::Command.new(
      method_class: Open3::Capture3,
      args: ["echo", "recorded"],
      stdout: "recorded\n",
      stderr: "recorded_err\n",
      status: 0
    )
    actual_command = Backspin::Command.new(
      method_class: Open3::Capture3,
      args: ["echo", "actual"],
      stdout: "actual\n",
      stderr: "actual_err\n",
      status: 1
    )

    record = Backspin::Record.new("record.yml")
    record.add_command(recorded_command)

    result = described_class.new(
      output: nil,
      mode: :verify,
      record: record,
      verified: false,
      command_diffs: [],
      actual_commands: [actual_command]
    )

    expect(result.stdout).to eq("actual\n")
    expect(result.stderr).to eq("actual_err\n")
    expect(result.status).to eq(1)
    expect(result.expected_stdout).to eq("recorded\n")
    expect(result.expected_stderr).to eq("recorded_err\n")
    expect(result.expected_status).to eq(0)
    expect(result.actual_stdout).to eq("actual\n")
    expect(result.actual_stderr).to eq("actual_err\n")
    expect(result.actual_status).to eq(1)
  end
end
