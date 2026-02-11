# frozen_string_literal: true

require "spec_helper"

RSpec.describe Backspin::BackspinResult do
  it "returns nil verified? in record mode" do
    actual = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "one"],
      stdout: "one\n",
      stderr: "",
      status: 0
    )

    result = described_class.new(
      mode: :record,
      record_path: "record.yml",
      actual: actual
    )

    expect(result.recorded?).to be true
    expect(result.verified?).to be_nil
    expect(result.expected).to be_nil
  end

  it "returns a detailed message for content mismatches" do
    expected = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "recorded"],
      stdout: "one\n",
      stderr: "",
      status: 0
    )
    actual = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "actual"],
      stdout: "two\n",
      stderr: "",
      status: 0
    )
    command_diff = Backspin::CommandDiff.new(
      expected: expected,
      actual: actual
    )

    result = described_class.new(
      mode: :verify,
      record_path: "record.yml",
      actual: actual,
      expected: expected,
      verified: false,
      command_diff: command_diff
    )

    expect(result.error_message).to include("Output verification failed:")
    expect(result.error_message).to include("Command failed")
    expect(result.error_message).to include("[stdout]")
  end

  it "exposes explicit actual and expected snapshots in verify mode" do
    expected = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "recorded"],
      stdout: "recorded\n",
      stderr: "recorded_err\n",
      status: 0
    )
    actual = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "actual"],
      stdout: "actual\n",
      stderr: "actual_err\n",
      status: 1
    )

    result = described_class.new(
      mode: :verify,
      record_path: "record.yml",
      actual: actual,
      expected: expected,
      verified: false
    )

    expect(result.actual.stdout).to eq("actual\n")
    expect(result.actual.stderr).to eq("actual_err\n")
    expect(result.actual.status).to eq(1)
    expect(result.expected.stdout).to eq("recorded\n")
    expect(result.expected.stderr).to eq("recorded_err\n")
    expect(result.expected.status).to eq(0)
  end
end
