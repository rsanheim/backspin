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

  context "field_summary" do
    it "reports all fields as changed when everything differs" do
      expected_snapshot = Backspin::Snapshot.new(
        command_type: Open3::Capture3,
        args: ["echo", "recorded"],
        stdout: "expected output\n",
        stderr: "expected err\n",
        status: 0
      )
      actual_snapshot = Backspin::Snapshot.new(
        command_type: Open3::Capture3,
        args: ["echo", "actual"],
        stdout: "actual output\n",
        stderr: "actual err\n",
        status: 1
      )

      command_diff = described_class.new(
        expected: expected_snapshot,
        actual: actual_snapshot
      )

      summary = command_diff.field_summary
      expect(summary).to include("stdout: changed")
      expect(summary).to include("stderr: changed")
      expect(summary).to include("status: changed (expected 0, actual 1)")
    end

    it "reports unchanged fields correctly when only stdout differs" do
      expected_snapshot = Backspin::Snapshot.new(
        command_type: Open3::Capture3,
        args: ["echo", "recorded"],
        stdout: "expected\n",
        stderr: "same\n",
        status: 0
      )
      actual_snapshot = Backspin::Snapshot.new(
        command_type: Open3::Capture3,
        args: ["echo", "actual"],
        stdout: "actual\n",
        stderr: "same\n",
        status: 0
      )

      command_diff = described_class.new(
        expected: expected_snapshot,
        actual: actual_snapshot
      )

      summary = command_diff.field_summary
      expect(summary).to include("stdout: changed")
      expect(summary).to include("stderr: unchanged")
      expect(summary).to include("status: unchanged")
    end
  end

  context "context lines in diff" do
    it "shows context lines around changes" do
      expected_lines = (1..10).map { |i| "line #{i}" }.join("\n") + "\n"
      actual_lines = (1..10).map { |i| (i == 5) ? "CHANGED 5" : "line #{i}" }.join("\n") + "\n"

      expected_snapshot = Backspin::Snapshot.new(
        command_type: Open3::Capture3,
        args: ["test"],
        stdout: expected_lines,
        stderr: "",
        status: 0
      )
      actual_snapshot = Backspin::Snapshot.new(
        command_type: Open3::Capture3,
        args: ["test"],
        stdout: actual_lines,
        stderr: "",
        status: 0
      )

      diff = described_class.new(
        expected: expected_snapshot,
        actual: actual_snapshot
      ).diff

      expect(diff).to include(" line 2")
      expect(diff).to include(" line 3")
      expect(diff).to include(" line 4")
      expect(diff).to include("-line 5")
      expect(diff).to include("+CHANGED 5")
      expect(diff).to include(" line 6")
      expect(diff).to include(" line 7")
      expect(diff).to include(" line 8")
      expect(diff).not_to include(" line 1")
      expect(diff).not_to include(" line 9")
    end

    it "uses ... separator for distant changes" do
      expected_lines = (1..20).map { |i| "line #{i}" }.join("\n") + "\n"
      actual_lines = (1..20).map { |i|
        case i
        when 2 then "CHANGED 2"
        when 18 then "CHANGED 18"
        else "line #{i}"
        end
      }.join("\n") + "\n"

      expected_snapshot = Backspin::Snapshot.new(
        command_type: Open3::Capture3,
        args: ["test"],
        stdout: expected_lines,
        stderr: "",
        status: 0
      )
      actual_snapshot = Backspin::Snapshot.new(
        command_type: Open3::Capture3,
        args: ["test"],
        stdout: actual_lines,
        stderr: "",
        status: 0
      )

      diff = described_class.new(
        expected: expected_snapshot,
        actual: actual_snapshot
      ).diff

      expect(diff).to include("...")
      expect(diff).to include("-line 2")
      expect(diff).to include("+CHANGED 2")
      expect(diff).to include("-line 18")
      expect(diff).to include("+CHANGED 18")
    end

    it "shows line entries for newline-only changes" do
      expected_snapshot = Backspin::Snapshot.new(
        command_type: Open3::Capture3,
        args: ["test"],
        stdout: "line with newline\n",
        stderr: "",
        status: 0
      )
      actual_snapshot = Backspin::Snapshot.new(
        command_type: Open3::Capture3,
        args: ["test"],
        stdout: "line with newline",
        stderr: "",
        status: 0
      )

      diff = described_class.new(
        expected: expected_snapshot,
        actual: actual_snapshot
      ).diff

      expect(diff).to include("[stdout]")
      expect(diff).to include("-line with newline")
      expect(diff).to include("+line with newline")
    end
  end

  context "diff truncation" do
    it "truncates large diffs with a message" do
      expected_lines = (1..100).map { |i| "expected #{i}" }.join("\n") + "\n"
      actual_lines = (1..100).map { |i| "actual #{i}" }.join("\n") + "\n"

      expected_snapshot = Backspin::Snapshot.new(
        command_type: Open3::Capture3,
        args: ["test"],
        stdout: expected_lines,
        stderr: "",
        status: 0
      )
      actual_snapshot = Backspin::Snapshot.new(
        command_type: Open3::Capture3,
        args: ["test"],
        stdout: actual_lines,
        stderr: "",
        status: 0
      )

      diff = described_class.new(
        expected: expected_snapshot,
        actual: actual_snapshot
      ).diff

      expect(diff).to include("BACKSPIN_FULL_DIFF=1")
      expect(diff).to include("truncated")
    end

    it "shows full diff when BACKSPIN_FULL_DIFF=1" do
      expected_lines = (1..100).map { |i| "expected #{i}" }.join("\n") + "\n"
      actual_lines = (1..100).map { |i| "actual #{i}" }.join("\n") + "\n"

      expected_snapshot = Backspin::Snapshot.new(
        command_type: Open3::Capture3,
        args: ["test"],
        stdout: expected_lines,
        stderr: "",
        status: 0
      )
      actual_snapshot = Backspin::Snapshot.new(
        command_type: Open3::Capture3,
        args: ["test"],
        stdout: actual_lines,
        stderr: "",
        status: 0
      )

      ENV["BACKSPIN_FULL_DIFF"] = "1"
      diff = described_class.new(
        expected: expected_snapshot,
        actual: actual_snapshot
      ).diff

      expect(diff).not_to include("truncated")
      expect(diff).to include("-expected 100")
      expect(diff).to include("+actual 100")
    ensure
      ENV.delete("BACKSPIN_FULL_DIFF")
    end
  end
end
