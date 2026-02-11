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
      "format_version" => "3.0",
      "snapshot" => {}
    }.to_yaml)

    expect do
      described_class.load_from_file(record_path)
    end.to raise_error(Backspin::RecordFormatError, /expected format version 4.1/)
  end

  it "loads 4.1 records with Open3::Capture3 snapshots" do
    FileUtils.mkdir_p(File.dirname(record_path))
    File.write(record_path, {
      "format_version" => "4.1",
      "first_recorded_at" => "2024-01-01T00:00:00Z",
      "recorded_at" => "2024-01-01T00:00:00Z",
      "record_count" => 1,
      "snapshot" => {
        "command_type" => "Open3::Capture3",
        "args" => ["echo", "hello"],
        "stdout" => "hello\n",
        "stderr" => "",
        "status" => 0,
        "recorded_at" => "2024-01-01T00:00:00Z"
      }
    }.to_yaml)

    record = described_class.load_from_file(record_path)

    expect(record.snapshot.args).to eq(["echo", "hello"])
    expect(record.snapshot.stdout).to eq("hello\n")
    expect(record.first_recorded_at).to eq("2024-01-01T00:00:00Z")
    expect(record.recorded_at).to eq("2024-01-01T00:00:00Z")
    expect(record.record_count).to eq(1)
  end

  it "loads 4.0 records and backfills top-level metadata" do
    FileUtils.mkdir_p(File.dirname(record_path))
    File.write(record_path, {
      "format_version" => "4.0",
      "recorded_at" => "2024-01-01T00:00:00Z",
      "snapshot" => {
        "command_type" => "Open3::Capture3",
        "args" => ["ruby", "-e", "print ENV['FOO']"],
        "env" => {"FOO" => "bar"},
        "stdout" => "bar",
        "stderr" => "",
        "status" => 0,
        "recorded_at" => "2024-01-01T00:00:00Z"
      }
    }.to_yaml)

    record = described_class.load_from_file(record_path)

    expect(record.snapshot.env).to eq({"FOO" => "bar"})
    expect(record.first_recorded_at).to eq("2024-01-01T00:00:00Z")
    expect(record.recorded_at).to eq("2024-01-01T00:00:00Z")
    expect(record.record_count).to eq(1)
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
      "format_version" => "4.1",
      "first_recorded_at" => "2024-01-01T00:00:00Z",
      "recorded_at" => "2024-01-01T00:00:00Z",
      "record_count" => 1,
      "snapshot" => {
        "command_type" => "Kernel::System",
        "args" => ["echo", "hello"],
        "stdout" => "hello\n",
        "stderr" => "",
        "status" => 0,
        "recorded_at" => "2024-01-01T00:00:00Z"
      }
    }.to_yaml)

    expect do
      described_class.load_from_file(record_path)
    end.to raise_error(Backspin::RecordFormatError, /Unknown command type/)
  end

  it "raises when snapshot is missing" do
    FileUtils.mkdir_p(File.dirname(record_path))
    File.write(record_path, {
      "format_version" => "4.1",
      "first_recorded_at" => "2024-01-01T00:00:00Z",
      "recorded_at" => "2024-01-01T00:00:00Z",
      "record_count" => 1
    }.to_yaml)

    expect do
      described_class.load_from_file(record_path)
    end.to raise_error(Backspin::RecordFormatError, /missing snapshot/i)
  end

  it "requires first_recorded_at for 4.1 records" do
    FileUtils.mkdir_p(File.dirname(record_path))
    File.write(record_path, {
      "format_version" => "4.1",
      "recorded_at" => "2024-01-01T00:00:00Z",
      "record_count" => 1,
      "snapshot" => {
        "command_type" => "Open3::Capture3",
        "args" => ["echo", "hello"],
        "stdout" => "hello\n",
        "stderr" => "",
        "status" => 0,
        "recorded_at" => "2024-01-01T00:00:00Z"
      }
    }.to_yaml)

    expect do
      described_class.load_from_file(record_path)
    end.to raise_error(Backspin::RecordFormatError, /missing first_recorded_at/i)
  end

  it "requires record_count to be a positive integer for 4.1 records" do
    FileUtils.mkdir_p(File.dirname(record_path))
    File.write(record_path, {
      "format_version" => "4.1",
      "first_recorded_at" => "2024-01-01T00:00:00Z",
      "recorded_at" => "2024-01-01T00:00:00Z",
      "record_count" => 0,
      "snapshot" => {
        "command_type" => "Open3::Capture3",
        "args" => ["echo", "hello"],
        "stdout" => "hello\n",
        "stderr" => "",
        "status" => 0,
        "recorded_at" => "2024-01-01T00:00:00Z"
      }
    }.to_yaml)

    expect do
      described_class.load_from_file(record_path)
    end.to raise_error(Backspin::RecordFormatError, /record_count must be a positive integer/i)
  end
end
