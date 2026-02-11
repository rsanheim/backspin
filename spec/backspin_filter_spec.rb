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

  it "applies filters to a mutable copy and keeps snapshot serialization immutable" do
    result = Backspin.run(["echo", "hello"], name: "filter_copy", filter: lambda { |data|
      data["stdout"].gsub!("hello", "filtered")
      data["args"] << "extra"
      data
    })

    expect(result.actual.to_h["stdout"]).to eq("hello\n")
    expect(result.actual.to_h["args"]).to eq(["echo", "hello"])

    record_path = Backspin.configuration.backspin_dir.join("filter_copy.yml")
    record_data = YAML.load_file(record_path)
    expect(record_data["snapshot"]["stdout"]).to eq("filtered\n")
    expect(record_data["snapshot"]["args"]).to eq(["echo", "hello", "extra"])
  end

  it "applies filter to expected and actual during verify by default for run" do
    filter = lambda do |data|
      data.merge("stdout" => data["stdout"].gsub(/id=\d+/, "id=[ID]"))
    end

    Backspin.run(["echo", "id=123"], name: "filter_on_both_run", mode: :record, filter: filter)
    result = Backspin.run(["echo", "id=999"], name: "filter_on_both_run", mode: :verify, filter: filter)

    expect(result).to be_verified
  end

  it "can restrict filter application to record-only verify behavior for run" do
    filter = lambda do |data|
      data.merge("stdout" => data["stdout"].gsub(/id=\d+/, "id=[ID]"))
    end

    Backspin.run(
      ["echo", "id=123"],
      name: "filter_on_record_run",
      mode: :record,
      filter: filter,
      filter_on: :record
    )

    expect do
      Backspin.run(
        ["echo", "id=999"],
        name: "filter_on_record_run",
        mode: :verify,
        filter: filter,
        filter_on: :record
      )
    end.to raise_error(Backspin::VerificationError)
  end

  it "provides filtered hashes to proc matchers when filter_on is :both" do
    filter = lambda do |data|
      data.merge("stdout" => data["stdout"].gsub(/id=\d+/, "id=[ID]"))
    end
    seen = nil
    matcher = lambda do |recorded, actual|
      seen = [recorded["stdout"], actual["stdout"]]
      recorded["stdout"] == actual["stdout"]
    end

    Backspin.run(["echo", "id=100"], name: "filter_matcher_interaction", mode: :record, filter: filter)
    result = Backspin.run(
      ["echo", "id=200"],
      name: "filter_matcher_interaction",
      mode: :verify,
      filter: filter,
      matcher: matcher
    )

    expect(result).to be_verified
    expect(seen).to eq(["id=[ID]\n", "id=[ID]\n"])
  end

  it "generates diffs from filtered values when filter_on is :both" do
    filter = lambda do |data|
      data.merge("stdout" => data["stdout"].gsub(/id=\d+/, "id=[ID]"))
    end

    Backspin.run(["echo", "id=123 one"], name: "filter_diff_output", mode: :record, filter: filter)

    Backspin.configure do |config|
      config.raise_on_verification_failure = false
    end

    result = Backspin.run(
      ["echo", "id=999 two"],
      name: "filter_diff_output",
      mode: :verify,
      filter: filter
    )

    expect(result.verified?).to be false
    expect(result.diff).to include("-id=[ID] one")
    expect(result.diff).to include("+id=[ID] two")
    expect(result.diff).not_to include("id=123")
    expect(result.diff).not_to include("id=999")
  end

  it "applies filter to expected and actual during verify by default for capture" do
    filter = lambda do |data|
      data.merge("stdout" => data["stdout"].gsub(/id=\d+/, "id=[ID]"))
    end

    Backspin.capture("filter_on_both_capture", mode: :record, filter: filter) do
      puts "id=111"
    end

    result = Backspin.capture("filter_on_both_capture", mode: :verify, filter: filter) do
      puts "id=222"
    end

    expect(result).to be_verified
  end

  it "can restrict filter application to record-only verify behavior for capture" do
    filter = lambda do |data|
      data.merge("stdout" => data["stdout"].gsub(/id=\d+/, "id=[ID]"))
    end

    Backspin.capture("filter_on_record_capture", mode: :record, filter: filter, filter_on: :record) do
      puts "id=111"
    end

    expect do
      Backspin.capture("filter_on_record_capture", mode: :verify, filter: filter, filter_on: :record) do
        puts "id=222"
      end
    end.to raise_error(Backspin::VerificationError)
  end
end
