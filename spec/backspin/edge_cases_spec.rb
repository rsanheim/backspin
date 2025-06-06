require "spec_helper"

RSpec.describe "Backspin edge cases" do
  it "raises error for empty record name" do
    expect {
      Backspin.run("", mode: :record) do
        Open3.capture3("echo empty")
      end
    }.to raise_error(ArgumentError, "record_name is required")
  end

  it "uses provided record name" do
    result = Backspin.run("custom_name") do
      Open3.capture3("echo custom")
    end

    expect(result.record_path.to_s).to end_with("custom_name.yaml")
  end

  it "sanitizes record names with special characters" do
    result = Backspin.run("test/with/slashes") do
      Open3.capture3("echo slashes")
    end

    expect(result.record_path.to_s).to end_with("test/with/slashes.yaml")
  end
end
