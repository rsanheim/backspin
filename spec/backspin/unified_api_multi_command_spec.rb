# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Backspin.run with multiple commands" do

  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  describe "recording multiple commands" do
    it "records all commands executed in the block" do
      result = Backspin.run("multi_commands") do
        stdout1, = Open3.capture3("echo first")
        stdout2, = Open3.capture3("echo second")
        system("echo third")
        stdout4, = Open3.capture3("echo fourth")
        "#{stdout1.strip} #{stdout2.strip} #{stdout4.strip}"
      end

      expect(result).to be_recorded
      expect(result.commands.size).to eq(4)
      expect(result.multiple_commands?).to be true

      # Check individual commands
      expect(result.commands[0].stdout).to eq("first\n")
      expect(result.commands[1].stdout).to eq("second\n")
      expect(result.commands[2].stdout).to eq("") # system doesn't capture stdout
      expect(result.commands[3].stdout).to eq("fourth\n")

      # Check convenience accessors for first command
      expect(result.stdout).to eq("first\n")
      expect(result.status).to eq(0)

      # Check multiple command accessors
      expect(result.all_stdout).to eq(["first\n", "second\n", "", "fourth\n"])
      expect(result.all_status).to eq([0, 0, 0, 0])
    end
  end

  describe "verifying multiple commands" do
    it "verifies all commands match" do
      # First record
      Backspin.run("multi_verify_match") do
        Open3.capture3("echo one")
        Open3.capture3("echo two")
        system("echo three")
      end

      # Then verify
      result = Backspin.run("multi_verify_match") do
        Open3.capture3("echo one")
        Open3.capture3("echo two")
        system("echo three")
      end

      expect(result).to be_verified
      expect(result.commands.size).to eq(3)
      expect(result).to be_success
    end

    it "detects when a command differs" do
      # First record
      Backspin.run("multi_verify_diff") do
        Open3.capture3("echo one")
        Open3.capture3("echo two")
        Open3.capture3("echo three")
      end

      # Then verify with different second command
      result = Backspin.run("multi_verify_diff") do
        Open3.capture3("echo one")
        Open3.capture3("echo TWO CHANGED")
        Open3.capture3("echo three")
      end

      expect(result).not_to be_verified
      expect(result.diff).to include("Command 2:")
      expect(result.diff).to include("-two")
      expect(result.diff).to include("+TWO CHANGED")
    end

    it "fails if fewer commands are executed than recorded" do
      # Record 3 commands
      Backspin.run("multi_too_few") do
        Open3.capture3("echo one")
        Open3.capture3("echo two")
        Open3.capture3("echo three")
      end

      # Try to verify with only 2 commands
      expect do
        Backspin.run("multi_too_few") do
          Open3.capture3("echo one")
          Open3.capture3("echo two")
          # Missing third command
        end
      end.to raise_error(Backspin::RecordNotFoundError, /Expected 3 commands but only 2 were executed/)
    end

    it "fails if more commands are executed than recorded" do
      # Record 2 commands
      Backspin.run("multi_too_many") do
        Open3.capture3("echo one")
        Open3.capture3("echo two")
      end

      # Try to verify with 3 commands
      expect do
        Backspin.run("multi_too_many") do
          Open3.capture3("echo one")
          Open3.capture3("echo two")
          Open3.capture3("echo three")
        end
      end.to raise_error(Backspin::RecordNotFoundError, /No more recorded commands/)
    end
  end

  describe "playback mode with multiple commands" do
    it "plays back all recorded commands" do
      # First record
      Backspin.run("multi_playback", mode: :record) do
        stdout1, = Open3.capture3("sleep 0.1 && echo slow1")
        stdout2, = Open3.capture3("sleep 0.1 && echo slow2")
        system("sleep 0.1 && echo slow3")
        "#{stdout1.strip} #{stdout2.strip}"
      end

      # Playback should be fast
      start_time = Time.now
      result = Backspin.run("multi_playback", mode: :playback) do
        stdout1, = Open3.capture3("sleep 10 && echo different")
        stdout2, = Open3.capture3("sleep 10 && echo different")
        system("sleep 10 && echo different")
        "#{stdout1.strip} #{stdout2.strip}"
      end
      elapsed = Time.now - start_time

      expect(elapsed).to be < 0.5 # Should be instant, not 30+ seconds
      expect(result).to be_playback
      expect(result.commands.size).to eq(3)
      expect(result.all_stdout).to eq(["slow1\n", "slow2\n", ""])
    end
  end

  describe "mixed command types" do
    it "handles mixing capture3 and system calls" do
      result = Backspin.run("mixed_types") do
        stdout1, = Open3.capture3("echo capture3_1")
        system("echo system_1")
        stdout2, stderr2, = Open3.capture3('sh -c "echo capture3_2 && echo error >&2"')
        system("false") # exit 1
        "#{stdout1.strip} #{stdout2.strip} #{stderr2.strip}"
      end

      expect(result.commands.size).to eq(4)

      # Check command types
      expect(result.commands[0].method_class).to eq(Open3::Capture3)
      expect(result.commands[1].method_class).to eq(::Kernel::System)
      expect(result.commands[2].method_class).to eq(Open3::Capture3)
      expect(result.commands[3].method_class).to eq(::Kernel::System)

      # Check outputs
      expect(result.commands[0].stdout).to eq("capture3_1\n")
      expect(result.commands[1].stdout).to eq("") # system doesn't capture stdout
      expect(result.commands[2].stdout).to eq("capture3_2\n")
      expect(result.commands[2].stderr).to eq("error\n")

      # Check exit statuses
      expect(result.all_status).to eq([0, 0, 0, 1])
      expect(result).to be_failure # Because last command failed
    end
  end

  describe "run! with multiple commands" do
    it "provides detailed error for multi-command failures" do
      # Record
      Backspin.run("multi_bang") do
        Open3.capture3("echo one")
        Open3.capture3("echo two")
        Open3.capture3("echo three")
      end

      # Verify with differences
      expect do
        Backspin.run!("multi_bang") do
          Open3.capture3("echo one")
          Open3.capture3("echo TWO")
          Open3.capture3("echo THREE")
        end
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError) do |error|
        expect(error.message).to include("Output verification failed for 2 command(s)")
        expect(error.message).to include("Command 2: ✗ Command failed: stdout differs")
        expect(error.message).to include("-two")
        expect(error.message).to include("+TWO")
        expect(error.message).to include("Command 3: ✗ Command failed: stdout differs")
        expect(error.message).to include("-three")
        expect(error.message).to include("+THREE")
      end
    end
  end
end
