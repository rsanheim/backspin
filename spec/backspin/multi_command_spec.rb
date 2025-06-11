# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Backspin multi-command support" do
  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  let(:backspin_path) { Backspin.configuration.backspin_dir }

  context "recording multiple commands" do
    it "records and replays multiple commands in sequence" do
      record_name = "multi_command_test"

      # First run: record multiple commands
      Backspin.run(record_name) do
        stdout1, = Open3.capture3("echo command1")
        expect(stdout1).to eq("command1\n")

        stdout2, = Open3.capture3("echo command2")
        expect(stdout2).to eq("command2\n")

        stdout3, = Open3.capture3("echo command3")
        expect(stdout3).to eq("command3\n")
      end

      # Verify record was created with array
      record_path = backspin_path.join("#{record_name}.yml")
      expect(record_path).to exist

      record_data = YAML.load_file(record_path)
      expect(record_data).to be_a(Hash)
      expect(record_data["format_version"]).to eq("2.0")
      expect(record_data["commands"]).to be_an(Array)
      expect(record_data["commands"].size).to eq(3)
      expect(record_data["commands"].map { |cmd| cmd["stdout"] }).to eq(%W[command1\n command2\n command3\n])

      # Second run: replay from record
      replay_outputs = []
      Backspin.run(record_name) do
        stdout1, = Open3.capture3("echo command1")
        replay_outputs << stdout1

        stdout2, = Open3.capture3("echo command2")
        replay_outputs << stdout2

        stdout3, = Open3.capture3("echo command3")
        replay_outputs << stdout3
      end

      expect(replay_outputs).to eq(%W[command1\n command2\n command3\n])
    end

    it "handles mixed commands with different outputs" do
      record_name = "mixed_commands"

      Backspin.run(record_name) do
        # Different commands with different outputs
        stdout1, _, status1 = Open3.capture3("echo success")
        expect(stdout1).to eq("success\n")
        expect(status1.exitstatus).to eq(0)

        # Command that writes to stderr
        _, stderr2, status2 = Open3.capture3("ruby -e 'STDERR.puts \"error message\"'")
        expect(stderr2).to include("error message")
        expect(status2.exitstatus).to eq(0)

        # Command with non-zero exit
        _, _, status3 = Open3.capture3("ruby -e 'exit 42'")
        expect(status3.exitstatus).to eq(42)
      end

      # Verify record structure
      record_path = backspin_path.join("#{record_name}.yml")
      record_data = YAML.load_file(record_path)
      expect(record_data).to be_a(Hash)
      expect(record_data["format_version"]).to eq("2.0")
      expect(record_data["commands"]).to be_an(Array)
      expect(record_data["commands"].size).to eq(3)

      expect(record_data["commands"][0]["stdout"]).to eq("success\n")
      expect(record_data["commands"][0]["status"]).to eq(0)

      expect(record_data["commands"][1]["stderr"]).to include("error message")
      expect(record_data["commands"][1]["status"]).to eq(0)

      expect(record_data["commands"][2]["status"]).to eq(42)
    end

    it "fails gracefully when replaying with too few recordings" do
      record_name = "insufficient_recordings"

      # Record only 2 commands
      Backspin.run(record_name) do
        Open3.capture3("echo first")
        Open3.capture3("echo second")
      end

      # Try to replay 3 commands - should fail on the third
      expect do
        Backspin.run(record_name) do
          Open3.capture3("echo first")
          Open3.capture3("echo second")
          Open3.capture3("echo third") # This should fail
        end
      end.to raise_error(Backspin::RecordNotFoundError, /No more recorded commands/)
    end

    it "saves single commands as arrays for consistency" do
      record_name = "single_command_array"

      # Record single command (should save as array)
      Backspin.run(record_name) do
        stdout, = Open3.capture3("echo single")
        expect(stdout).to eq("single\n")
      end

      # Verify record is array even for single command
      record_path = backspin_path.join("#{record_name}.yml")
      record_data = YAML.load_file(record_path)
      expect(record_data).to be_a(Hash)
      expect(record_data["format_version"]).to eq("2.0")
      expect(record_data["commands"]).to be_an(Array)
      expect(record_data["commands"].size).to eq(1)
      expect(record_data["commands"].first["stdout"]).to eq("single\n")

      # Should still replay correctly
      Backspin.run(record_name) do
        stdout, = Open3.capture3("echo single")
        expect(stdout).to eq("single\n")
      end
    end
  end
end
