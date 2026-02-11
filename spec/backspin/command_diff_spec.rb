# frozen_string_literal: true

require "spec_helper"

RSpec.describe Backspin::CommandDiff do
  it "includes stdout, stderr, and status diffs in order" do
    expected_snapshot = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "recorded"],
      stdout: "one\n",
      stderr: "err\n",
      status: 0
    )

    actual_snapshot = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "actual"],
      stdout: "two\n",
      stderr: "bad\n",
      status: 1
    )

    diff = described_class.new(
      expected: expected_snapshot,
      actual: actual_snapshot
    ).diff

    expect(diff).to include("[stdout]")
    expect(diff).to include("-one")
    expect(diff).to include("+two")
    expect(diff).to include("[stderr]")
    expect(diff).to include("-err")
    expect(diff).to include("+bad")
    expect(diff).to include("Exit status: expected 0, got 1")

    stdout_index = diff.index("[stdout]")
    stderr_index = diff.index("[stderr]")
    status_index = diff.index("Exit status")
    expect(stdout_index).to be < stderr_index
    expect(stderr_index).to be < status_index
  end

  it "materializes compare hashes once and reuses them for verify and diff" do
    expected_hash = {
      "stdout" => "one\n",
      "stderr" => "err\n",
      "status" => 0
    }
    actual_hash = {
      "stdout" => "two\n",
      "stderr" => "bad\n",
      "status" => 1
    }

    expected_snapshot = instance_double(
      Backspin::Snapshot,
      command_type: Open3::Capture3,
      stdout: "one\n",
      stderr: "err\n",
      status: 0
    )
    actual_snapshot = instance_double(
      Backspin::Snapshot,
      command_type: Open3::Capture3,
      stdout: "two\n",
      stderr: "bad\n",
      status: 1
    )

    expect(expected_snapshot).to receive(:to_h).once.and_return(expected_hash)
    expect(actual_snapshot).to receive(:to_h).once.and_return(actual_hash)

    command_diff = described_class.new(
      expected: expected_snapshot,
      actual: actual_snapshot
    )

    expect(command_diff.verified?).to be false
    expect(command_diff.diff).to include("[stdout]")
    expect(command_diff.diff).to include("[stderr]")
    expect(command_diff.diff).to include("Exit status: expected 0, got 1")
  end
end
