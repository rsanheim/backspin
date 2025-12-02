require "spec_helper"

RSpec.describe "Backspin.capture" do
  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  context "capture" do
    it "captures stdout and stderr from anything in the block (regardless of how called)" do
      record_name = "capture_all_output"

      result = Backspin.capture(record_name) do
        puts "Hello from puts"
        $stdout.print "Direct stdout write\n"
        warn "Error message"

        system("echo 'From system command'")
        puts `echo 'From backticks'`

        stdout, _, _ = Open3.capture3("echo", "From Open3")
        puts stdout

        "block return value"
      end

      expect(result.output).to eq("block return value")
      expect(result.mode).to eq(:record)

      record_path = Backspin.configuration.backspin_dir.join("capture_all_output.yml")
      expect(record_path).to exist

      yaml_content = YAML.load_file(record_path)
      expect(yaml_content).to be_a(Hash)
      expect(yaml_content["commands"]).to be_an(Array)
      expect(yaml_content["commands"].size).to eq(1)

      command = yaml_content["commands"].first
      expect(command["stdout"]).to include("Hello from puts")
      expect(command["stdout"]).to include("Direct stdout write")
      expect(command["stdout"]).to include("From system command")
      expect(command["stdout"]).to include("From backticks")
      expect(command["stdout"]).to include("From Open3")
      expect(command["stderr"]).to include("Error message")
    end

    it "records to a record file with stdout and stderr, command_type: 'Backspin::Capturer'" do
      record_name = "capture_command_type"

      Backspin.capture(record_name) do
        puts "Test output"
        warn "Test error"
      end

      yaml_content = YAML.load_file(Backspin.configuration.backspin_dir.join("capture_command_type.yml"))
      command = yaml_content["commands"].first

      expect(command["command_type"]).to eq("Backspin::Capturer")
      expect(command["args"]).to eq([])
      expect(command["stdout"]).to eq("Test output\n")
      expect(command["stderr"]).to eq("Test error\n")
      expect(command["status"]).to eq(0)
      expect(command["recorded_at"]).to be_a(String)
    end

    it "acts the same as run: record when called with no matching record file" do
      record_name = "capture_record_mode"

      result = Backspin.capture(record_name) do
        puts "Recording this output"
        42
      end

      expect(result.mode).to eq(:record)
      expect(result.output).to eq(42)
      expect(Backspin.configuration.backspin_dir.join("capture_record_mode.yml")).to exist
    end

    it "acts the same as run: verify when called with a matching record file" do
      record_name = "capture_verify_mode"

      Backspin.capture(record_name) do
        puts "Expected output"
      end

      result = Backspin.capture(record_name) do
        puts "Expected output"
      end

      expect(result.mode).to eq(:verify)
      expect(result.verified?).to be true

      expect do
        Backspin.capture(record_name) do
          puts "Different output"
        end
      end.to raise_error(Backspin::VerificationError) do |error|
        expect(error.message).to include("Backspin verification failed!")
        expect(error.message).to include("Output verification failed")
      end
    end

    it "includes result object on VerificationError" do
      record_name = "capture_error_with_result"

      Backspin.capture(record_name, mode: :record) do
        puts "Recorded output"
      end

      begin
        Backspin.capture(record_name, mode: :verify) do
          puts "Actual output"
        end
      rescue Backspin::VerificationError => error
        expect(error.result).to be_a(Backspin::RecordResult)
        expected_diff = <<~DIFF
          Command 1:
          [stdout]
          -Recorded output
          +Actual output
        DIFF
        expect(error.result.diff).to eq(expected_diff.strip)
        expect(error.recorded_commands.first.stdout).to eq("Recorded output\n")
        expect(error.actual_commands.first.stdout).to eq("Actual output\n")
      end
    end

    it "uses the same recorder and record interface as Backspin.run" do
      record_name = "capture_uses_same_interface"

      result = Backspin.capture(record_name, mode: :record) do
        puts "Test"
      end

      expect(result).to be_a(Backspin::RecordResult)
      expect(result.record).to be_a(Backspin::Record)

      custom_matcher = ->(recorded, actual) { recorded["stdout"] == actual["stdout"] }

      result = Backspin.capture(record_name, mode: :verify, matcher: custom_matcher) do
        puts "Test"
      end

      expect(result.verified?).to be true

      Backspin.capture("capture_with_timestamp", mode: :record) do
        puts "The time is: 2024-01-01 10:00:00"
        puts "Static content"
      end

      timestamp_normalizer = ->(recorded, actual) {
        recorded_normalized = recorded["stdout"].gsub(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/, "[TIMESTAMP]")
        actual_normalized = actual["stdout"].gsub(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/, "[TIMESTAMP]")

        recorded_normalized == actual_normalized &&
          recorded["stderr"] == actual["stderr"] &&
          recorded["status"] == actual["status"]
      }

      result = Backspin.capture("capture_with_timestamp", mode: :verify, matcher: timestamp_normalizer) do
        puts "The time is: 2024-12-25 15:30:45"
        puts "Static content"
      end

      expect(result.verified?).to be true

      expect do
        Backspin.capture("capture_with_timestamp", mode: :verify) do
          puts "The time is: 2024-12-25 15:30:45"
          puts "Static content"
        end
      end.to raise_error(Backspin::VerificationError) do |error|
        expect(error.message).to include("Backspin verification failed!")
        expect(error.message).to include("-The time is: 2024-01-01 10:00:00")
        expect(error.message).to include("+The time is: 2024-12-25 15:30:45")
      end

      filter = ->(data) { data.merge("filtered" => true) }

      Backspin.capture("capture_with_filter", mode: :record, filter: filter) do
        puts "Test"
      end

      yaml_content = YAML.load_file(Backspin.configuration.backspin_dir.join("capture_with_filter.yml"))
      expect(yaml_content["commands"].first["filtered"]).to be true
    end

    it "supports matchers that can transform both recorded and actual content" do
      Backspin.capture("capture_dynamic_content", mode: :record) do
        puts "Process ID: #{Process.pid}"
        puts "Ruby version: #{RUBY_VERSION}"
        warn "Warning with PID: #{Process.pid}"
      end

      content_normalizer = ->(recorded, actual) {
        recorded_stdout = recorded["stdout"]
          .gsub(/Process ID: \d+/, "Process ID: [PID]")
          .gsub(/Ruby version: \d+\.\d+\.\d+/, "Ruby version: [VERSION]")

        actual_stdout = actual["stdout"]
          .gsub(/Process ID: \d+/, "Process ID: [PID]")
          .gsub(/Ruby version: \d+\.\d+\.\d+/, "Ruby version: [VERSION]")

        recorded_stderr = recorded["stderr"]
          .gsub(/PID: \d+/, "PID: [PID]")

        actual_stderr = actual["stderr"]
          .gsub(/PID: \d+/, "PID: [PID]")

        recorded_stdout == actual_stdout && recorded_stderr == actual_stderr
      }

      result = Backspin.capture("capture_dynamic_content", mode: :verify, matcher: content_normalizer) do
        puts "Process ID: #{Process.pid}"
        puts "Ruby version: #{RUBY_VERSION}"
        warn "Warning with PID: #{Process.pid}"
      end

      expect(result.verified?).to be true

      field_matchers = {
        stdout: ->(recorded, actual) {
          recorded.gsub(/\d+/, "[NUM]") == actual.gsub(/\d+/, "[NUM]")
        },
        stderr: ->(recorded, actual) {
          recorded.gsub(/\d+/, "[NUM]") == actual.gsub(/\d+/, "[NUM]")
        }
      }

      result = Backspin.capture("capture_dynamic_content", mode: :verify, matcher: field_matchers) do
        puts "Process ID: #{Process.pid}"
        puts "Ruby version: #{RUBY_VERSION}"
        warn "Warning with PID: #{Process.pid}"
      end

      expect(result.verified?).to be true
    end

    context "with raise_on_verification_failure set to false" do
      it "returns result with verified? false instead of raising" do
        Backspin.capture("capture_no_raise") do
          puts "original output"
        end

        Backspin.configure do |config|
          config.raise_on_verification_failure = false
        end

        result = Backspin.capture("capture_no_raise") do
          puts "different output"
        end

        expect(result).not_to be_verified
        expect(result.verified?).to be false
        expect(result.diff).to include("-original output")
        expect(result.diff).to include("+different output")
        expect(result.error_message).to include("Output verification failed")
      end

      it "allows users to handle verification failures themselves" do
        Backspin.capture("capture_handle_failure") do
          puts "expected stdout"
          warn "expected stderr"
        end

        Backspin.configuration.raise_on_verification_failure = false

        result = Backspin.capture("capture_handle_failure") do
          puts "actual stdout"
          warn "actual stderr"
        end

        expect(result.verified?).to be false
        expect(result.error_message).to be_a(String)
        expect(result.diff).to include("-expected stdout")
        expect(result.diff).to include("+actual stdout")
        expect(result.diff).to include("-expected stderr")
        expect(result.diff).to include("+actual stderr")

        if !result.verified?
          custom_message = "Capture verification failed: #{result.error_message}"
          expect(custom_message).to include("Output verification failed")
        end
      end
    end
  end
end
