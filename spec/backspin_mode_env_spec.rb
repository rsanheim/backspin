# frozen_string_literal: true

require "spec_helper"

RSpec.describe "BACKSPIN_MODE environment variable" do
  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  context "explicit mode kwarg takes precedence over env var" do
    it "mode: :record overrides BACKSPIN_MODE=verify" do
      ENV["BACKSPIN_MODE"] = "verify"

      result = Backspin.run(["echo", "explicit wins"], name: "explicit_record", mode: :record)

      expect(result).to be_recorded
      expect(result.actual.stdout).to eq("explicit wins\n")
    end

    it "mode: :verify overrides BACKSPIN_MODE=record" do
      Backspin.run(["echo", "first"], name: "explicit_verify", mode: :record)

      ENV["BACKSPIN_MODE"] = "record"

      result = Backspin.run(["echo", "first"], name: "explicit_verify", mode: :verify)

      expect(result).to be_verified
    end
  end

  context "BACKSPIN_MODE forces mode for run" do
    it "forces record mode (re-records instead of verifying)" do
      Backspin.run(["echo", "original"], name: "env_record_run", mode: :record)

      ENV["BACKSPIN_MODE"] = "record"

      result = Backspin.run(["echo", "re-recorded"], name: "env_record_run")

      expect(result).to be_recorded
      expect(result.actual.stdout).to eq("re-recorded\n")
    end

    it "forces verify mode" do
      Backspin.run(["echo", "recorded"], name: "env_verify_run", mode: :record)

      ENV["BACKSPIN_MODE"] = "verify"

      result = Backspin.run(["echo", "recorded"], name: "env_verify_run")

      expect(result).to be_verified
    end
  end

  context "BACKSPIN_MODE forces mode for capture" do
    it "forces record mode (re-records instead of verifying)" do
      Backspin.capture("env_record_capture") do
        puts "original"
      end

      ENV["BACKSPIN_MODE"] = "record"

      result = Backspin.capture("env_record_capture") do
        puts "re-recorded"
      end

      expect(result).to be_recorded
      expect(result.actual.stdout).to eq("re-recorded\n")
    end

    it "forces verify mode" do
      Backspin.capture("env_verify_capture") do
        puts "captured"
      end

      ENV["BACKSPIN_MODE"] = "verify"

      result = Backspin.capture("env_verify_capture") do
        puts "captured"
      end

      expect(result).to be_verified
    end
  end

  context "BACKSPIN_MODE=auto" do
    it "behaves the same as default (record then verify)" do
      ENV["BACKSPIN_MODE"] = "auto"

      result = Backspin.run(["echo", "auto"], name: "env_auto")
      expect(result).to be_recorded

      result = Backspin.run(["echo", "auto"], name: "env_auto")
      expect(result).to be_verified
    end
  end

  context "invalid values" do
    it "raises ArgumentError for invalid BACKSPIN_MODE" do
      ENV["BACKSPIN_MODE"] = "bogus"

      expect {
        Backspin.run(["echo", "hi"], name: "invalid_mode")
      }.to raise_error(ArgumentError, /Invalid BACKSPIN_MODE value: "bogus".*Allowed values: auto, record, verify/)
    end

    it "ignores an empty string" do
      ENV["BACKSPIN_MODE"] = ""

      result = Backspin.run(["echo", "empty"], name: "empty_env")

      expect(result).to be_recorded
    end

    it "ignores a whitespace-only string" do
      ENV["BACKSPIN_MODE"] = "   "

      result = Backspin.run(["echo", "whitespace"], name: "whitespace_env")

      expect(result).to be_recorded
    end
  end

  context "edge cases" do
    it "BACKSPIN_MODE=verify with no record raises RecordNotFoundError for run" do
      ENV["BACKSPIN_MODE"] = "verify"

      expect {
        Backspin.run(["echo", "missing"], name: "no_record_run")
      }.to raise_error(Backspin::RecordNotFoundError)
    end

    it "BACKSPIN_MODE=verify with no record raises RecordNotFoundError for capture" do
      ENV["BACKSPIN_MODE"] = "verify"

      expect {
        Backspin.capture("no_record_capture") do
          puts "missing"
        end
      }.to raise_error(Backspin::RecordNotFoundError)
    end

    it "works when logger is nil in auto mode" do
      Backspin.configure do |config|
        config.logger = nil
      end

      result = Backspin.run(["echo", "no logger"], name: "nil_logger_auto")

      expect(result).to be_recorded
    end

    it "works when logger is nil and mode resolves from env" do
      Backspin.run(["echo", "seed"], name: "nil_logger_env", mode: :record)

      Backspin.configure do |config|
        config.logger = nil
      end
      ENV["BACKSPIN_MODE"] = "verify"

      result = Backspin.run(["echo", "seed"], name: "nil_logger_env")

      expect(result).to be_verified
    end

    it "accepts case-insensitive values" do
      %w[RECORD Record record].each do |value|
        ENV["BACKSPIN_MODE"] = value

        result = Backspin.run(["echo", "case test"], name: "case_#{value}")

        expect(result).to be_recorded
      end
    end
  end
end
