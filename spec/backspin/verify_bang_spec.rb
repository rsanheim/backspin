require "spec_helper"

RSpec.describe "Backspin verify! functionality" do
  let(:record_dir) { Pathname.new(File.join(Dir.pwd, "..")).join("tmp", "backspin") }

  before do
    # Record a command for testing
    Backspin.call("echo_verify_bang") do
      Open3.capture3("echo hello")
    end
  end

  it "succeeds when output matches recorded record" do
    # Should not raise an error
    result = Backspin.verify!("echo_verify_bang") do
      Open3.capture3("echo hello")
    end

    expect(result.verified?).to be true
    expect(result.output).to eq("hello\n")
  end

  it "raises an RSpec expectation error when output differs from recorded record" do
    expect {
      Backspin.verify!("echo_verify_bang") do
        Open3.capture3("echo goodbye")
      end
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Backspin verification failed!/)
  end

  it "includes useful information in the error message" do
    Backspin.verify!("echo_verify_bang") do
      Open3.capture3("echo goodbye")
    end
    fail "Expected RSpec::Expectations::ExpectationNotMetError to be raised"
  rescue RSpec::Expectations::ExpectationNotMetError => e
    expect(e.message).to include("Backspin verification failed!")
    expect(e.message).to include("Record:")
    expect(e.message).to include("Expected output:")
    expect(e.message).to include("hello")
    expect(e.message).to include("Actual output:")
    expect(e.message).to include("goodbye")
    expect(e.message).to include("Diff:")
    expect(e.message).to include("-hello")
    expect(e.message).to include("+goodbye")
  end

  it "works with custom matchers and raises on matcher failure" do
    expect {
      Backspin.verify!("echo_verify_bang",
        matcher: ->(recorded, actual) {
          # This matcher will always fail
          false
        }) do
        Open3.capture3("echo hello")
      end
    }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /Backspin verification failed!/)
  end

  it "works in playback mode and never raises" do
    # Playback mode always returns verified: true, so verify! should never raise
    result = Backspin.verify!("echo_verify_bang", mode: :playback) do
      Open3.capture3("echo anything")  # Command not actually executed
    end

    expect(result.verified?).to be true
    expect(result.command_executed?).to be false
  end
end
