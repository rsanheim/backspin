# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Backspin.compare" do
  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  it "verifies two different commands that produce the same output" do
    result = Backspin.compare(
      reference: ["printf", "hello"],
      actual: ["sh", "-c", "printf hello"]
    )

    expect(result.verified?).to be(true)
    expect(result.expected.stdout).to eq("hello")
    expect(result.actual.stdout).to eq("hello")
    expect(result.expected.args).to eq(["printf", "hello"])
    expect(result.actual.args).to eq(["sh", "-c", "printf hello"])
  end

  it "writes no record file" do
    Backspin.compare(reference: "echo hi", actual: "echo hi")

    expect(Dir.glob(Backspin.configuration.backspin_dir.join("**", "*.yml"))).to be_empty
  end

  it "raises VerificationError with a diff and no empty Record line on mismatch" do
    expect {
      Backspin.compare(reference: "echo hello", actual: "echo goodbye")
    }.to raise_error(Backspin::VerificationError) { |error|
      expect(error.message).to include("-hello")
      expect(error.message).to include("+goodbye")
      expect(error.message).not_to include("Record:")
      expect(error.result.record_path).to be_nil
    }
  end

  it "returns an unverified result when raise_on_verification_failure is false" do
    Backspin.configure { |config| config.raise_on_verification_failure = false }

    result = Backspin.compare(reference: "echo hello", actual: "echo goodbye")

    expect(result.verified?).to be(false)
    expect(result.recorded?).to be(false)
    expect(result.diff).to include("-hello")
    expect(result.error_message).to include("Output verification failed")
  end

  it "compares exit status as well as output" do
    Backspin.configure { |config| config.raise_on_verification_failure = false }

    result = Backspin.compare(
      reference: ["sh", "-c", "printf boom; exit 0"],
      actual: ["sh", "-c", "printf boom; exit 3"]
    )

    expect(result.verified?).to be(false)
    expect(result.diff).to include("Exit status: expected 0, got 3")
  end

  it "applies the filter to both sides before comparing" do
    normalize = ->(snapshot) {
      snapshot.merge("stdout" => snapshot["stdout"].gsub(/took \d+ms/, "took [time]"))
    }

    result = Backspin.compare(
      reference: "echo 'done, took 12ms'",
      actual: "echo 'done, took 4500ms'",
      filter: normalize
    )

    expect(result.verified?).to be(true)
    expect(result.actual.stdout).to eq("done, took 4500ms\n")
  end

  it "supports a custom matcher" do
    result = Backspin.compare(
      reference: "echo hello",
      actual: "echo HELLO",
      matcher: ->(expected, actual) { expected["stdout"].downcase == actual["stdout"].downcase }
    )

    expect(result.verified?).to be(true)
  end

  it "passes env to both commands" do
    result = Backspin.compare(
      reference: ["sh", "-c", 'printf "%s" "$GREETING"'],
      actual: ["ruby", "-e", "print ENV.fetch('GREETING')"],
      env: {"GREETING" => "howdy"}
    )

    expect(result.verified?).to be(true)
    expect(result.actual.stdout).to eq("howdy")
  end

  it "raises when the reference command produces no output" do
    expect {
      Backspin.compare(
        reference: ["sh", "-c", "exit 127"],
        actual: ["sh", "-c", "exit 127"]
      )
    }.to raise_error(Backspin::ReferenceCommandError, /no output \(exit status 127\)/)
  end

  it "does not run the command under test when the reference produces no output" do
    marker = Backspin.configuration.backspin_dir.join("actual_ran")

    expect {
      Backspin.compare(
        reference: ["sh", "-c", "exit 1"],
        actual: ["sh", "-c", "touch #{marker}"]
      )
    }.to raise_error(Backspin::ReferenceCommandError)

    expect(File.exist?(marker)).to be(false)
  end
end
