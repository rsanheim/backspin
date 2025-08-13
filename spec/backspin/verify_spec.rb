# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Backspin verify functionality" do
  around do |example|
    Timecop.freeze(static_time) do
      example.run
    end
  end

  describe "basic verification" do
    before do
      # First, record a command
      Backspin.run("echo_verify") do
        Open3.capture3("echo hello")
      end
    end

    it "passes when output matches recorded record" do
      result = Backspin.run("echo_verify") do
        Open3.capture3("echo hello")
      end

      expect(result.verified?).to be true
      expect(result.stdout).to eq("hello\n")
    end

    it "fails when output differs from recorded record" do
      expect do
        Backspin.run("echo_verify") do
          Open3.capture3("echo goodbye")
        end
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError) do |error|
        expect(error.message).to include("Backspin verification failed!")
        expect(error.message).to include("-hello")
        expect(error.message).to include("+goodbye")
      end
    end

    it "verifies stderr and exit status too" do
      # Record a command with stderr
      Backspin.run("stderr_test") do
        Open3.capture3("sh -c 'echo error >&2; exit 1'")
      end

      # Verify matching stderr and status
      result = Backspin.run("stderr_test") do
        Open3.capture3("sh -c 'echo error >&2; exit 1'")
      end

      expect(result.verified?).to be true

      # Verify non-matching stderr
      expect do
        Backspin.run("stderr_test") do
          Open3.capture3("sh -c 'echo different >&2; exit 1'")
        end
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError) do |error|
        expect(error.message).to include("Backspin verification failed!")
        expect(error.message).to include("-error")
        expect(error.message).to include("+different")
      end
    end
  end

  describe "verification modes" do
    it "can run in strict mode (default) - must match exactly" do
      Backspin.run("strict_test") do
        Open3.capture3("echo", "exact output")
      end

      # Running with different output will fail in strict mode
      expect do
        Backspin.run("strict_test") do
          Open3.capture3("echo", "different output")
        end
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError) do |error|
        expect(error.message).to include("Backspin verification failed!")
        expect(error.message).to include("-exact output")
        expect(error.message).to include("+different output")
      end
    end

    it "can run in playback mode - returns recorded output without running command" do
      Backspin.run("playback_test") do
        Open3.capture3("echo original")
      end

      result = Backspin.run("playback_test", mode: :playback) do
        # This would normally output "different" but playback mode should return "original"
        Open3.capture3("echo different")
      end

      expect(result.verified?).to be true
      expect(result.stdout).to eq("original\n")
      expect(result.playback?).to be true
    end

    it "can use custom matchers for flexible verification" do
      # Use a deterministic command for the test
      Backspin.run("version_test", mode: :record) do
        Open3.capture3("echo", "ruby version 3.4.5")
      end

      result = Backspin.run("version_test",
        matcher: lambda { |recorded, actual|
          recorded["stdout"].start_with?("ruby") && actual["stdout"].start_with?("ruby")
        }) do
        Open3.capture3("echo", "ruby version 3.4.5")
      end

      expect(result.verified?).to be true
    end
  end

  describe "error handling" do
    it "raises error when record doesn't exist" do
      expect do
        Backspin.run("nonexistent", mode: :verify) do
          Open3.capture3("echo test")
        end
      end.to raise_error(Backspin::RecordNotFoundError, /nonexistent.yml/)
    end

    it "provides helpful error messages on verification failure" do
      Backspin.run("failure_test") do
        Open3.capture3("echo expected")
      end

      expect do
        Backspin.run("failure_test") do
          Open3.capture3("echo actual")
        end
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError) do |error|
        expect(error.message).to include("Backspin verification failed!")
        expect(error.message).to include("Output verification failed")
        expect(error.message).to include("-expected")
        expect(error.message).to include("+actual")
      end
    end
  end
end
