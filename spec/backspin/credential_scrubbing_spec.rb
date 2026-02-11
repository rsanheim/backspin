# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Backspin credential scrubbing" do
  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  describe "configuration" do
    it "has credential scrubbing enabled by default" do
      expect(Backspin.configuration.scrub_credentials).to be true
    end

    it "can disable credential scrubbing" do
      Backspin.configure do |config|
        config.scrub_credentials = false
      end

      expect(Backspin.configuration.scrub_credentials).to be false
    end

    it "can add custom credential patterns" do
      Backspin.configure do |config|
        config.add_credential_pattern(/MY_SECRET_[A-Z0-9]+/)
      end

      expect(Backspin.configuration.credential_patterns).to include(/MY_SECRET_[A-Z0-9]+/)
    end
  end

  it "scrubs credentials from stdout" do
    result = Backspin.run(["echo", "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"], name: "aws_keys")

    record_data = YAML.load_file(result.record_path)
    expect(record_data["snapshot"]["stdout"]).to eq("AWS_ACCESS_KEY_ID=********************\n")
  end

  it "scrubs credentials from stderr" do
    result = Backspin.run(
      ["sh", "-c", "echo normal output && echo 'Error: Invalid API_KEY=sk-1234567890abcdef1234567890abcdef' >&2 && exit 1"],
      name: "stderr_creds"
    )

    record_data = YAML.load_file(result.record_path)
    expect(record_data["snapshot"]["stdout"]).to eq("normal output\n")
    expect(record_data["snapshot"]["stderr"]).to eq("Error: Invalid #{"*" * 43}\n")
  end

  it "scrubs credentials in command arguments" do
    result = Backspin.run(["echo", "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"], name: "args_aws_creds")

    record_data = YAML.load_file(result.record_path)
    args = record_data["snapshot"]["args"]
    args_string = args.join(" ")

    expect(args_string).not_to include("AKIAIOSFODNN7EXAMPLE")
    expect(args_string).to include("AWS_ACCESS_KEY_ID=")
    expect(args_string).to match(/\*{20}/)
  end

  it "scrubs credentials in env values" do
    result = Backspin.run(
      ["ruby", "-e", "print ENV.fetch('AWS_ACCESS_KEY_ID')"],
      name: "env_scrub",
      env: {"AWS_ACCESS_KEY_ID" => "AKIAIOSFODNN7EXAMPLE"}
    )

    record_data = YAML.load_file(result.record_path)
    expect(record_data["snapshot"]["env"]).to eq({"AWS_ACCESS_KEY_ID" => "********************"})
  end

  it "scrubs credentials in nested args and hashes" do
    api_key = "API_KEY=sk-1234567890abcdef1234567890abcdef"
    snapshot = Backspin::Snapshot.new(
      command_type: Open3::Capture3,
      args: [
        "echo",
        ["AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"],
        {"token" => api_key}
      ],
      stdout: "",
      stderr: "",
      status: 0
    )

    args = snapshot.to_h["args"]

    expect(args[1].first).to eq("AWS_ACCESS_KEY_ID=********************")
    expect(args[2]["token"]).to eq("*" * api_key.length)
  end

  it "scrubs custom patterns for run records" do
    secret = "MY_SECRET_ABC123"
    Backspin.configure do |config|
      config.add_credential_pattern(/MY_SECRET_[A-Z0-9]+/)
    end

    result = Backspin.run(["echo", secret], name: "custom_scrub_run")

    record_data = YAML.load_file(result.record_path)
    expect(record_data["snapshot"]["stdout"]).to eq("#{"*" * secret.length}\n")
  end

  it "scrubs custom patterns for capture records" do
    secret = "MY_SECRET_ABC123"
    Backspin.configure do |config|
      config.add_credential_pattern(/MY_SECRET_[A-Z0-9]+/)
    end

    result = Backspin.capture("custom_scrub_capture") do
      puts secret
    end

    record_data = YAML.load_file(result.record_path)
    expect(record_data["snapshot"]["stdout"]).to eq("#{"*" * secret.length}\n")
  end

  it "scrubs output in verification diffs" do
    Backspin.run(["echo", "token=AKIAIOSFODNN7EXAMPLE one"], name: "scrub_diff", mode: :record)

    expect do
      Backspin.run(["echo", "token=AKIAIOSFODNN7EXAMPLE two"], name: "scrub_diff")
    end.to raise_error(Backspin::VerificationError) do |error|
      expect(error.message).to include("token=******************** one")
      expect(error.message).to include("token=******************** two")
      expect(error.message).not_to include("AKIAIOSFODNN7EXAMPLE")
    end
  end

  it "scrubs credentials from captured output" do
    result = Backspin.capture("capture_scrub") do
      puts "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"
      warn "Error: Invalid API_KEY=sk-1234567890abcdef1234567890abcdef"
    end

    record_data = YAML.load_file(result.record_path)
    snapshot = record_data["snapshot"]
    expect(snapshot["stdout"]).to eq("AWS_ACCESS_KEY_ID=********************\n")
    expect(snapshot["stderr"]).to eq("Error: Invalid #{"*" * 43}\n")
  end

  it "does not scrub when scrubbing is disabled" do
    Backspin.configure do |config|
      config.scrub_credentials = false
    end

    result = Backspin.run(["echo", "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"], name: "no_scrub")

    record_data = YAML.load_file(result.record_path)
    expect(record_data["snapshot"]["stdout"]).to eq("AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE\n")
  end

  it "does not scrub captured output when scrubbing is disabled" do
    Backspin.configure do |config|
      config.scrub_credentials = false
    end

    result = Backspin.capture("capture_no_scrub") do
      puts "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"
    end

    record_data = YAML.load_file(result.record_path)
    expect(record_data["snapshot"]["stdout"]).to eq("AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE\n")
  end
end
