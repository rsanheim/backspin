require "spec_helper"

RSpec.describe "Backspin.run" do
  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  describe "VCR-style unified API" do
    it "records on first run, verifies on subsequent runs in auto mode" do
      first_result = Backspin.run("unified_test") do
        Open3.capture3("echo hello from use_record")
      end

      expect(first_result.output).to eq(["hello from use_record\n", "", 0])
      expect(first_result.mode).to eq(:record)
      expect(Backspin.configuration.backspin_dir.join("unified_test.yml")).to exist

      # Second run - should verify (auto mode becomes verify when file exists)
      second_result = Backspin.run("unified_test") do
        Open3.capture3("echo hello from use_record")
      end

      expect(second_result.output).to eq(["hello from use_record\n", "", 0])
      expect(second_result.mode).to eq(:verify)
      expect(second_result.verified?).to eq(true)
    end

    it "replays without executing in playback mode" do
      # First record
      Backspin.run("playback_test") do
        Open3.capture3("echo hello from playback")
      end

      # Use playback mode to replay without executing
      result = Backspin.run("playback_test", mode: :playback) do
        stdout, stderr, status = Open3.capture3("echo this should not run")
        # Return the normalized status ourselves
        [stdout, stderr, status.respond_to?(:exitstatus) ? status.exitstatus : status]
      end

      # Should get the recorded output, not "this should not run"
      expect(result.output).to eq(["hello from playback\n", "", 0])
      expect(result.mode).to eq(:playback)
    end

    it "requires record name" do
      expect {
        Backspin.run do
          Open3.capture3("echo auto-named")
        end
      }.to raise_error(ArgumentError, "wrong number of arguments (given 0, expected 1..2)")
    end

    it "raises ArgumentError when record name is nil" do
      expect {
        Backspin.run(nil) do
          Open3.capture3("echo test")
        end
      }.to raise_error(ArgumentError, "record_name is required")
    end

    it "raises ArgumentError when record name is empty" do
      expect {
        Backspin.run("") do
          Open3.capture3("echo test")
        end
      }.to raise_error(ArgumentError, "record_name is required")
    end

    it "supports record modes" do
      # Record initially
      Backspin.run("modes_test") do
        Open3.capture3("echo first")
      end

      # Auto mode with existing file - verifies
      result = Backspin.run("modes_test") do
        Open3.capture3("echo first")  # Must match recorded command for verification
      end
      expect(result.output[0]).to eq("first\n")
      expect(result.mode).to eq(:verify)

      # :record mode - always re-record
      result = Backspin.run("modes_test", mode: :record) do
        Open3.capture3("echo third")
      end
      expect(result.output[0]).to eq("third\n")
      expect(result.mode).to eq(:record)

      # Verify it was re-recorded - now verifies against "third"
      result = Backspin.run("modes_test") do
        Open3.capture3("echo third")  # Must match new recording
      end
      expect(result.output[0]).to eq("third\n")
      expect(result.verified?).to eq(true)
    end

    it "supports :none mode - never record" do
      expect {
        Backspin.run("none_mode_test", mode: :playback) do
          Open3.capture3("echo test")
        end
      }.to raise_error(Backspin::RecordNotFoundError)
    end

    xit "supports :new_episodes mode - not supported in new API" do
      # This mode is not supported in the new API
      # Keeping the test as a placeholder to document the removed functionality
    end

    # TODO: remove this behavior and the spec?
    it "returns stdout, stderr, and status like capture3" do
      result = Backspin.run("full_output_test") do
        Open3.capture3("sh -c 'echo stdout; echo stderr >&2; exit 42'")
      end

      stdout, stderr, status = result.output
      expect(stdout).to eq("stdout\n")
      expect(stderr).to eq("stderr\n")
      expect(status).to eq(42)
    end

    it "supports options hash" do
      result = Backspin.run("options_test",
        mode: :record,
        erb: true,
        preserve_exact_body_bytes: true) do
        Open3.capture3("echo with options")
      end

      expect(result.output[0]).to eq("with options\n")
    end
  end

  describe "block return values" do
    it "returns the value from the block" do
      result = Backspin.run("return_value_test") do
        stdout, _, _ = Open3.capture3("echo test")
        "custom return: #{stdout.strip}"
      end

      expect(result.output).to eq("custom return: test")
    end
  end

  describe "error handling" do
    it "preserves exceptions from the block" do
      expect {
        Backspin.run("exception_test") do
          raise "Something went wrong"
        end
      }.to raise_error("Something went wrong")
    end
  end
end
