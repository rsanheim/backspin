require "spec_helper"

RSpec.describe Backspin do
  let(:backspin_path) { Backspin.configuration.backspin_dir }

  context "record" do
    it "records stdout, stderr, and status to a single yaml" do
      time = Time.now
      Timecop.freeze(time)
      result = Backspin.run("echo_hello", mode: :record) do
        Open3.capture3("echo hello")
      end
      expect(result.commands.size).to eq(1)
      expect(result.commands.first.method_class).to eq(Open3::Capture3)
      expect(result.commands.first.args).to eq(["echo", "hello"])
      expect(result.record_path.to_s).to end_with("echo_hello.yaml")
      expect(backspin_path.join("echo_hello.yaml")).to exist
      results = YAML.load_file(backspin_path.join("echo_hello.yaml"))
      expect(results).to be_a(Hash)
      expect(results["format_version"]).to eq("2.0")
      expect(results["first_recorded_at"]).not_to be_nil
      expect(results["commands"]).to be_an(Array)
      expect(results["commands"].size).to eq(1)
      expect(results["commands"].first).to include({
        "command_type" => "Open3::Capture3",
        "args" => ["echo", "hello"],
        "stdout" => "hello\n",
        "stderr" => "",
        "status" => 0,
        "recorded_at" => time.iso8601
      })
    end

    it "raises ArgumentError when no record name is provided" do
      expect {
        Backspin.run do
          Open3.capture3("echo hello")
        end
      }.to raise_error(ArgumentError, /wrong number of arguments/)
    end

    it "raises ArgumentError when record name is nil" do
      expect {
        Backspin.run(nil, mode: :record) do
          Open3.capture3("echo hello")
        end
      }.to raise_error(ArgumentError, "record_name is required")
    end

    it "raises ArgumentError when record name is empty" do
      expect {
        Backspin.run("", mode: :record) do
          Open3.capture3("echo hello")
        end
      }.to raise_error(ArgumentError, "record_name is required")
    end

    it "records multiple commands for single run / record" do
      time = Time.now
      Timecop.freeze(time)

      result = Backspin.run("multi_command", mode: :record) do
        Open3.capture3("echo first")
        Open3.capture3("echo second")
        Open3.capture3("echo third")
      end

      expect(result.commands.size).to eq(3)
      expect(result.commands[0].args).to eq(["echo", "first"])
      expect(result.commands[1].args).to eq(["echo", "second"])
      expect(result.commands[2].args).to eq(["echo", "third"])

      expect(result.record_path).to exist
      record_data = YAML.load_file(result.record_path)

      # Multiple commands should be stored in new format
      expect(record_data).to be_a(Hash)
      expect(record_data["format_version"]).to eq("2.0")
      expect(record_data["commands"]).to be_an(Array)
      expect(record_data["commands"].size).to eq(3)

      expect(record_data["commands"][0]).to include({
        "command_type" => "Open3::Capture3",
        "args" => ["echo", "first"],
        "stdout" => "first\n",
        "stderr" => "",
        "status" => 0,
        "recorded_at" => time.iso8601
      })

      expect(record_data["commands"][1]).to include({
        "command_type" => "Open3::Capture3",
        "args" => ["echo", "second"],
        "stdout" => "second\n",
        "stderr" => "",
        "status" => 0,
        "recorded_at" => time.iso8601
      })

      expect(record_data["commands"][2]).to include({
        "command_type" => "Open3::Capture3",
        "args" => ["echo", "third"],
        "stdout" => "third\n",
        "stderr" => "",
        "status" => 0,
        "recorded_at" => time.iso8601
      })
    end
  end
end
