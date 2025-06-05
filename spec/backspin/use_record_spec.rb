require "spec_helper"

RSpec.describe "Backspin.use_record" do
  let(:record_dir) { Pathname.new("tmp/backspin_data") }

  before do
    # Use tmp for integration tests that modify files
    Backspin.configure do |config|
      config.backspin_dir = record_dir
    end
    FileUtils.rm_rf(record_dir)
  end

  after do
    FileUtils.rm_rf(record_dir)
    Backspin.reset_configuration!
  end

  describe "VCR-style unified API" do
    it "records on first run, replays on subsequent runs" do
      # First run - should record
      first_result = Backspin.use_record("unified_test") do
        Open3.capture3("echo hello from use_record")
      end

      expect(first_result).to eq(["hello from use_record\n", "", 0])
      expect(record_dir.join("unified_test.yaml")).to exist

      # Second run - should replay without executing
      second_result = Backspin.use_record("unified_test") do
        Open3.capture3("echo this should not run")
      end

      # Should get the recorded output, not "this should not run"
      expect(second_result).to eq(["hello from use_record\n", "", 0])
    end

    it "requires record name" do
      expect {
        Backspin.use_record do
          Open3.capture3("echo auto-named")
        end
      }.to raise_error(ArgumentError, "wrong number of arguments (given 0, expected 1..2)")
    end

    it "raises ArgumentError when record name is nil" do
      expect {
        Backspin.use_record(nil) do
          Open3.capture3("echo test")
        end
      }.to raise_error(ArgumentError, "record_name is required")
    end

    it "raises ArgumentError when record name is empty" do
      expect {
        Backspin.use_record("") do
          Open3.capture3("echo test")
        end
      }.to raise_error(ArgumentError, "record_name is required")
    end

    it "supports record modes" do
      # Clean up any existing file first
      FileUtils.rm_f(record_dir.join("modes_test.yaml"))

      # Record initially
      Backspin.use_record("modes_test") do
        Open3.capture3("echo first")
      end

      # :once mode (default) - use existing record
      result = Backspin.use_record("modes_test", record: :once) do
        Open3.capture3("echo second")
      end
      expect(result[0]).to eq("first\n")

      # :all mode - always re-record
      result = Backspin.use_record("modes_test", record: :all) do
        Open3.capture3("echo third")
      end
      expect(result[0]).to eq("third\n")

      # Verify it was re-recorded
      result = Backspin.use_record("modes_test") do
        Open3.capture3("echo fourth")
      end
      expect(result[0]).to eq("third\n")
    end

    it "supports :none mode - never record" do
      # Ensure record doesn't exist
      FileUtils.rm_f(record_dir.join("none_mode_test.yaml"))

      expect {
        Backspin.use_record("none_mode_test", record: :none) do
          Open3.capture3("echo test")
        end
      }.to raise_error(Backspin::RecordNotFoundError)
    end

    it "supports :new_episodes mode - appends new recordings" do
      # Record initial command
      Backspin.use_record("episodes_test", record: :new_episodes) do
        Open3.capture3("echo episode1")
      end

      # Different command - should record new episode
      result = Backspin.use_record("episodes_test", record: :new_episodes) do
        Open3.capture3("echo episode2")
      end
      expect(result[0]).to eq("episode2\n")

      # Verify multiple recordings exist
      record_data = YAML.load_file(record_dir.join("episodes_test.yaml"))
      expect(record_data).to be_a(Hash)
      expect(record_data["format_version"]).to eq("2.0")
      expect(record_data["commands"]).to be_an(Array)
      expect(record_data["commands"].map { |r| r["stdout"] }).to include("episode1\n", "episode2\n")
    end

    it "returns stdout, stderr, and status like capture3" do
      stdout, stderr, status = Backspin.use_record("full_output_test") do
        Open3.capture3("sh -c 'echo stdout; echo stderr >&2; exit 42'")
      end

      expect(stdout).to eq("stdout\n")
      expect(stderr).to eq("stderr\n")
      expect(status).to eq(42)
    end

    it "supports options hash" do
      result = Backspin.use_record("options_test",
        record: :all,
        erb: true,
        preserve_exact_body_bytes: true) do
        Open3.capture3("echo with options")
      end

      expect(result[0]).to eq("with options\n")
    end
  end

  describe "block return values" do
    it "returns the value from the block" do
      result = Backspin.use_record("return_value_test") do
        stdout, _, _ = Open3.capture3("echo test")
        "custom return: #{stdout.strip}"
      end

      expect(result).to eq("custom return: test")
    end
  end

  describe "error handling" do
    it "preserves exceptions from the block" do
      expect {
        Backspin.use_record("exception_test") do
          raise "Something went wrong"
        end
      }.to raise_error("Something went wrong")
    end
  end
end
