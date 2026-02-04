# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Backspin.run" do
  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  it "records a command run with env and preserves args" do
    result = Backspin.run([
      "ruby",
      "-e",
      "print ENV.fetch('MY_ENV_VAR')"
    ], name: "command_with_env", env: {"MY_ENV_VAR" => "hello"})

    expect(result).to be_recorded
    expect(result.stdout).to eq("hello")

    record_path = Backspin.configuration.backspin_dir.join("command_with_env.yml")
    record_data = YAML.load_file(record_path)

    expect(record_data["format_version"]).to eq("3.0")
    command = record_data["commands"].first
    expect(command["command_type"]).to eq("Open3::Capture3")
    expect(command["args"]).to eq(["ruby", "-e", "print ENV.fetch('MY_ENV_VAR')"])
    expect(command["env"]).to eq({"MY_ENV_VAR" => "hello"})
    expect(command["status"]).to eq(0)
  end

  it "does not record env when env is not provided" do
    Backspin.run(["echo", "no env"], name: "command_no_env")

    record_path = Backspin.configuration.backspin_dir.join("command_no_env.yml")
    command = YAML.load_file(record_path)["commands"].first
    expect(command).not_to have_key("env")
  end

  it "records string commands as strings" do
    Backspin.run("echo hello", name: "string_command")

    record_path = Backspin.configuration.backspin_dir.join("string_command.yml")
    command = YAML.load_file(record_path)["commands"].first
    expect(command["args"]).to eq("echo hello")
  end

  it "verifies matching output and raises on mismatch by default" do
    Backspin.run(["echo", "original"], name: "verify_command", mode: :record)

    result = Backspin.run(["echo", "original"], name: "verify_command")
    expect(result).to be_verified

    expect do
      Backspin.run(["echo", "different"], name: "verify_command")
    end.to raise_error(Backspin::VerificationError) do |error|
      expect(error.message).to include("Backspin verification failed!")
      expect(error.message).to include("-original")
      expect(error.message).to include("+different")
    end
  end

  it "returns a failed result when raise_on_verification_failure is false" do
    Backspin.run(["echo", "expected"], name: "config_no_raise")

    Backspin.configure do |config|
      config.raise_on_verification_failure = false
    end

    result = Backspin.run(["echo", "actual"], name: "config_no_raise")

    expect(result.verified?).to be false
    expect(result.error_message).to include("Output verification failed")
  end

  it "rejects playback mode" do
    expect do
      Backspin.run(["echo", "hi"], name: "no_playback", mode: :playback)
    end.to raise_error(ArgumentError, /Playback mode is not supported/)
  end
end
