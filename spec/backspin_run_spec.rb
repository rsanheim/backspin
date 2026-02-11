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

  it "records then verifies by default when mode is omitted" do
    result = Backspin.run(["echo", "auto"], name: "auto_default")

    expect(result).to be_recorded
    expect(result.mode).to eq(:record)

    result = Backspin.run(["echo", "auto"], name: "auto_default")

    expect(result).to be_verified
    expect(result.mode).to eq(:verify)
  end

  it "runs real commands with array and string forms" do
    Dir.mktmpdir("backspin_ls") do |dir|
      File.write(File.join(dir, "a.txt"), "a")
      File.write(File.join(dir, "b.txt"), "b")

      result = Backspin.run(["ls", dir], name: "ls_array")
      expect(result).to be_recorded
      expect(result.stdout).to include("a.txt")
      expect(result.stdout).to include("b.txt")

      result = Backspin.run(["ls", dir], name: "ls_array")
      expect(result).to be_verified
    end

    result = Backspin.run("echo hello", name: "echo_string")
    expect(result.stdout).to eq("hello\n")
    result = Backspin.run("echo hello", name: "echo_string")
    expect(result).to be_verified

    result = Backspin.run(["date", "+%Y"], name: "date_array")
    expect(result.stdout).to match(/\A\d{4}\n\z/)
    result = Backspin.run(["date", "+%Y"], name: "date_array")
    expect(result).to be_verified
  end

  it "captures stderr and non-zero exit status for failing commands" do
    result = Backspin.run(["sh", "-c", "echo error >&2; exit 1"], name: "stderr_status")
    expect(result).to be_recorded
    expect(result.stdout).to eq("")
    expect(result.stderr).to eq("error\n")
    expect(result.status).to eq(1)

    result = Backspin.run(["sh", "-c", "echo error >&2; exit 1"], name: "stderr_status")
    expect(result).to be_verified
  end

  it "overwrites existing records when mode is :record" do
    Backspin.run(["echo", "first"], name: "record_overwrite", mode: :record)
    Backspin.run(["echo", "second"], name: "record_overwrite", mode: :record)

    record_path = Backspin.configuration.backspin_dir.join("record_overwrite.yml")
    command = YAML.load_file(record_path)["commands"].first
    expect(command["stdout"]).to eq("second\n")
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

  it "does not duplicate diff sections in verification errors" do
    Backspin.run(["echo", "original"], name: "verify_command_single_diff", mode: :record)

    expect do
      Backspin.run(["echo", "different"], name: "verify_command_single_diff")
    end.to raise_error(Backspin::VerificationError) do |error|
      expect(error.message).not_to include("\n\nDiff:\n")
      expect(error.message.scan("[stdout]").length).to eq(1)
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
    expect(result.stdout).to eq("actual\n")
    expect(result.expected_stdout).to eq("expected\n")
    expect(result.actual_stdout).to eq("actual\n")
  end

  it "requires a command when no block is provided" do
    expect do
      Backspin.run(name: "missing_command")
    end.to raise_error(ArgumentError, /command is required/)
  end

  it "rejects an empty command array" do
    expect do
      Backspin.run([], name: "empty_command")
    end.to raise_error(ArgumentError, /command array cannot be empty/)
  end

  it "rejects non-hash env values" do
    expect do
      Backspin.run(["echo", "hi"], name: "bad_env", env: "nope")
    end.to raise_error(ArgumentError, /env must be a Hash/)
  end

  it "rejects env when using a block" do
    expect do
      Backspin.run(name: "block_env", env: {"FOO" => "bar"}) do
        puts "hi"
      end
    end.to raise_error(ArgumentError, /env is not supported when using a block/)
  end

  it "raises when verifying without a record" do
    expect do
      Backspin.run(["echo", "hi"], name: "missing_record", mode: :verify)
    end.to raise_error(Backspin::RecordNotFoundError, /Record not found/)
  end

  it "raises when record has multiple commands for run verification" do
    record_path = Backspin.configuration.backspin_dir.join("multi_command_verify.yml")
    FileUtils.mkdir_p(File.dirname(record_path))
    File.write(record_path, {
      "format_version" => "3.0",
      "first_recorded_at" => "2024-01-01T00:00:00Z",
      "commands" => [
        {
          "command_type" => "Open3::Capture3",
          "args" => ["echo", "one"],
          "stdout" => "one\n",
          "stderr" => "",
          "status" => 0,
          "recorded_at" => "2024-01-01T00:00:00Z"
        },
        {
          "command_type" => "Open3::Capture3",
          "args" => ["echo", "two"],
          "stdout" => "two\n",
          "stderr" => "",
          "status" => 0,
          "recorded_at" => "2024-01-01T00:00:00Z"
        }
      ]
    }.to_yaml)

    expect do
      Backspin.run(["echo", "one"], name: "multi_command_verify", mode: :verify)
    end.to raise_error(Backspin::RecordFormatError, /expected 1 command for run, found 2/)
  end

  it "raises when record command type is capture" do
    Backspin.capture("capture_record") do
      puts "capture"
    end

    expect do
      Backspin.run(["echo", "capture"], name: "capture_record", mode: :verify)
    end.to raise_error(Backspin::RecordFormatError, /expected Open3::Capture3/)
  end

  it "does not execute verify commands when record command type is capture" do
    Backspin.capture("capture_record_no_exec") do
      puts "capture"
    end
    marker_path = Backspin.configuration.backspin_dir.join("should_not_exist.txt")

    expect do
      Backspin.run(
        ["ruby", "-e", "File.write(ARGV.fetch(0), 'bad')", marker_path.to_s],
        name: "capture_record_no_exec",
        mode: :verify
      )
    end.to raise_error(Backspin::RecordFormatError, /expected Open3::Capture3/)

    expect(marker_path).not_to exist
  end

  it "rejects playback mode" do
    expect do
      Backspin.run(["echo", "hi"], name: "no_playback", mode: :playback)
    end.to raise_error(ArgumentError, /Playback mode is not supported/)
  end
end
