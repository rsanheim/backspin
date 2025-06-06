require "spec_helper"

RSpec.describe Backspin::Record do
  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  let(:record_path) { Backspin.configuration.backspin_dir.join("test_record.yaml") }
  let(:record) { described_class.new(record_path) }

  describe "#initialize" do
    it "creates a new record with the given path" do
      expect(record.path).to eq(record_path)
    end

    it "initializes with empty commands if file doesn't exist" do
      expect(record.commands).to eq([])
    end

    it "loads existing commands if file exists" do
      # Create a record file with new format
      FileUtils.mkdir_p(File.dirname(record_path))
      File.write(record_path, {
        "format_version" => "2.0",
        "first_recorded_at" => "2024-01-01T00:00:00Z",
        "commands" => [
          {"command_type" => "Open3::Capture3", "args" => ["echo", "hello"], "stdout" => "hello\n", "stderr" => "", "status" => 0, "recorded_at" => "2024-01-01T00:00:00Z"}
        ]
      }.to_yaml)

      loaded_record = described_class.new(record_path)
      expect(loaded_record.commands.size).to eq(1)
      expect(loaded_record.commands.first).to be_a(Backspin::Command)
      expect(loaded_record.commands.first.stdout).to eq("hello\n")
      expect(loaded_record.first_recorded_at).to eq("2024-01-01T00:00:00Z")
    end

    it "raises error if file exists but has invalid format" do
      FileUtils.mkdir_p(File.dirname(record_path))
      File.write(record_path, "not an array")

      expect {
        described_class.new(record_path)
      }.to raise_error(Backspin::RecordFormatError, /Invalid record format/)
    end
  end

  describe "#add_command" do
    it "adds a command to the record" do
      command = Backspin::Command.new(
        method_class: Open3::Capture3,
        args: ["echo", "hello"],
        stdout: "hello\n",
        stderr: "",
        status: 0,
        recorded_at: Time.now.iso8601
      )

      record.add_command(command)
      expect(record.commands).to include(command)
    end

    it "returns self for chaining" do
      command = Backspin::Command.new(
        method_class: Open3::Capture3,
        args: ["echo", "test"],
        stdout: "test\n",
        stderr: "",
        status: 0,
        recorded_at: Time.now.iso8601
      )

      expect(record.add_command(command)).to eq(record)
    end
  end

  describe "#save" do
    it "creates the directory if it doesn't exist" do
      record.add_command(create_test_command("test"))
      record.save

      expect(File.directory?(File.dirname(record_path))).to be true
    end

    it "writes commands to YAML file" do
      record.add_command(create_test_command("first"))
      record.add_command(create_test_command("second"))
      record.save

      expect(File.exist?(record_path)).to be true

      saved_data = YAML.load_file(record_path)
      expect(saved_data).to be_a(Hash)
      expect(saved_data["format_version"]).to eq("2.0")
      expect(saved_data["first_recorded_at"]).not_to be_nil
      expect(saved_data["commands"]).to be_an(Array)
      expect(saved_data["commands"].size).to eq(2)
      expect(saved_data["commands"][0]["stdout"]).to eq("first\n")
      expect(saved_data["commands"][1]["stdout"]).to eq("second\n")
    end

    it "overwrites existing file" do
      # Create initial file with new format
      FileUtils.mkdir_p(File.dirname(record_path))
      File.write(record_path, {
        "format_version" => "2.0",
        "first_recorded_at" => Time.now.iso8601,
        "commands" => [{"command_type" => "Open3::Capture3", "args" => ["echo", "old"], "stdout" => "old\n", "stderr" => "", "status" => 0, "recorded_at" => Time.now.iso8601}]
      }.to_yaml)

      # Create a new record instance that won't load the existing data
      new_record = described_class.new(record_path)
      expect(new_record.size).to eq(1)  # It loaded the existing data

      # Clear and add new data
      new_record.clear
      new_record.add_command(create_test_command("new"))
      new_record.save

      saved_data = YAML.load_file(record_path)
      expect(saved_data["commands"].size).to eq(1)
      expect(saved_data["commands"][0]["stdout"]).to eq("new\n")
    end

    it "applies credential scrubbing when saving" do
      command = Backspin::Command.new(
        method_class: Open3::Capture3,
        args: ["aws"],
        stdout: "AKIA1234567890123456\n",
        stderr: "",
        status: 0,
        recorded_at: Time.now.iso8601
      )

      record.add_command(command)
      record.save

      saved_data = YAML.load_file(record_path)
      expect(saved_data["commands"][0]["stdout"]).to eq("********************\n")
    end

    it "saves command type and args in new format" do
      command = Backspin::Command.new(
        method_class: Open3::Capture3,
        args: ["echo", "hello world"],
        stdout: "hello world\n",
        stderr: "",
        status: 0,
        recorded_at: Time.now.iso8601
      )

      record.add_command(command)
      record.save

      saved_data = YAML.load_file(record_path)
      expect(saved_data["format_version"]).to eq("2.0")
      expect(saved_data["first_recorded_at"]).to eq(command.recorded_at)
      expect(saved_data["commands"][0]["command_type"]).to eq("Open3::Capture3")
      expect(saved_data["commands"][0]["args"]).to eq(["echo", "hello world"])
    end
  end

  describe "#reload" do
    it "reloads commands from disk" do
      # Start with one command
      record.add_command(create_test_command("first"))
      record.save

      # Modify the file externally with new format
      new_data = {
        "format_version" => "2.0",
        "first_recorded_at" => Time.now.iso8601,
        "commands" => [
          {"command_type" => "Open3::Capture3", "args" => ["echo", "external"], "stdout" => "external\n", "stderr" => "", "status" => 0, "recorded_at" => Time.now.iso8601}
        ]
      }
      File.write(record_path, new_data.to_yaml)

      # Reload
      record.reload

      expect(record.commands.size).to eq(1)
      expect(record.commands.first.stdout).to eq("external\n")
    end

    it "clears commands if file doesn't exist" do
      record.add_command(create_test_command("test")).save
      expect(record_path).to exist
      expect(record.commands.size).to eq(1)

      record_path.delete

      expect(record_path).not_to exist

      record.reload

      expect(record.commands).to eq([])
    end
  end

  describe "#exists?" do
    it "returns false when file doesn't exist" do
      expect(record.exists?).to be false
    end

    it "returns true when file exists" do
      record.save
      expect(record.exists?).to be true
    end
  end

  describe "#empty?" do
    it "returns true when no commands are recorded" do
      expect(record.empty?).to be true
    end

    it "returns false when commands are present" do
      record.add_command(create_test_command("test"))
      expect(record.empty?).to be false
    end
  end

  describe "#size" do
    it "returns the number of recorded commands" do
      expect(record.size).to eq(0)

      record.add_command(create_test_command("first"))
      expect(record.size).to eq(1)

      record.add_command(create_test_command("second"))
      expect(record.size).to eq(2)
    end
  end

  describe "#next_command" do
    it "returns commands in sequence" do
      record.add_command(create_test_command("first"))
      record.add_command(create_test_command("second"))

      expect(record.next_command.stdout).to eq("first\n")
      expect(record.next_command.stdout).to eq("second\n")
    end

    it "raises error when no more commands are available" do
      record.add_command(create_test_command("only"))

      record.next_command # Use the only command

      expect {
        record.next_command
      }.to raise_error(Backspin::NoMoreRecordingsError, /No more recordings available/)
    end

    it "resets playback position when reloaded" do
      record.add_command(create_test_command("test"))
      record.save  # Save to disk first
      record.next_command # Use the command

      record.reload # This should reset position
      expect(record.next_command.stdout).to eq("test\n")
    end
  end

  describe "#clear" do
    it "removes all commands" do
      record.add_command(create_test_command("first"))
      record.add_command(create_test_command("second"))

      record.clear

      expect(record.empty?).to be true
      expect(record.size).to eq(0)
    end
  end

  describe ".load_or_create" do
    it "loads existing record" do
      # Create a record file with new format
      FileUtils.mkdir_p(File.dirname(record_path))
      File.write(record_path, {
        "format_version" => "2.0",
        "first_recorded_at" => "2024-01-01T00:00:00Z",
        "commands" => [
          {"command_type" => "Open3::Capture3", "args" => ["echo", "existing"], "stdout" => "existing\n", "stderr" => "", "status" => 0, "recorded_at" => "2024-01-01T00:00:00Z"}
        ]
      }.to_yaml)

      record = described_class.load_or_create(record_path)

      expect(record.size).to eq(1)
      expect(record.commands.first.stdout).to eq("existing\n")
    end

    it "creates new record if file doesn't exist" do
      record = described_class.load_or_create(record_path)

      expect(record.empty?).to be true
      expect(record.path).to eq(record_path)
    end
  end

  private

  def create_test_command(output)
    Backspin::Command.new(
      method_class: Open3::Capture3,
      args: ["echo", output],
      stdout: "#{output}\n",
      stderr: "",
      status: 0,
      recorded_at: Time.now.iso8601
    )
  end
end
