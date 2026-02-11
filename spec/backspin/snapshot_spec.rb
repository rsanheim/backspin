# frozen_string_literal: true

require "spec_helper"

RSpec.describe Backspin::Snapshot do
  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  it "stores and deep-freezes the serialized hash at initialization" do
    args = ["echo", "hello"]
    env = {"FOO" => "bar"}
    snapshot = described_class.new(
      command_type: Open3::Capture3,
      args: args,
      env: env,
      stdout: "hello\n",
      stderr: "",
      status: 0,
      recorded_at: "2026-02-11T00:00:00Z"
    )

    args << "changed"
    env["FOO"] = "changed"

    first = snapshot.to_h
    second = snapshot.to_h

    expect(first.object_id).to eq(second.object_id)
    expect(first).to be_frozen
    expect(first["args"]).to be_frozen
    expect(first["env"]).to be_frozen
    expect(first["stdout"]).to be_frozen
    expect(first["args"]).to eq(["echo", "hello"])
    expect(first["env"]).to eq({"FOO" => "bar"})
  end

  it "captures scrubbing behavior at initialization time" do
    snapshot = described_class.new(
      command_type: Open3::Capture3,
      args: ["echo", "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"],
      stdout: "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE\n",
      stderr: "",
      status: 0
    )

    Backspin.configure do |config|
      config.scrub_credentials = false
    end

    data = snapshot.to_h
    expect(data["stdout"]).to eq("AWS_ACCESS_KEY_ID=********************\n")
    expect(data["args"]).to eq(["echo", "AWS_ACCESS_KEY_ID=********************"])
  end

  it "returns the same frozen hash on each to_h call" do
    snapshot = described_class.new(
      command_type: Open3::Capture3,
      args: ["echo", "hello"],
      env: {"FOO" => "bar"},
      stdout: "hello\n",
      stderr: "",
      status: 0
    )

    data_a = snapshot.to_h
    data_b = snapshot.to_h

    expect(data_a.object_id).to eq(data_b.object_id)
    expect(data_a).to be_frozen
  end
end
