require "spec_helper"

RSpec.describe Backspin::Recorder do
  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  let(:record) { Backspin::Record.new(Backspin.configuration.backspin_dir.join("recorder_verification_test.yml")) }

  describe "#perform_verification" do
    context "when verifying recorded commands" do
      before do
        recorded_command = Backspin::Command.new(
          method_class: Open3::Capture3,
          args: ["echo", "hello"],
          stdout: "hello\n",
          stderr: "",
          status: 0,
          recorded_at: Time.now.iso8601
        )
        record.add_command(recorded_command)
        record.save
      end

      it "verifies matching output successfully" do
        recorder = Backspin::Recorder.new(mode: :verify, record: record, options: {})

        result = recorder.perform_verification do
          Open3.capture3("echo", "hello")
        end

        expect(result).to be_a(Backspin::RecordResult)
        expect(result.verified?).to be true
        expect(result.mode).to eq(:verify)
        expect(result.command_diffs.size).to eq(1)
        expect(result.command_diffs.first).to be_verified
      end

      it "fails verification when output doesn't match" do
        recorder = Backspin::Recorder.new(mode: :verify, record: record, options: {})

        result = recorder.perform_verification do
          Open3.capture3("echo", "goodbye")
        end

        expect(result.verified?).to be false
        expect(result.command_diffs.first).not_to be_verified
        expect(result.command_diffs.first.diff).to include("-hello", "+goodbye")
      end

      it "raises error when executing more commands than recorded" do
        recorder = Backspin::Recorder.new(mode: :verify, record: record, options: {})

        expect {
          recorder.perform_verification do
            Open3.capture3("echo", "hello")
            Open3.capture3("echo", "extra")
          end
        }.to raise_error(Backspin::RecordNotFoundError, /No more recorded commands/)
      end

      it "raises error when executing fewer commands than recorded" do
        # Add a second command to the record
        record.add_command(Backspin::Command.new(
          method_class: Open3::Capture3,
          args: ["echo", "world"],
          stdout: "world\n",
          stderr: "",
          status: 0,
          recorded_at: Time.now.iso8601
        ))
        record.save

        recorder = Backspin::Recorder.new(mode: :verify, record: record, options: {})

        expect {
          recorder.perform_verification do
            Open3.capture3("echo", "hello")
          end
        }.to raise_error(Backspin::RecordNotFoundError, /Expected 2 commands but only 1 were executed/)
      end
    end

    context "with custom matchers" do
      before do
        recorded_command = Backspin::Command.new(
          method_class: Open3::Capture3,
          args: ["date"],
          stdout: "2025-01-01 12:00:00\n",
          stderr: "",
          status: 0,
          recorded_at: Time.now.iso8601
        )
        record.add_command(recorded_command)
        record.save
      end

      it "uses custom matcher for verification" do
        custom_matcher = ->(recorded, actual) {
          # Check that actual stdout contains a year starting with 20
          actual["stdout"].include?("20")
        }
        recorder = Backspin::Recorder.new(
          mode: :verify,
          record: record,
          options: {matcher: custom_matcher}
        )

        result = recorder.perform_verification do
          Open3.capture3("date")
        end

        expect(result.verified?).to be true
      end

      it "uses match_on for field-specific matching" do
        recorder = Backspin::Recorder.new(
          mode: :verify,
          record: record,
          options: {
            match_on: [:stdout, ->(recorded, actual) { actual.include?("20") }]
          }
        )

        result = recorder.perform_verification do
          Open3.capture3("date")
        end

        expect(result.verified?).to be true
      end
    end

    context "with system commands" do
      before do
        recorded_command = Backspin::Command.new(
          method_class: ::Kernel::System,
          args: ["true"],
          stdout: "",
          stderr: "",
          status: 0,
          recorded_at: Time.now.iso8601
        )
        record.add_command(recorded_command)
        record.save
      end

      it "verifies system command success" do
        recorder = Backspin::Recorder.new(mode: :verify, record: record, options: {})

        result = recorder.perform_verification do
          system("true")
        end

        expect(result.verified?).to be true
        expect(result.command_diffs.first.actual_result.status).to eq(0)
      end

      it "verifies system command failure" do
        # Update record with failing command
        record.clear
        record.add_command(Backspin::Command.new(
          method_class: ::Kernel::System,
          args: ["false"],
          stdout: "",
          stderr: "",
          status: 1,
          recorded_at: Time.now.iso8601
        ))
        record.save

        recorder = Backspin::Recorder.new(mode: :verify, record: record, options: {})

        result = recorder.perform_verification do
          system("false")
        end

        expect(result.verified?).to be true
        expect(result.command_diffs.first.actual_result.status).to eq(1)
      end
    end

    context "with mixed command types" do
      before do
        record.add_command(Backspin::Command.new(
          method_class: Open3::Capture3,
          args: ["echo", "first"],
          stdout: "first\n",
          stderr: "",
          status: 0,
          recorded_at: Time.now.iso8601
        ))
        record.add_command(Backspin::Command.new(
          method_class: ::Kernel::System,
          args: ["true"],
          stdout: "",
          stderr: "",
          status: 0,
          recorded_at: Time.now.iso8601
        ))
        record.add_command(Backspin::Command.new(
          method_class: Open3::Capture3,
          args: ["echo", "last"],
          stdout: "last\n",
          stderr: "",
          status: 0,
          recorded_at: Time.now.iso8601
        ))
        record.save
      end

      it "verifies mixed command types in correct order" do
        recorder = Backspin::Recorder.new(mode: :verify, record: record, options: {})

        result = recorder.perform_verification do
          Open3.capture3("echo", "first")
          system("true")
          Open3.capture3("echo", "last")
        end

        expect(result.verified?).to be true
        expect(result.command_diffs.size).to eq(3)
        expect(result.command_diffs.all?(&:verified?)).to be true
      end

      it "raises error when command types don't match" do
        recorder = Backspin::Recorder.new(mode: :verify, record: record, options: {})

        expect {
          recorder.perform_verification do
            system("echo", "first") # Wrong type - should be capture3
          end
        }.to raise_error(Backspin::RecordNotFoundError, /Expected.*Capture3.*but got system/)
      end
    end

    context "error handling" do
      it "raises error when record doesn't exist" do
        non_existent_record = Backspin::Record.new("non_existent.yml")
        recorder = Backspin::Recorder.new(mode: :verify, record: non_existent_record, options: {})

        expect {
          recorder.perform_verification {}
        }.to raise_error(Backspin::RecordNotFoundError, /Record not found/)
      end

      it "raises error when record has no commands" do
        record.save # Save empty record
        recorder = Backspin::Recorder.new(mode: :verify, record: record, options: {})

        expect {
          recorder.perform_verification {}
        }.to raise_error(Backspin::RecordNotFoundError, /No commands found in record/)
      end
    end
  end
end
