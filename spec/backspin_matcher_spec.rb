# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Backspin matcher contract" do
  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  it "supports proc matchers for command runs" do
    Backspin.run(["echo", "hello"], name: "proc_matcher", mode: :record)

    matcher = lambda { |recorded, actual|
      recorded["stdout"].start_with?("hello") && actual["stdout"].start_with?("hello")
    }

    result = Backspin.run(["echo", "hello"], name: "proc_matcher", matcher: matcher)

    expect(result).to be_verified
  end

  it "supports field-specific matchers for capture" do
    Backspin.capture("field_matcher") do
      puts "Value: 123"
    end

    matcher = {
      stdout: ->(recorded, actual) {
        recorded.gsub(/\d+/, "[NUM]") == actual.gsub(/\d+/, "[NUM]")
      }
    }

    result = Backspin.capture("field_matcher", matcher: matcher) do
      puts "Value: 999"
    end

    expect(result).to be_verified
  end

  it "supports :all matchers alongside field matchers" do
    Backspin.run(["echo", "status"], name: "all_matcher", mode: :record)

    matcher = {
      all: ->(recorded, actual) { recorded["status"] == actual["status"] },
      stdout: ->(recorded, actual) { recorded == actual }
    }

    result = Backspin.run(["echo", "status"], name: "all_matcher", matcher: matcher)

    expect(result).to be_verified
  end

  it "defaults to matching stdout/stderr/status only" do
    recorded_command = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "recorded"],
      env: {"FOO" => "recorded"},
      stdout: "same\n",
      stderr: "",
      status: 0
    )

    actual_command = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "actual"],
      env: {"FOO" => "actual"},
      stdout: "same\n",
      stderr: "",
      status: 0
    )

    matcher = Backspin::Matcher.new(
      config: nil,
      expected: recorded_command,
      actual: actual_command
    )

    expect(matcher.match?).to be true
    expect(matcher.failure_reason).to eq("")
  end

  it "reports all output/status differences for the default matcher" do
    recorded_command = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "recorded"],
      stdout: "one\n",
      stderr: "err\n",
      status: 0
    )

    actual_command = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "actual"],
      stdout: "two\n",
      stderr: "diff\n",
      status: 1
    )

    matcher = Backspin::Matcher.new(
      config: nil,
      expected: recorded_command,
      actual: actual_command
    )

    expect(matcher.failure_reason).to include("stdout differs")
    expect(matcher.failure_reason).to include("stderr differs")
    expect(matcher.failure_reason).to include("exit status differs")
  end

  it "validates hash matcher keys and values" do
    recorded_command = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "recorded"],
      stdout: "ok\n",
      stderr: "",
      status: 0
    )

    actual_command = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "actual"],
      stdout: "ok\n",
      stderr: "",
      status: 0
    )

    expect do
      Backspin::Matcher.new(
        config: {bad: ->(_recorded, _actual) { true }},
        expected: recorded_command,
        actual: actual_command
      )
    end.to raise_error(ArgumentError, /Invalid matcher key/)

    expect do
      Backspin::Matcher.new(
        config: {stdout: "nope"},
        expected: recorded_command,
        actual: actual_command
      )
    end.to raise_error(ArgumentError, /must be callable/)
  end

  it "runs all hash matchers and reports each failure reason" do
    recorded_command = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "recorded"],
      stdout: "ok\n",
      stderr: "err\n",
      status: 0
    )

    actual_command = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "actual"],
      stdout: "bad\n",
      stderr: "bad\n",
      status: 1
    )

    calls = []
    matcher_config = {
      all: ->(_recorded, _actual) {
        calls << :all
        false
      },
      stdout: ->(_recorded, _actual) {
        calls << :stdout
        false
      },
      stderr: ->(_recorded, _actual) {
        calls << :stderr
        false
      },
      status: ->(_recorded, _actual) {
        calls << :status
        false
      }
    }

    matcher = Backspin::Matcher.new(
      config: matcher_config,
      expected: recorded_command,
      actual: actual_command
    )

    expect(matcher.match?).to be false
    expect(calls).to match_array(%i[all stdout stderr status])
    expect(matcher.failure_reason).to include(":all matcher failed")
    expect(matcher.failure_reason).to include("stdout custom matcher failed")
    expect(matcher.failure_reason).to include("stderr custom matcher failed")
    expect(matcher.failure_reason).to include("status custom matcher failed")
  end

  it "ignores args and env for capture commands by default" do
    recorded_command = Backspin::Snapshot.new(
      command_type: Backspin::Capturer,
      args: ["<captured block>"],
      env: {"FOO" => "recorded"},
      stdout: "same\n",
      stderr: "",
      status: 0
    )

    actual_command = Backspin::Snapshot.new(
      command_type: Backspin::Capturer,
      args: ["different args"],
      env: {"FOO" => "actual"},
      stdout: "same\n",
      stderr: "",
      status: 0
    )

    matcher = Backspin::Matcher.new(
      config: nil,
      expected: recorded_command,
      actual: actual_command
    )

    expect(matcher.match?).to be true
  end

  it "does not call to_h for default matching and failure reporting" do
    expected_snapshot = instance_double(
      Backspin::Snapshot,
      stdout: "same\n",
      stderr: "",
      status: 0
    )
    actual_snapshot = instance_double(
      Backspin::Snapshot,
      stdout: "same\n",
      stderr: "",
      status: 0
    )

    expect(expected_snapshot).not_to receive(:to_h)
    expect(actual_snapshot).not_to receive(:to_h)

    matcher = Backspin::Matcher.new(
      config: nil,
      expected: expected_snapshot,
      actual: actual_snapshot
    )

    expect(matcher.match?).to be true
    expect(matcher.failure_reason).to eq("")
  end

  it "calls to_h for :all hash matcher contracts" do
    expected_snapshot = instance_double(
      Backspin::Snapshot,
      stdout: "same\n",
      stderr: "",
      status: 0
    )
    actual_snapshot = instance_double(
      Backspin::Snapshot,
      stdout: "same\n",
      stderr: "",
      status: 0
    )

    expect(expected_snapshot).to receive(:to_h).once.and_return({
      "stdout" => "same\n",
      "stderr" => "",
      "status" => 0
    })
    expect(actual_snapshot).to receive(:to_h).once.and_return({
      "stdout" => "same\n",
      "stderr" => "",
      "status" => 0
    })

    matcher = Backspin::Matcher.new(
      config: {
        all: ->(recorded, actual) { recorded["stdout"] == actual["stdout"] }
      },
      expected: expected_snapshot,
      actual: actual_snapshot
    )

    expect(matcher.match?).to be true
  end

  it "allows proc matchers to mutate input copies without mutating snapshots" do
    recorded_command = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "recorded"],
      stdout: "id=100\n",
      stderr: "",
      status: 0
    )
    actual_command = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "actual"],
      stdout: "id=200\n",
      stderr: "",
      status: 0
    )

    matcher = Backspin::Matcher.new(
      config: lambda { |recorded, actual|
        recorded["stdout"].gsub!(/id=\d+/, "id=[ID]")
        actual["stdout"].gsub!(/id=\d+/, "id=[ID]")
        recorded["stdout"] == actual["stdout"]
      },
      expected: recorded_command,
      actual: actual_command
    )

    expect(matcher.match?).to be true
    expect(recorded_command.to_h["stdout"]).to eq("id=100\n")
    expect(actual_command.to_h["stdout"]).to eq("id=200\n")
  end

  it "allows :all hash matchers to mutate input copies" do
    recorded_command = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "recorded"],
      stdout: "id=100\n",
      stderr: "",
      status: 0
    )
    actual_command = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: ["echo", "actual"],
      stdout: "id=200\n",
      stderr: "",
      status: 0
    )

    matcher = Backspin::Matcher.new(
      config: {
        all: ->(recorded, actual) {
          recorded["stdout"].gsub!(/id=\d+/, "id=[ID]")
          actual["stdout"].gsub!(/id=\d+/, "id=[ID]")
          recorded["stdout"] == actual["stdout"]
        }
      },
      expected: recorded_command,
      actual: actual_command
    )

    expect(matcher.match?).to be true
    expect(recorded_command.to_h["stdout"]).to eq("id=100\n")
    expect(actual_command.to_h["stdout"]).to eq("id=200\n")
  end

end
