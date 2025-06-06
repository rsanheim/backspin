# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Backspin.run unified API" do
  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  describe "Backspin.run" do
    context "basic usage" do
      it "records on first run when record doesn't exist" do
        result = Backspin.run("unified_basic") do
          Open3.capture3("echo hello unified")
        end

        expect(result).to be_recorded
        expect(result).not_to be_verified
        expect(result.all_stdout).to eq(["hello unified\n"])
        expect(result.all_stderr).to eq([""])
        expect(result.all_status).to eq([0])
        expect(result).to be_success

        # Verify file was created
        expect(Backspin.configuration.backspin_dir.join("unified_basic.yml")).to exist
      end

      it "verifies on subsequent runs when record exists" do
        # First run - record
        Backspin.run("unified_verify") do
          Open3.capture3("echo first run")
        end

        # Second run - verify
        result = Backspin.run("unified_verify") do
          Open3.capture3("echo first run")
        end

        expect(result).not_to be_recorded
        expect(result).to be_verified
        expect(result.all_stdout).to eq(["first run\n"])
      end

      it "returns false for verified? when output doesn't match" do
        # Record
        Backspin.run("unified_mismatch") do
          Open3.capture3("echo original")
        end

        # Verify with different output
        result = Backspin.run("unified_mismatch") do
          Open3.capture3("echo different")
        end

        expect(result).not_to be_verified
        expect(result.diff).to include("Command 1:")
        expect(result.diff).to include("-original")
        expect(result.diff).to include("+different")
      end
    end

    context "with explicit mode option" do
      it "always records with mode: :record" do
        # First run
        Backspin.run("mode_record", mode: :record) do
          Open3.capture3("echo first")
        end

        # Second run with mode: :record should overwrite
        result = Backspin.run("mode_record", mode: :record) do
          Open3.capture3("echo second")
        end

        expect(result).to be_recorded
        expect(result.stdout).to eq("second\n")

        # Verify it was overwritten
        result = Backspin.run("mode_record", mode: :verify) do
          Open3.capture3("echo second")
        end
        expect(result).to be_verified
      end

      it "always verifies with mode: :verify" do
        # Create record first
        Backspin.run("mode_verify", mode: :record) do
          Open3.capture3("echo test")
        end

        # Verify mode
        result = Backspin.run("mode_verify", mode: :verify) do
          Open3.capture3("echo test")
        end

        expect(result).not_to be_recorded
        expect(result).to be_verified
      end

      it "raises error with mode: :verify when record doesn't exist" do
        expect do
          Backspin.run("nonexistent", mode: :verify) do
            Open3.capture3("echo test")
          end
        end.to raise_error(Backspin::RecordNotFoundError)
      end

      it "returns recorded output with mode: :playback" do
        # Create record
        Backspin.run("playback_test", mode: :record) do
          Open3.capture3("echo playback")
        end

        # Playback mode
        result = Backspin.run("playback_test", mode: :playback) do
          Open3.capture3("echo this should not execute")
        end

        expect(result).to be_playback
        expect(result).to be_verified # Always true for playback
        expect(result.stdout).to eq("playback\n")
      end
    end

    context "with custom matcher" do
      it "uses custom matcher for verification" do
        # Record
        Backspin.run("custom_matcher") do
          Open3.capture3("ruby --version")
        end

        # Verify with custom matcher
        result = Backspin.run("custom_matcher",
          matcher: lambda { |recorded, actual|
            recorded["stdout"].start_with?("ruby") &&
            actual["stdout"].start_with?("ruby")
          }) do
          Open3.capture3("ruby --version")
        end

        expect(result).to be_verified
      end
    end

    context "with different return values" do
      it "handles custom return values from block" do
        result = Backspin.run("custom_return") do
          stdout, = Open3.capture3("echo test")
          {output: stdout.strip, processed: true}
        end

        expect(result.output).to eq({output: "test", processed: true})
      end

      it "handles capture3 array format" do
        result = Backspin.run("capture3_format") do
          Open3.capture3("echo out; echo err >&2; exit 42")
        end

        expect(result.stdout).to eq("out\n")
        expect(result.stderr).to eq("err\n")
        expect(result.status).to eq(42)
        expect(result).to be_failure
      end
    end

    context "error handling" do
      it "requires record_name" do
        expect do
          Backspin.run(nil) { Open3.capture3("echo test") }
        end.to raise_error(ArgumentError, "record_name is required")
      end

      it "requires a block" do
        expect do
          Backspin.run("no_block")
        end.to raise_error(ArgumentError, "block is required")
      end

      it "preserves exceptions from the block" do
        expect do
          Backspin.run("exception_test") do
            raise "Custom error"
          end
        end.to raise_error("Custom error")
      end
    end
  end

  describe "Backspin.run!" do
    it "returns result on successful verification" do
      # Record
      Backspin.run("bang_success") do
        Open3.capture3("echo success")
      end

      # Verify with run!
      result = Backspin.run!("bang_success") do
        Open3.capture3("echo success")
      end

      expect(result).to be_verified
      expect(result.stdout).to eq("success\n")
    end

    it "raises on verification failure" do
      # Record
      Backspin.run("bang_failure") do
        Open3.capture3("echo original")
      end

      # Verify with different output
      expect do
        Backspin.run!("bang_failure") do
          Open3.capture3("echo different")
        end
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError) do |error|
        expect(error.message).to include("Backspin verification failed!")
        expect(error.message).to include("Output verification failed")
        expect(error.message).to include("Command 1:")
        expect(error.message).to include("stdout differs")
        expect(error.message).to include("-original")
        expect(error.message).to include("+different")
      end
    end

    it "returns result when recording" do
      result = Backspin.run!("bang_record") do
        Open3.capture3("echo recording")
      end

      expect(result).to be_recorded
      expect(result.stdout).to eq("recording\n")
    end
  end

  describe "RecordResult" do
    it "provides helpful methods" do
      result = Backspin.run("result_methods") do
        Open3.capture3("sh -c 'echo stdout; echo stderr >&2; exit 0'")
      end

      expect(result.to_h).to include(
        mode: :record,
        recorded: true,
        stdout: "stdout\n",
        stderr: "stderr\n",
        status: 0
      )

      # Verify that verified is nil but not included in the hash
      expect(result.verified?).to be_nil

      expect(result.inspect).to match(/RecordResult mode=record/)
    end
  end
end
