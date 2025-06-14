# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Backspin system() support" do
  around do |example|
    Timecop.freeze(static_time) do
      example.run
    end
  end

  describe "recording system calls" do
    it "records a simple system call" do
      result = Backspin.run("system_echo") do
        system("echo hello")
      end

      expect(result.commands.size).to eq(1)
      command = result.commands.first
      expect(command.args).to eq(%w[echo hello])
      # System calls don't capture stdout/stderr - they go directly to the terminal
      expect(command.stdout).to eq("")
      expect(command.stderr).to eq("")
      expect(command.status).to eq(0)
    end

    it "records system call exit status and preserves return value" do
      return_values = []
      result = Backspin.run("system_false") do
        return_values << system("true")   # Should return true
        return_values << system("false")  # Should return false
      end

      expect(return_values).to eq([true, false])
      expect(result.commands[0].status).to eq(0)
      expect(result.commands[1].status).to eq(1)
    end

    it "records multiple system calls" do
      result = Backspin.run("multi_system", mode: :record) do
        system("echo first")
        system("echo second")
      end

      expect(result.commands.size).to eq(2)
      expect(result.commands[0].args).to eq(%w[echo first])
      expect(result.commands[0].stdout).to eq("")
      expect(result.commands[1].args).to eq(%w[echo second])
      expect(result.commands[1].stdout).to eq("")
    end
  end

  describe "verifying system calls" do
    it "verifies matching system calls" do
      # Record
      Backspin.run("verify_system") do
        system("echo hello")
      end

      # Verify - should pass because command and exit status match
      result = Backspin.run("verify_system") do
        system("echo hello")
      end

      expect(result.verified?).to be true
    end

    it "detects non-matching system exit status" do
      # Record a successful command
      Backspin.run("verify_system_diff") do
        system("true") # exit status 0
      end

      # Verify with a failing command - should fail
      result = Backspin.run("verify_system_diff") do
        system("false") # exit status 1
      end

      expect(result.verified?).to be false
    end
  end

  describe "playback mode" do
    it "plays back system calls without executing" do
      # Record
      Backspin.run("playback_system") do
        system("echo recorded")
      end

      # Playback
      result = Backspin.run("playback_system", mode: :playback) do
        # This should not actually execute
        system("echo not executed")
      end

      expect(result.verified?).to be true
      expect(result.playback?).to be true
    end
  end

  describe "mixing system and capture3" do
    it "records both system and capture3 calls" do
      result = Backspin.run("mixed_calls", mode: :record) do
        system("echo from system")
        Open3.capture3("echo from capture3")
        "hello"
      end

      expect(result.commands.size).to eq(2)
      expect(result.output).to eq("hello")
      expect(result.commands[0].method_class.name).to eq("Kernel::System")
      expect(result.commands[0].stdout).to eq("") # System calls don't capture stdout
      expect(result.commands[1].method_class.name).to eq("Open3::Capture3")
      expect(result.commands[1].stdout).to eq("from capture3\n") # But capture3 does
    end
  end
end
