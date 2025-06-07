require "spec_helper"

RSpec.describe "Backspin match_on functionality" do
  around do |example|
    Timecop.freeze(static_time) do
      example.run
    end
  end

  describe "match_on with single field" do
    it "matches specified field with custom matcher and uses exact equality for others" do
      # Record a command with timestamp
      Backspin.run("match_on_single") do
        Open3.capture3("echo 'Current time: 2025-01-06 10:00:00'")
      end

      # Verify with different timestamp but same format
      result = Backspin.run("match_on_single",
        match_on: [:stdout, ->(recorded, actual) {
          # Match if both have a timestamp format
          recorded.match?(/Current time: \d{4}-\d{2}-\d{2}/) && 
          actual.match?(/Current time: \d{4}-\d{2}-\d{2}/)
        }]) do
        Open3.capture3("echo 'Current time: 2025-01-06 15:30:45'")
      end

      expect(result.verified?).to be true
    end

    it "fails when custom matcher returns false" do
      Backspin.run("match_on_fail") do
        Open3.capture3("echo 'Version: 1.2.3'")
      end

      result = Backspin.run("match_on_fail",
        match_on: [:stdout, ->(recorded, actual) {
          # Require major version to match
          recorded.match(/Version: 1\./) && actual.match(/Version: 1\./)
        }]) do
        Open3.capture3("echo 'Version: 2.0.0'")
      end

      expect(result.verified?).to be false
    end

    it "uses exact equality for non-matched fields" do
      Backspin.run("match_on_other_fields") do
        Open3.capture3("sh -c 'echo output; echo error >&2; exit 1'")
      end

      # Match stdout but stderr must be exact
      result = Backspin.run("match_on_other_fields",
        match_on: [:stdout, ->(recorded, actual) { true }]) do
        Open3.capture3("sh -c 'echo different; echo other_error >&2; exit 1'")
      end

      expect(result.verified?).to be false
      expect(result.diff).to include("stderr diff:")
      expect(result.diff).to include("-error")
      expect(result.diff).to include("+other_error")
    end
  end

  describe "match_on with multiple fields" do
    it "matches multiple fields with different matchers" do
      Backspin.run("match_on_multiple") do
        stdout, stderr, status = Open3.capture3("sh -c 'echo \"User: alice@example.com\"; echo \"Error: Connection timeout at 10:30:00\" >&2; exit 1'")
        [stdout, stderr, status.exitstatus]
      end

      result = Backspin.run("match_on_multiple",
        match_on: [
          [:stdout, ->(recorded, actual) {
            # Email format matches
            recorded.match(/User: \w+@\w+\.\w+/) && actual.match(/User: \w+@\w+\.\w+/)
          }],
          [:stderr, ->(recorded, actual) {
            # Error type matches, ignore timestamp
            recorded.match(/Error: Connection timeout/) && actual.match(/Error: Connection timeout/)
          }]
        ]) do
        stdout, stderr, status = Open3.capture3("sh -c 'echo \"User: bob@test.org\"; echo \"Error: Connection timeout at 15:45:30\" >&2; exit 1'")
        [stdout, stderr, status.exitstatus]
      end

      expect(result.verified?).to be true
    end

    it "fails if any custom matcher returns false" do
      Backspin.run("match_on_any_fail") do
        Open3.capture3("sh -c 'echo good; echo bad >&2'")
      end

      result = Backspin.run("match_on_any_fail",
        match_on: [
          [:stdout, ->(recorded, actual) { recorded == actual }],  # This will pass
          [:stderr, ->(recorded, actual) { false }]  # This will fail
        ]) do
        Open3.capture3("sh -c 'echo good; echo bad >&2'")
      end

      expect(result.verified?).to be false
    end
  end

  describe "edge cases" do
    it "handles nil values in matchers" do
      Backspin.run("match_on_nil") do
        Open3.capture3("echo test")
      end

      result = Backspin.run("match_on_nil",
        match_on: [:stderr, ->(recorded, actual) {
          # Both should be empty strings
          recorded.to_s.empty? && actual.to_s.empty?
        }]) do
        Open3.capture3("echo test")
      end

      expect(result.verified?).to be true
    end

    it "raises error for invalid field names" do
      Backspin.run("match_on_invalid") do
        Open3.capture3("echo test")
      end

      expect {
        Backspin.run("match_on_invalid",
          match_on: [:invalid_field, ->(r, a) { true }]) do
          Open3.capture3("echo test")
        end
      }.to raise_error(ArgumentError, /Invalid field name: invalid_field/)
    end

    it "raises error for invalid match_on format" do
      Backspin.run("match_on_bad_format") do
        Open3.capture3("echo test")
      end

      expect {
        Backspin.run("match_on_bad_format",
          match_on: "not_an_array") do
          Open3.capture3("echo test")
        end
      }.to raise_error(ArgumentError, /match_on must be an array/)
    end
  end

  describe "integration with run!" do
    it "works with run! method" do
      Backspin.run("match_on_run_bang") do
        Open3.capture3("echo 'Process ID: 12345'")
      end

      # Should not raise
      result = Backspin.run!("match_on_run_bang",
        match_on: [:stdout, ->(recorded, actual) {
          recorded.match(/Process ID: \d+/) && actual.match(/Process ID: \d+/)
        }]) do
        Open3.capture3("echo 'Process ID: 67890'")
      end

      expect(result.verified?).to be true
    end

    it "raises when match_on verification fails in run!" do
      Backspin.run("match_on_run_bang_fail") do
        Open3.capture3("echo 'Status: OK'")
      end

      expect {
        Backspin.run!("match_on_run_bang_fail",
          match_on: [:stdout, ->(recorded, actual) {
            recorded.include?("OK") && actual.include?("OK")
          }]) do
          Open3.capture3("echo 'Status: FAIL'")
        end
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end
end