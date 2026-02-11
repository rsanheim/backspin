# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Record format v4.1" do
  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  def expect_iso8601(value)
    expect(value).to be_a(String)
    expect { Time.iso8601(value) }.not_to raise_error
  end

  def expect_v4_1_record_schema(record_data, command_type:)
    expect(record_data["format_version"]).to eq("4.1")
    expect_iso8601(record_data["first_recorded_at"])
    expect_iso8601(record_data["recorded_at"])
    expect(record_data["record_count"]).to be_a(Integer)
    expect(record_data["record_count"]).to be >= 1

    snapshot = record_data["snapshot"]
    expect(snapshot).to be_a(Hash)
    expect(snapshot["command_type"]).to eq(command_type)
    expect(snapshot).to include("args", "stdout", "stderr", "status", "recorded_at")
    expect_iso8601(snapshot["recorded_at"])
    expect(snapshot["recorded_at"]).to eq(record_data["recorded_at"])
  end

  it "writes run records that match the v4.1 schema" do
    Backspin.run(["echo", "hello"], name: "run_schema")

    record_path = Backspin.configuration.backspin_dir.join("run_schema.yml")
    record_data = YAML.load_file(record_path)

    expect_v4_1_record_schema(record_data, command_type: "Open3::Capture3")
  end

  it "writes capture records that match the v4.1 schema" do
    Backspin.capture("capture_schema") do
      puts "hello"
    end

    record_path = Backspin.configuration.backspin_dir.join("capture_schema.yml")
    record_data = YAML.load_file(record_path)

    expect_v4_1_record_schema(record_data, command_type: "Backspin::Capturer")
  end

  it "re-records by updating recorded_at while keeping first_recorded_at stable" do
    first_time = Time.utc(2026, 1, 1, 10, 0, 0)
    second_time = Time.utc(2026, 2, 1, 10, 0, 0)

    Timecop.freeze(first_time) do
      Backspin.run(["echo", "first"], name: "rerun_metadata", mode: :record)
    end

    Timecop.freeze(second_time) do
      Backspin.run(["echo", "second"], name: "rerun_metadata", mode: :record)
    end

    record_path = Backspin.configuration.backspin_dir.join("rerun_metadata.yml")
    record_data = YAML.load_file(record_path)

    expect_v4_1_record_schema(record_data, command_type: "Open3::Capture3")
    expect(record_data["first_recorded_at"]).to eq(first_time.iso8601)
    expect(record_data["recorded_at"]).to eq(second_time.iso8601)
    expect(record_data["record_count"]).to eq(2)
    expect(record_data["snapshot"]["stdout"]).to eq("second\n")
  end

  it "upgrades a 4.0 record to v4.1 metadata on re-record" do
    record_path = Backspin.configuration.backspin_dir.join("upgrade_from_v4_0.yml")
    FileUtils.mkdir_p(File.dirname(record_path))
    File.write(record_path, {
      "format_version" => "4.0",
      "recorded_at" => "2026-01-01T10:00:00Z",
      "snapshot" => {
        "command_type" => "Open3::Capture3",
        "args" => ["echo", "old"],
        "stdout" => "old\n",
        "stderr" => "",
        "status" => 0,
        "recorded_at" => "2026-01-01T10:00:00Z"
      }
    }.to_yaml)

    Timecop.freeze(Time.utc(2026, 2, 1, 10, 0, 0)) do
      Backspin.run(["echo", "new"], name: "upgrade_from_v4_0", mode: :record)
    end

    updated_record = YAML.load_file(record_path)

    expect_v4_1_record_schema(updated_record, command_type: "Open3::Capture3")
    expect(updated_record["first_recorded_at"]).to eq("2026-01-01T10:00:00Z")
    expect(updated_record["recorded_at"]).to eq("2026-02-01T10:00:00Z")
    expect(updated_record["record_count"]).to eq(2)
    expect(updated_record["snapshot"]["stdout"]).to eq("new\n")
  end
end
