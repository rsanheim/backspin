require "spec_helper"

RSpec.describe "Backspin use_record integration" do
  it "works seamlessly with rux testing" do
    # First run - records
    result1 = Backspin.run("rux_version") do
      stdout, _, _ = Open3.capture3("echo 'rux v0.6.0'")
      stdout
    end

    expect(result1.output).to eq("rux v0.6.0\n")

    # Second run - verifies with same command
    result2 = Backspin.run("rux_version") do
      stdout, _, _ = Open3.capture3("echo 'rux v0.6.0'")
      stdout
    end

    expect(result2).to be_verified  # Second run verifies
    expect(result2.output).to eq("rux v0.6.0\n") # Block returns same value
  end

  it "preserves the exact behavior of Open3.capture3" do
    # Test that our API is transparent
    original_result = Open3.capture3("echo test")

    result = Backspin.run("transparent_test") do
      Open3.capture3("echo test")
    end

    expect(result.output[0]).to eq(original_result[0]) # stdout
    expect(result.output[1]).to eq(original_result[1]) # stderr
    expect(result.output[2]).to eq(original_result[2].exitstatus) # status
  end

  it "can be used in before/after hooks" do
    recordings = []

    3.times do |i|
      result = Backspin.run("hook_test") do
        Open3.capture3("echo iteration")
      end
      recordings << result.output[0]
    end

    # All iterations should get the same recorded value
    expect(recordings).to eq(["iteration\n", "iteration\n", "iteration\n"])
  end
end
