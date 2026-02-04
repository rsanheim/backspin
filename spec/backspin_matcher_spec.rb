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
    recorded_command = Backspin::Command.new(
      method_class: Open3::Capture3,
      args: ["echo", "recorded"],
      env: {"FOO" => "recorded"},
      stdout: "same\n",
      stderr: "",
      status: 0
    )

    actual_command = Backspin::Command.new(
      method_class: Open3::Capture3,
      args: ["echo", "actual"],
      env: {"FOO" => "actual"},
      stdout: "same\n",
      stderr: "",
      status: 0
    )

    matcher = Backspin::Matcher.new(
      config: nil,
      recorded_command: recorded_command,
      actual_command: actual_command
    )

    expect(matcher.match?).to be true
    expect(matcher.failure_reason).to eq("")
  end

  it "reports all output/status differences for the default matcher" do
    recorded_command = Backspin::Command.new(
      method_class: Open3::Capture3,
      args: ["echo", "recorded"],
      stdout: "one\n",
      stderr: "err\n",
      status: 0
    )

    actual_command = Backspin::Command.new(
      method_class: Open3::Capture3,
      args: ["echo", "actual"],
      stdout: "two\n",
      stderr: "diff\n",
      status: 1
    )

    matcher = Backspin::Matcher.new(
      config: nil,
      recorded_command: recorded_command,
      actual_command: actual_command
    )

    expect(matcher.failure_reason).to include("stdout differs")
    expect(matcher.failure_reason).to include("stderr differs")
    expect(matcher.failure_reason).to include("exit status differs")
  end

  it "validates hash matcher keys and values" do
    recorded_command = Backspin::Command.new(
      method_class: Open3::Capture3,
      args: ["echo", "recorded"],
      stdout: "ok\n",
      stderr: "",
      status: 0
    )

    actual_command = Backspin::Command.new(
      method_class: Open3::Capture3,
      args: ["echo", "actual"],
      stdout: "ok\n",
      stderr: "",
      status: 0
    )

    expect do
      Backspin::Matcher.new(
        config: {bad: ->(_recorded, _actual) { true }},
        recorded_command: recorded_command,
        actual_command: actual_command
      )
    end.to raise_error(ArgumentError, /Invalid matcher key/)

    expect do
      Backspin::Matcher.new(
        config: {stdout: "nope"},
        recorded_command: recorded_command,
        actual_command: actual_command
      )
    end.to raise_error(ArgumentError, /must be callable/)
  end

  it "runs all hash matchers and reports each failure reason" do
    recorded_command = Backspin::Command.new(
      method_class: Open3::Capture3,
      args: ["echo", "recorded"],
      stdout: "ok\n",
      stderr: "err\n",
      status: 0
    )

    actual_command = Backspin::Command.new(
      method_class: Open3::Capture3,
      args: ["echo", "actual"],
      stdout: "bad\n",
      stderr: "bad\n",
      status: 1
    )

    calls = []
    matcher_config = {
      all: ->(_recorded, _actual) { calls << :all; false },
      stdout: ->(_recorded, _actual) { calls << :stdout; false },
      stderr: ->(_recorded, _actual) { calls << :stderr; false },
      status: ->(_recorded, _actual) { calls << :status; false }
    }

    matcher = Backspin::Matcher.new(
      config: matcher_config,
      recorded_command: recorded_command,
      actual_command: actual_command
    )

    expect(matcher.match?).to be false
    expect(calls).to match_array(%i[all stdout stderr status])
    expect(matcher.failure_reason).to include(":all matcher failed")
    expect(matcher.failure_reason).to include("stdout custom matcher failed")
    expect(matcher.failure_reason).to include("stderr custom matcher failed")
    expect(matcher.failure_reason).to include("status custom matcher failed")
  end

  it "ignores args and env for capture commands by default" do
    recorded_command = Backspin::Command.new(
      method_class: Backspin::Capturer,
      args: ["<captured block>"],
      env: {"FOO" => "recorded"},
      stdout: "same\n",
      stderr: "",
      status: 0
    )

    actual_command = Backspin::Command.new(
      method_class: Backspin::Capturer,
      args: ["different args"],
      env: {"FOO" => "actual"},
      stdout: "same\n",
      stderr: "",
      status: 0
    )

    matcher = Backspin::Matcher.new(
      config: nil,
      recorded_command: recorded_command,
      actual_command: actual_command
    )

    expect(matcher.match?).to be true
  end
end
