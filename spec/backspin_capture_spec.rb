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
