# frozen_string_literal: true

require "spec_helper"

RSpec.describe Backspin::Record do
  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  let(:record_path) { Backspin.configuration.backspin_dir.join("test_record.yml") }

  it "rejects legacy format versions" do
    FileUtils.mkdir_p(File.dirname(record_path))
    File.write(record_path, {
      "format_version" => "2.0",
      "first_recorded_at" => "2024-01-01T00:00:00Z",
      "commands" => []
    }.to_yaml)

    expect do
      described_class.load_from_file(record_path)
    end.to raise_error(Backspin::RecordFormatError, /expected format version 3.0/)
  end

  it "loads records with Open3::Capture3 commands" do
    FileUtils.mkdir_p(File.dirname(record_path))
    File.write(record_path, {
      "format_version" => "3.0",
      "first_recorded_at" => "2024-01-01T00:00:00Z",
      "commands" => [
        {
          "command_type" => "Open3::Capture3",
          "args" => ["echo", "hello"],
          "stdout" => "hello\n",
          "stderr" => "",
          "status" => 0,
          "recorded_at" => "2024-01-01T00:00:00Z"
        }
      ]
    }.to_yaml)

    record = described_class.load_from_file(record_path)

    expect(record.commands.size).to eq(1)
    expect(record.commands.first.args).to eq(["echo", "hello"])
    expect(record.commands.first.stdout).to eq("hello\n")
  end

  it "includes env data when present" do
    FileUtils.mkdir_p(File.dirname(record_path))
    File.write(record_path, {
      "format_version" => "3.0",
      "first_recorded_at" => "2024-01-01T00:00:00Z",
      "commands" => [
        {
          "command_type" => "Open3::Capture3",
          "args" => ["ruby", "-e", "print ENV['FOO']"],
          "env" => {"FOO" => "bar"},
          "stdout" => "bar",
          "stderr" => "",
          "status" => 0,
          "recorded_at" => "2024-01-01T00:00:00Z"
        }
      ]
    }.to_yaml)

    record = described_class.load_from_file(record_path)

    expect(record.commands.first.env).to eq({"FOO" => "bar"})
  end

  it "raises on invalid YAML" do
    FileUtils.mkdir_p(File.dirname(record_path))
    File.write(record_path, "commands: [")

    expect do
      described_class.load_from_file(record_path)
    end.to raise_error(Backspin::RecordFormatError, /Invalid record format/)
  end

  it "rejects unknown command types" do
    FileUtils.mkdir_p(File.dirname(record_path))
    File.write(record_path, {
      "format_version" => "3.0",
      "first_recorded_at" => "2024-01-01T00:00:00Z",
      "commands" => [
        {
          "command_type" => "Kernel::System",
          "args" => ["echo", "hello"],
          "stdout" => "hello\n",
          "stderr" => "",
          "status" => 0,
          "recorded_at" => "2024-01-01T00:00:00Z"
        }
      ]
    }.to_yaml)

    expect do
      described_class.load_from_file(record_path)
    end.to raise_error(Backspin::RecordFormatError, /Unknown command type/)
  end

  it "raises when commands are missing" do
    FileUtils.mkdir_p(File.dirname(record_path))
    File.write(record_path, {
      "format_version" => "3.0",
      "first_recorded_at" => "2024-01-01T00:00:00Z"
    }.to_yaml)

    expect do
      described_class.load_from_file(record_path)
    end.to raise_error(Backspin::RecordFormatError, /missing commands/i)
  end
end
