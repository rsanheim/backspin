require "spec_helper"

RSpec.describe "Backspin filtering support" do
  before do
    Backspin.reset_configuration!
  end

  describe "Backspin.call with filter" do
    it "applies filter to recorded output before saving" do
      # Filter that normalizes timestamps in the format YYYY-MM-DD HH:MM:SS
      timestamp_filter = ->(data) {
        data["stdout"] = data["stdout"].gsub(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/, "TIMESTAMP")
        data
      }

      Backspin.call("timestamp_test", filter: timestamp_filter) do
        output, _stderr, _status = Open3.capture3("echo 'Test run at 2024-01-15 10:30:45'")
        expect(output).to include("2024-01-15 10:30:45")
      end

      # Verify the saved file has normalized timestamps
      record_path = Backspin.configuration.backspin_dir.join("timestamp_test.yaml")
      saved_data = YAML.load_file(record_path)
      expect(saved_data["commands"].first["stdout"]).to eq("Test run at TIMESTAMP\n")
    end

    it "applies filter to remove absolute paths" do
      path_filter = ->(data) {
        # Normalize paths like /Users/username/project to PROJECT_ROOT
        data["stdout"] = data["stdout"].gsub(/\/Users\/\w+\/\w+/, "PROJECT_ROOT")
        data
      }

      Backspin.call("path_test", filter: path_filter) do
        Open3.capture3("echo 'File saved to /Users/testuser/project/output.txt'")
      end

      record_path = Backspin.configuration.backspin_dir.join("path_test.yaml")
      saved_data = YAML.load_file(record_path)
      expect(saved_data["commands"].first["stdout"]).to eq("File saved to PROJECT_ROOT/output.txt\n")
    end

    it "applies filter to multiple commands" do
      counter_filter = ->(data) {
        # Replace any number with X
        data["stdout"] = data["stdout"].gsub(/\d+/, "X")
        data
      }

      Backspin.call("multi_command_filter", filter: counter_filter) do
        Open3.capture3("echo 'Count: 42'")
        Open3.capture3("echo 'Total: 100'")
      end

      record_path = Backspin.configuration.backspin_dir.join("multi_command_filter.yaml")
      saved_data = YAML.load_file(record_path)
      expect(saved_data["commands"][0]["stdout"]).to eq("Count: X\n")
      expect(saved_data["commands"][1]["stdout"]).to eq("Total: X\n")
    end

    it "filter receives full command data including stderr and status" do
      received_data = nil
      inspection_filter = ->(data) {
        received_data = data.dup
        data
      }

      Backspin.call("full_data_filter", filter: inspection_filter) do
        Open3.capture3("bash", "-c", "echo 'stdout message' && echo 'stderr message' >&2 && exit 42")
      end

      expect(received_data).to include(
        "command_type" => "Open3::Capture3",
        "args" => ["bash", "-c", "echo 'stdout message' && echo 'stderr message' >&2 && exit 42"],
        "stdout" => "stdout message\n",
        "stderr" => "stderr message\n",
        "status" => 42
      )
      expect(received_data).to have_key("recorded_at")
    end
  end

  describe "Backspin.use_record with filter" do
    it "applies filter when recording with :once mode" do
      filter = ->(data) {
        data["stdout"] = data["stdout"].upcase
        data
      }

      # First call - record with filter
      Backspin.use_record("use_record_filter", record: :once, filter: filter) do
        Open3.capture3("echo 'hello world'")
      end

      # Check the saved file has filtered content
      record_path = Backspin.configuration.backspin_dir.join("use_record_filter.yaml")
      saved_data = YAML.load_file(record_path)
      expect(saved_data["commands"].first["stdout"]).to eq("HELLO WORLD\n")

      # Second call - replay (filter not applied during replay)
      result2 = Backspin.use_record("use_record_filter", record: :once) do
        Open3.capture3("echo 'different output'")
      end

      # Should get the filtered (uppercase) version from the recording
      expect(result2[0]).to eq("HELLO WORLD\n")
    end

    it "applies filter with :all mode" do
      call_count = 0
      dynamic_filter = ->(data) {
        call_count += 1
        data["stdout"] = "filtered output #{call_count}\n"
        data
      }

      # First recording
      Backspin.use_record("all_mode_filter", record: :all, filter: dynamic_filter) do
        Open3.capture3("echo 'first'")
      end

      # Second recording (overwrites)
      Backspin.use_record("all_mode_filter", record: :all, filter: dynamic_filter) do
        Open3.capture3("echo 'second'")
      end

      record_path = Backspin.configuration.backspin_dir.join("all_mode_filter.yaml")
      saved_data = YAML.load_file(record_path)
      # Should have the second recording with filter applied
      expect(saved_data["commands"].first["stdout"]).to eq("filtered output 2\n")
    end

    it "applies filter with :new_episodes mode" do
      episode_filter = ->(data) {
        data["stdout"] = data["stdout"].gsub("episode", "EPISODE")
        data
      }

      # First recording
      Backspin.use_record("episodes_filter", record: :all, filter: episode_filter) do
        Open3.capture3("echo 'episode 1'")
      end

      # Add new episode
      Backspin.use_record("episodes_filter", record: :new_episodes, filter: episode_filter) do
        Open3.capture3("echo 'episode 2'")
      end

      record_path = Backspin.configuration.backspin_dir.join("episodes_filter.yaml")
      saved_data = YAML.load_file(record_path)
      expect(saved_data["commands"].map { |c| c["stdout"] }).to eq([
        "EPISODE 1\n",
        "EPISODE 2\n"
      ])
    end

    it "does not apply filter with :none mode" do
      # Create a recording without filter first
      Backspin.use_record("none_mode_test", record: :all) do
        Open3.capture3("echo 'original'")
      end

      # Try to use with filter in :none mode - filter should be ignored
      result = Backspin.use_record("none_mode_test", record: :none, filter: ->(d) {
        d["stdout"] = "FILTERED"
        d
      }) do
        Open3.capture3("echo 'anything'")
      end

      # Should get original recording, not filtered
      expect(result[0]).to eq("original\n")
    end
  end

  describe "filter edge cases" do
    it "handles nil filter gracefully" do
      Backspin.call("nil_filter", filter: nil) do
        output, _, _ = Open3.capture3("echo 'test'")
        expect(output).to eq("test\n")
      end

      record_path = Backspin.configuration.backspin_dir.join("nil_filter.yaml")
      saved_data = YAML.load_file(record_path)
      expect(saved_data["commands"].first["stdout"]).to eq("test\n")
    end

    it "filter can modify multiple fields" do
      multi_field_filter = ->(data) {
        data["stdout"] = "modified stdout"
        data["stderr"] = "modified stderr"
        data["status"] = 0
        data
      }

      Backspin.call("multi_field_filter", filter: multi_field_filter) do
        Open3.capture3("bash", "-c", "echo 'out' && echo 'err' >&2 && exit 1")
      end

      record_path = Backspin.configuration.backspin_dir.join("multi_field_filter.yaml")
      saved_data = YAML.load_file(record_path)
      command = saved_data["commands"].first
      expect(command["stdout"]).to eq("modified stdout")
      expect(command["stderr"]).to eq("modified stderr")
      expect(command["status"]).to eq(0)
    end

    it "preserves credential scrubbing when filter is applied" do
      Backspin.configuration.scrub_credentials = true

      filter = ->(data) {
        # Filter just uppercases, credential scrubbing should still happen
        data["stdout"] = data["stdout"].upcase
        data
      }

      Backspin.call("credential_filter", filter: filter) do
        Open3.capture3("echo 'My API key is AKIA1234567890ABCDEF'")
      end

      record_path = Backspin.configuration.backspin_dir.join("credential_filter.yaml")
      saved_data = YAML.load_file(record_path)
      # Should be uppercased AND have credentials scrubbed
      expect(saved_data["commands"].first["stdout"]).to eq("MY API KEY IS ********************\n")
    end
  end

  after do
    # Clean up test recordings
    FileUtils.rm_rf(Backspin.configuration.backspin_dir)
  end
end
