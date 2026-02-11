# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Backspin.capture" do
  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  it "captures stdout and stderr from anything in the block" do
    record_name = "capture_all_output"

    result = Backspin.capture(record_name) do
      puts "Hello from puts"
      $stdout.print "Direct stdout write\n"
      warn "Error message"

      system("echo 'From system command'")
      puts `echo 'From backticks'`

      stdout, _, _ = Open3.capture3("echo", "From Open3")
      puts stdout

      "block return value"
    end

    expect(result.output).to eq("block return value")
    expect(result.mode).to eq(:record)

    record_path = Backspin.configuration.backspin_dir.join("capture_all_output.yml")
    expect(record_path).to exist

    yaml_content = YAML.load_file(record_path)
    expect(yaml_content["format_version"]).to eq("3.0")

    command = yaml_content["commands"].first
    expect(command["command_type"]).to eq("Backspin::Capturer")
    expect(command["args"]).to eq(["<captured block>"])
    expect(command["stdout"]).to include("Hello from puts")
    expect(command["stdout"]).to include("Direct stdout write")
    expect(command["stdout"]).to include("From system command")
    expect(command["stdout"]).to include("From backticks")
    expect(command["stdout"]).to include("From Open3")
    expect(command["stderr"]).to include("Error message")
  end

  it "supports block capture via Backspin.run" do
    result = Backspin.run(name: "block_capture") do
      puts "Block output"
      :ok
    end

    expect(result.output).to eq(:ok)
    record_path = Backspin.configuration.backspin_dir.join("block_capture.yml")
    record_data = YAML.load_file(record_path)
    expect(record_data["commands"].first["command_type"]).to eq("Backspin::Capturer")
  end

  it "requires a record name" do
    expect do
      Backspin.capture("") { :ok }
    end.to raise_error(ArgumentError, /record_name is required/)
  end

  it "requires a block" do
    expect do
      Backspin.capture("no_block")
    end.to raise_error(ArgumentError, /block is required/)
  end

  it "raises when verifying without a record" do
    expect do
      Backspin.capture("missing_capture", mode: :verify) { puts "hi" }
    end.to raise_error(Backspin::RecordNotFoundError, /Record not found/)
  end

  it "raises when record has multiple commands for capture verification" do
    record_path = Backspin.configuration.backspin_dir.join("multi_capture_verify.yml")
    FileUtils.mkdir_p(File.dirname(record_path))
    File.write(record_path, {
      "format_version" => "3.0",
      "first_recorded_at" => "2024-01-01T00:00:00Z",
      "commands" => [
        {
          "command_type" => "Backspin::Capturer",
          "args" => ["<captured block>"],
          "stdout" => "one\n",
          "stderr" => "",
          "status" => 0,
          "recorded_at" => "2024-01-01T00:00:00Z"
        },
        {
          "command_type" => "Backspin::Capturer",
          "args" => ["<captured block>"],
          "stdout" => "two\n",
          "stderr" => "",
          "status" => 0,
          "recorded_at" => "2024-01-01T00:00:00Z"
        }
      ]
    }.to_yaml)

    expect do
      Backspin.capture("multi_capture_verify", mode: :verify) { puts "hi" }
    end.to raise_error(Backspin::RecordFormatError, /expected 1 command for capture, found 2/)
  end

  it "raises when record command type is run" do
    Backspin.run(["echo", "run"], name: "run_record")

    expect do
      Backspin.capture("run_record", mode: :verify) { puts "capture" }
    end.to raise_error(Backspin::RecordFormatError, /expected Backspin::Capturer/)
  end

  it "returns a failed result when raise_on_verification_failure is false" do
    Backspin.capture("capture_no_raise") do
      puts "Expected output"
    end

    Backspin.configure do |config|
      config.raise_on_verification_failure = false
    end

    result = Backspin.capture("capture_no_raise") do
      puts "Different output"
    end

    expect(result.verified?).to be false
    expect(result.error_message).to include("Output verification failed")
    expect(result.stdout).to eq("Different output\n")
    expect(result.expected_stdout).to eq("Expected output\n")
    expect(result.actual_stdout).to eq("Different output\n")
  end

  it "passes status 0 to capture matchers" do
    Backspin.capture("capture_status") do
      puts "Status output"
    end

    matcher = {
      status: ->(recorded, actual) { recorded == 0 && actual == 0 }
    }

    result = Backspin.capture("capture_status", matcher: matcher) do
      puts "Status output"
    end

    expect(result).to be_verified
  end

  it "raises on verification mismatch by default" do
    Backspin.capture("capture_verify") do
      puts "Expected output"
    end

    expect do
      Backspin.capture("capture_verify") do
        puts "Different output"
      end
    end.to raise_error(Backspin::VerificationError) do |error|
      expect(error.message).to include("Backspin verification failed!")
      expect(error.message).to include("Output verification failed")
    end
  end
end
