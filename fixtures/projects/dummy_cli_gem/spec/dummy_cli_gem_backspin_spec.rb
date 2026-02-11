# frozen_string_literal: true

require "spec_helper"

RSpec.describe "DummyCliGem Backspin full-stack fixture" do
  let(:project_root) { Pathname(__dir__).join("..").expand_path }
  let(:record_dir) { project_root.join("spec", "fixtures", "backspin") }

  before do
    Backspin.configure do |config|
      config.backspin_dir = record_dir
      config.logger = nil
    end
  end

  after do
    Backspin.reset_configuration!
  end

  it "verifies echo command output from committed YAML" do
    expect(record_dir.join("dummy_echo.yml")).to exist

    result = Backspin.run(
      ["ruby", "exe/dummy_cli_gem", "echo", "hello from dummy gem"],
      name: "dummy_echo"
    )

    expect(result).to be_verified
    expect(result.actual.stdout).to eq("hello from dummy gem\n")
    expect(result.actual.stderr).to eq("")
    expect(result.actual.status).to eq(0)
  end

  it "verifies list command output from committed YAML" do
    expect(record_dir.join("dummy_ls.yml")).to exist

    result = Backspin.run(
      ["ruby", "exe/dummy_cli_gem", "list", "spec/fixtures/listing_target"],
      name: "dummy_ls"
    )

    expect(result).to be_verified
    expect(result.actual.stdout).to eq("alpha.txt\n")
    expect(result.actual.stderr).to eq("")
    expect(result.actual.status).to eq(0)
  end

  it "uses current Backspin record format for fixture YAML files" do
    %w[dummy_echo dummy_ls].each do |record_name|
      record_path = record_dir.join("#{record_name}.yml")
      expect(record_path).to exist

      record_data = YAML.load_file(record_path)
      expect(record_data["format_version"]).to eq("4.1")
      expect(record_data["snapshot"]["command_type"]).to eq("Open3::Capture3")
    end
  end
end
