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
end
