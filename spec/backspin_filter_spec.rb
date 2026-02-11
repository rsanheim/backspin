# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Backspin record filters" do
  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  it "applies filters after scrubbing for run records" do
    scrubbed_seen = nil
    filter = lambda do |data|
      scrubbed_seen = data["stdout"]
      data.merge("stdout" => "filtered\n")
    end

    Backspin.run(["echo", "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"], name: "filter_run", filter: filter)

    expect(scrubbed_seen).to eq("AWS_ACCESS_KEY_ID=********************\n")
    record_path = Backspin.configuration.backspin_dir.join("filter_run.yml")
    record_data = YAML.load_file(record_path)
    expect(record_data["snapshot"]["stdout"]).to eq("filtered\n")
  end

  it "applies filters after scrubbing for capture records" do
    scrubbed_seen = nil
    filter = lambda do |data|
      scrubbed_seen = data["stdout"]
      data.merge("stdout" => "filtered\n", "stderr" => "filtered_err\n")
    end

    Backspin.capture("filter_capture", filter: filter) do
      puts "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"
      warn "Error: Invalid API_KEY=sk-1234567890abcdef1234567890abcdef"
    end

    expect(scrubbed_seen).to eq("AWS_ACCESS_KEY_ID=********************\n")
    record_path = Backspin.configuration.backspin_dir.join("filter_capture.yml")
    record_data = YAML.load_file(record_path)
    snapshot = record_data["snapshot"]
    expect(snapshot["stdout"]).to eq("filtered\n")
    expect(snapshot["stderr"]).to eq("filtered_err\n")
  end
end
