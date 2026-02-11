# frozen_string_literal: true

require "spec_helper"

RSpec.describe Backspin::Snapshot do
  it "memoizes and deep-freezes the unfiltered hash payload" do
    snapshot = described_class.new(
      command_type: Open3::Capture3,
      args: ["echo", "hello"],
      env: {"FOO" => "bar"},
      stdout: "hello\n",
      stderr: "",
      status: 0,
      recorded_at: "2026-02-11T00:00:00Z"
    )

    first = snapshot.to_h
    second = snapshot.to_h

    expect(first.object_id).to eq(second.object_id)
    expect(first).to be_frozen
    expect(first["args"]).to be_frozen
    expect(first["env"]).to be_frozen
    expect(first["stdout"]).to be_frozen
  end

  it "gives filters a mutable copy without mutating the cached base hash" do
    snapshot = described_class.new(
      command_type: Open3::Capture3,
      args: ["echo", "hello"],
      env: {"FOO" => "bar"},
      stdout: "hello\n",
      stderr: "",
      status: 0
    )

    base = snapshot.to_h

    filtered = snapshot.to_h(filter: lambda { |data|
      data["stdout"].gsub!("hello", "filtered")
      data["args"] << "extra"
      data["env"]["FOO"] = "changed"
      data
    })

    expect(filtered["stdout"]).to eq("filtered\n")
    expect(filtered["args"]).to eq(["echo", "hello", "extra"])
    expect(filtered["env"]).to eq({"FOO" => "changed"})

    expect(base["stdout"]).to eq("hello\n")
    expect(base["args"]).to eq(["echo", "hello"])
    expect(base["env"]).to eq({"FOO" => "bar"})
  end

  it "runs filter on every filtered to_h call" do
    snapshot = described_class.new(
      command_type: Open3::Capture3,
      args: ["echo", "hello"],
      stdout: "hello\n",
      stderr: "",
      status: 0
    )

    calls = 0
    filter = lambda { |data|
      calls += 1
      data.merge("stdout" => "call-#{calls}\n")
    }

    expect(snapshot.to_h(filter: filter)["stdout"]).to eq("call-1\n")
    expect(snapshot.to_h(filter: filter)["stdout"]).to eq("call-2\n")
    expect(calls).to eq(2)
  end
end
