# frozen_string_literal: true

require "spec_helper"

RSpec.describe Backspin::Configuration do
  before do
    Backspin.reset_configuration!
  end

  it "provides defaults for recording, verification, and logging" do
    configuration = Backspin.configuration

    expect(configuration.backspin_dir).to eq(Pathname(Dir.pwd).join("fixtures", "backspin"))
    expect(configuration.scrub_credentials).to be true
    expect(configuration.raise_on_verification_failure).to be true
    expect(configuration.logger.level).to eq(Logger::WARN)
  end

  it "preserves configuration across configure calls" do
    configuration = Backspin.configuration
    Backspin.configure do |config|
      expect(config).to equal(configuration)
      config.backspin_dir = "spec/fixtures/cli_records"
      config.logger = nil
    end

    Backspin.configure do |config|
      expect(config).to equal(configuration)
      expect(config.backspin_dir).to eq(Pathname("spec/fixtures/cli_records"))
      expect(config.logger).to be_nil
    end
  end

  it "accepts absolute String paths" do
    configuration = described_class.new
    configuration.backspin_dir = File.join(Dir.tmpdir, "backspin-records")

    expect(configuration.backspin_dir).to eq(Pathname(Dir.tmpdir).join("backspin-records"))
  end

  it "continues accepting Pathname paths" do
    configuration = described_class.new
    configuration.backspin_dir = Pathname("custom/records")

    expect(configuration.backspin_dir).to eq(Pathname("custom/records"))
  end

  it "does not let later String mutation change the configured directory" do
    directory = +"custom/records"
    configuration = described_class.new
    configuration.backspin_dir = directory
    directory.replace("other/records")

    expect(configuration.backspin_dir).to eq(Pathname("custom/records"))
  end

  it "rejects invalid paths without discarding the configured directory" do
    configuration = described_class.new
    configuration.backspin_dir = "custom/records"

    [nil, 123].each do |invalid_path|
      expect { configuration.backspin_dir = invalid_path }.to raise_error(TypeError)
      expect(configuration.backspin_dir).to eq(Pathname("custom/records"))
    end
  end

  it "resets configured values and credential patterns with a fresh configuration" do
    original = Backspin.configuration
    default_patterns = original.credential_patterns.dup
    original.backspin_dir = "custom/records"
    original.scrub_credentials = false
    original.raise_on_verification_failure = false
    original.logger = nil
    original.clear_credential_patterns
    original.add_credential_pattern(/custom-secret/)

    Backspin.reset_configuration!
    fresh = Backspin.configuration

    expect(fresh).not_to equal(original)
    expect(fresh.backspin_dir).to eq(Pathname(Dir.pwd).join("fixtures", "backspin"))
    expect(fresh.scrub_credentials).to be true
    expect(fresh.raise_on_verification_failure).to be true
    expect(fresh.logger).to be_a(Logger)
    expect(fresh.credential_patterns).to eq(default_patterns)
  end

  it "isolates mutable credential patterns between configurations" do
    first = described_class.new
    second = described_class.new
    default_patterns = second.credential_patterns.dup
    first.add_credential_pattern(/custom-secret/)

    expect(second.credential_patterns).to eq(default_patterns)

    first.clear_credential_patterns
    expect(first.credential_patterns).to be_empty
    expect(second.credential_patterns).to eq(default_patterns)

    first.reset_credential_patterns
    expect(first.credential_patterns).to eq(default_patterns)
  end

  it "records and verifies commands in an absolute String directory" do
    Dir.mktmpdir("backspin-config") do |directory|
      Backspin.configure { |config| config.backspin_dir = File.join(directory, "nested", "records") }

      recorded = Backspin.run(["echo", "hello"], name: "command")
      verified = Backspin.run(["echo", "hello"], name: "command")

      expect(recorded).to be_recorded
      expect(verified).to be_verified
      expect(Pathname(directory).join("nested", "records", "command.yml")).to be_file
    end
  end

  it "records and verifies captures in a relative String directory" do
    Dir.mktmpdir("backspin-config") do |directory|
      Dir.chdir(directory) do
        Backspin.configure { |config| config.backspin_dir = "nested/records" }

        recorded = Backspin.capture("capture") { puts "hello" }
        verified = Backspin.capture("capture") { puts "hello" }

        expect(recorded).to be_recorded
        expect(verified).to be_verified
        expect(Pathname(directory).join("nested", "records", "capture.yml")).to be_file
      end
    end
  end
end
