# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Backspin unified matcher functionality" do
  around do |example|
    Timecop.freeze(static_time) do
      example.run
    end
  end

  describe "matcher with single field" do
    it "matches specified field with custom matcher and uses exact equality for others" do
      # Record a command with timestamp
      Backspin.run("match_on_single") do
        Open3.capture3("echo 'Current time: 2025-01-06 10:00:00'")
      end

      # Verify with different timestamp but same format
      result = Backspin.run("match_on_single",
        matcher: {stdout: lambda { |recorded, actual|
          # Match if both have a timestamp format
          recorded.match?(/Current time: \d{4}-\d{2}-\d{2}/) &&
          actual.match?(/Current time: \d{4}-\d{2}-\d{2}/)
        }}) do
        Open3.capture3("echo 'Current time: 2025-01-06 15:30:45'")
      end

      expect(result.verified?).to be true
    end

    it "fails when custom matcher returns false" do
      Backspin.run("match_on_fail") do
        Open3.capture3("echo 'Version: 1.2.3'")
      end

      result = Backspin.run("match_on_fail",
        matcher: {stdout: lambda { |recorded, actual|
          # Require major version to match
          recorded.match(/Version: 1\./) && actual.match(/Version: 1\./)
        }}) do
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
        matcher: {stdout: ->(_recorded, _actual) { true }}) do
        Open3.capture3("sh -c 'echo different; echo other_error >&2; exit 1'")
      end

      expect(result.verified?).to be false
      expect(result.diff).to include("stderr diff:")
      expect(result.diff).to include("-error")
      expect(result.diff).to include("+other_error")
    end
  end

  describe "matcher with multiple fields" do
    it "matches multiple fields with different matchers" do
      Backspin.run("match_on_multiple") do
        stdout, stderr, status = Open3.capture3("sh -c 'echo \"User: alice@example.com\"; echo \"Error: Connection timeout at 10:30:00\" >&2; exit 1'")
        [stdout, stderr, status.exitstatus]
      end

      result = Backspin.run("match_on_multiple",
        matcher: {
          stdout: lambda { |recorded, actual|
            # Email format matches
            recorded.match(/User: \w+@\w+\.\w+/) && actual.match(/User: \w+@\w+\.\w+/)
          },
          stderr: lambda { |recorded, actual|
            # Error type matches, ignore timestamp
            recorded.match(/Error: Connection timeout/) && actual.match(/Error: Connection timeout/)
          }
        }) do
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
        matcher: {
          stdout: ->(recorded, actual) { recorded == actual }, # This will pass
          stderr: ->(_recorded, _actual) { false } # This will fail
        }) do
        Open3.capture3("sh -c 'echo good; echo good >&2'")
      end

      pp result
      pp result.error_message
      pp result.all_stderr
      diff = result.command_diffs.first
      pp diff.diff
      pp diff.recorded_command.class
      pp diff.actual_command.class
      pp diff.recorded_command.stderr
      pp diff.actual_command.stderr
      expect(result.verified?).to be false
    end
  end

  describe "edge cases" do
    it "handles nil values in matchers" do
      Backspin.run("match_on_nil") do
        Open3.capture3("echo test")
      end

      result = Backspin.run("match_on_nil",
        matcher: {stderr: lambda { |recorded, actual|
          # Both should be empty strings
          recorded.to_s.empty? && actual.to_s.empty?
        }}) do
        Open3.capture3("echo test")
      end

      expect(result.verified?).to be true
    end

    it "raises error for invalid field names" do
      Backspin.run("match_on_invalid") do
        Open3.capture3("echo test")
      end

      expect do
        Backspin.run("match_on_invalid",
          matcher: {invalid_field: ->(_r, _a) { true }}) do
          Open3.capture3("echo test")
        end
      end.to raise_error(ArgumentError, /Invalid matcher key: invalid_field/)
    end

    it "raises error for invalid matcher format" do
      Backspin.run("match_on_bad_format") do
        Open3.capture3("echo test")
      end

      expect do
        Backspin.run("match_on_bad_format",
          matcher: "not_a_valid_matcher") do
          Open3.capture3("echo test")
        end
      end.to raise_error(ArgumentError, /Matcher must be a Proc or Hash/)
    end
  end

  describe ":all matcher" do
    it "receives full command hashes with all fields" do
      received_hashes = nil

      # Record a command
      Backspin.run("all_matcher_basic", mode: :record) do
        Open3.capture3("echo", "hello world")
      end

      # Verify with :all matcher
      result = Backspin.run("all_matcher_basic", mode: :verify,
        matcher: {
          all: lambda { |recorded, actual|
            received_hashes = {recorded: recorded, actual: actual}
            true
          }
        }) do
        Open3.capture3("echo", "hello world")
      end

      expect(result.verified?).to be true
      expect(received_hashes).not_to be_nil

      # :all matcher receives complete command data
      expect(received_hashes[:recorded].keys).to include("stdout", "stderr", "status", "command_type", "args")
      expect(received_hashes[:recorded]["stdout"]).to eq("hello world\n")
      expect(received_hashes[:recorded]["stderr"]).to eq("")
      expect(received_hashes[:recorded]["status"]).to eq(0)
      expect(received_hashes[:recorded]["command_type"]).to eq("Open3::Capture3")
    end

    it "can implement custom verification logic across all fields" do
      # Record a command with specific output
      Backspin.run("all_matcher_custom", mode: :record) do
        Open3.capture3("sh", "-c", "echo 'PASS: test 1'; echo 'WARNING: minor issue' >&2")
      end

      # Custom matcher that checks for specific patterns across fields
      result = Backspin.run("all_matcher_custom", mode: :verify,
        matcher: {
          all: lambda { |_recorded, actual|
            # Check that stdout contains PASS and stderr contains WARNING
            actual["stdout"].include?("PASS") && actual["stderr"].include?("WARNING")
          }
        }) do
        Open3.capture3("sh", "-c", "echo 'PASS: test 1'; echo 'WARNING: minor issue' >&2")
      end

      expect(result.verified?).to be true

      # Should fail if output doesn't match pattern
      result2 = Backspin.run("all_matcher_custom", mode: :verify,
        matcher: {
          all: lambda { |_recorded, actual|
            actual["stdout"].include?("PASS") && actual["stderr"].include?("WARNING")
          }
        }) do
        Open3.capture3("sh", "-c", "echo 'FAIL: test 1'; echo 'OK: no issues' >&2")
      end

      expect(result2.verified?).to be false
    end

    it "checks both :all and field matchers independently" do
      matchers_called = []

      # Record
      Backspin.run("all_short_circuit", mode: :record) do
        Open3.capture3("echo", "test")
      end

      # Verify with failing :all matcher but passing field matcher
      result = Backspin.run("all_short_circuit", mode: :verify,
        matcher: {
          all: lambda { |_r, _a|
            matchers_called << :all
            false # Fails
          },
          stdout: lambda { |_r, _a|
            matchers_called << :stdout
            true # Passes
          }
        }) do
        Open3.capture3("echo", "test")
      end

      expect(result.verified?).to be false
      # Both matchers are called (no short-circuit)
      expect(matchers_called).to eq(%i[all stdout])
    end
  end

  describe ":all matcher combined with field matchers" do
    it "checks both :all and field-specific matchers when both are present" do
      matchers_called = []

      # Record
      Backspin.run("all_with_fields", mode: :record) do
        Open3.capture3("sh", "-c", "echo 'output'; echo 'error' >&2")
      end

      # Verify with both :all and field matchers
      result = Backspin.run("all_with_fields", mode: :verify,
        matcher: {
          all: lambda { |_recorded, actual|
            matchers_called << :all
            # Could do complex cross-field validation here
            !actual["stdout"].empty? && !actual["stderr"].empty?
          },
          stdout: lambda { |_recorded, actual|
            matchers_called << :stdout
            actual.include?("output")
          },
          stderr: lambda { |_recorded, actual|
            matchers_called << :stderr
            actual.include?("error")
          }
        }) do
        Open3.capture3("sh", "-c", "echo 'output'; echo 'error' >&2")
      end

      expect(result.verified?).to be true
      expect(matchers_called).to eq(%i[all stdout stderr])
    end

    it "always checks exact equality for unspecified fields, even when :all is present" do
      # Record specific output
      Backspin.run("all_checks_equality", mode: :record) do
        Open3.capture3("sh", "-c", "echo 'original'; echo 'original error' >&2")
      end

      # Verify with different stderr but :all passes and no stderr matcher
      result = Backspin.run("all_checks_equality", mode: :verify,
        matcher: {
          all: ->(_r, _a) { true }, # Always passes
          stdout: ->(_r, a) { a.include?("original") } # Only check stdout
          # Note: no stderr matcher, and stderr is different
        }) do
        Open3.capture3("sh", "-c", "echo 'original'; echo 'DIFFERENT ERROR' >&2")
      end

      # This now fails because:
      # 1. :all returned true
      # 2. stdout matcher passed
      # 3. stderr is different and exact equality is ALWAYS checked for unmatched fields
      expect(result.verified?).to be false
      expect(result.error_message).to include("stderr differs")
    end

    it "fails when :all passes but a field matcher fails" do
      # Record
      Backspin.run("all_pass_field_fail", mode: :record) do
        Open3.capture3("echo", "hello")
      end

      # Verify with passing :all but failing field matcher
      result = Backspin.run("all_pass_field_fail", mode: :verify,
        matcher: {
          all: ->(_r, _a) { true }, # Passes
          stdout: lambda { |_r, a|
            a.include?("goodbye")
          } # Fails - looking for wrong text
        }) do
        Open3.capture3("echo", "hello")
      end

      expect(result.verified?).to be false
      expect(result.error_message).to include("stdout custom matcher failed")
    end

    it "can use :all for logging/debugging while field matchers do actual verification" do
      logged_data = []

      # Record
      Backspin.run("all_for_logging", mode: :record) do
        Open3.capture3("date")
      end

      # Use :all for side effects like logging
      result = Backspin.run("all_for_logging", mode: :verify,
        matcher: {
          all: lambda { |_recorded, actual|
            # The actual hash is the CommandResult hash, not the Command hash
            logged_data << {
              stdout_length: actual["stdout"].length,
              stderr_empty: actual["stderr"].empty?,
              status: actual["status"]
            }
            true # Always pass - just for logging
          },
          stdout: ->(_r, a) { a.include?(":") } # Date output contains colons
        }) do
        Open3.capture3("date")
      end

      expect(result.verified?).to be true
      expect(logged_data).not_to be_empty
      expect(logged_data.first[:stdout_length]).to be > 0
      expect(logged_data.first[:status]).to eq(0)
    end
  end

  describe "integration with run!" do
    it "works with run! method" do
      Backspin.run("match_on_run_bang") do
        Open3.capture3("echo 'Process ID: 12345'")
      end

      # Should not raise
      result = Backspin.run!("match_on_run_bang",
        matcher: {stdout: lambda { |recorded, actual|
          recorded.match(/Process ID: \d+/) && actual.match(/Process ID: \d+/)
        }}) do
        Open3.capture3("echo 'Process ID: 67890'")
      end

      expect(result.verified?).to be true
    end

    it "raises when matcher verification fails in run!" do
      Backspin.run("match_on_run_bang_fail") do
        Open3.capture3("echo 'Status: OK'")
      end

      expect do
        Backspin.run!("match_on_run_bang_fail",
          matcher: {stdout: lambda { |recorded, actual|
            recorded.include?("OK") && actual.include?("OK")
          }}) do
          Open3.capture3("echo 'Status: FAIL'")
        end
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end
end
