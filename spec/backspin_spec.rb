# frozen_string_literal: true

require "spec_helper"

RSpec.describe Backspin do
  let(:backspin_path) { Backspin.configuration.backspin_dir }

  around do |example|
    Timecop.freeze(static_time) do
      example.run
    end
  end

  context "run" do
    it "records stdout, stderr, and status to a single yaml" do
      result = Backspin.run("echo_hello", mode: :record) do
        Open3.capture3("echo hello")
      end
      expect(result.commands.size).to eq(1)
      expect(result.commands.first.method_class).to eq(Open3::Capture3)
      expect(result.commands.first.args).to eq(%w[echo hello])
      expect(result.record.path.to_s).to end_with("echo_hello.yml")

      expect(backspin_path.join("echo_hello.yml")).to exist

      results = YAML.load_file(backspin_path.join("echo_hello.yml"))
      expect(results).to be_a(Hash)
      expect(results["format_version"]).to eq("2.0")
      expect(results["first_recorded_at"]).not_to be_nil
      expect(results["commands"]).to be_an(Array)
      expect(results["commands"].size).to eq(1)
      expect(results["commands"].first).to include({
        "command_type" => "Open3::Capture3",
        "args" => %w[echo hello],
        "stdout" => "hello\n",
        "stderr" => "",
        "status" => 0,
        "recorded_at" => static_time.iso8601
      })
    end

    it "records multiple commands for single run / record" do
      result = Backspin.run("multi_command", mode: :record) do
        Open3.capture3("echo first")
        Open3.capture3("echo second")
        Open3.capture3("echo third")
      end

      expect(result.commands.size).to eq(3)
      expect(result.commands[0].args).to eq(%w[echo first])
      expect(result.commands[1].args).to eq(%w[echo second])
      expect(result.commands[2].args).to eq(%w[echo third])

      record = backspin_path.join("multi_command.yml")
      expect(record).to exist
      record_data = YAML.load_file(record)

      # Multiple commands should be stored in new format
      expect(record_data).to be_a(Hash)
      expect(record_data["format_version"]).to eq("2.0")
      expect(record_data["commands"]).to be_an(Array)
      expect(record_data["commands"].size).to eq(3)

      expect(record_data["commands"][0]).to include({
        "command_type" => "Open3::Capture3",
        "args" => %w[echo first],
        "stdout" => "first\n",
        "stderr" => "",
        "status" => 0,
        "recorded_at" => static_time.iso8601
      })

      expect(record_data["commands"][1]).to include({
        "command_type" => "Open3::Capture3",
        "args" => %w[echo second],
        "stdout" => "second\n",
        "stderr" => "",
        "status" => 0,
        "recorded_at" => static_time.iso8601
      })

      expect(record_data["commands"][2]).to include({
        "command_type" => "Open3::Capture3",
        "args" => %w[echo third],
        "stdout" => "third\n",
        "stderr" => "",
        "status" => 0,
        "recorded_at" => static_time.iso8601
      })
    end
  end

  context "capture" do
    it "captures stdout and stderr from anything in the block (regardless of how called)"

    it "records to a record file with stdout and stderr, command_type: 'backspin-capturer'"

    it "acts the same as run: record when called with no matching record file"
    it "acts the same as run: verify when called with a matching record file"

    it "uses the same recorder and record interface as Backspin.run"
  end

  context "run with invalid args"
  it "raises ArgumentError when no record name is provided" do
    expect do
      Backspin.run do
        Open3.capture3("echo hello")
      end
    end.to raise_error(ArgumentError, /wrong number of arguments/)
  end

  it "raises ArgumentError when record name is nil" do
    expect do
      Backspin.run(nil, mode: :record) do
        Open3.capture3("echo hello")
      end
    end.to raise_error(ArgumentError, "record_name is required")
  end

  it "raises ArgumentError when record name is empty" do
    expect do
      Backspin.run("", mode: :record) do
        Open3.capture3("echo hello")
      end
    end.to raise_error(ArgumentError, "record_name is required")
  end
end
