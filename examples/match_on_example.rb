#!/usr/bin/env ruby
require "bundler/inline"
require "open3"

gemfile do
  source "https://rubygems.org"
  gem "backspin", path: ".."
end

# Example 1: Single field matcher
puts "Example 1: Matching timestamps with custom matcher"
puts "-" * 50

# First run: Record the output
result = Backspin.run("timestamp_example") do
  Open3.capture3("date '+%Y-%m-%d %H:%M:%S'")
end
puts "Recorded: #{result.stdout.chomp}"

# Sleep to ensure different timestamp
sleep 1

# Second run: Verify with custom matcher
result = Backspin.run("timestamp_example",
  match_on: [:stdout, ->(recorded, actual) {
    # Both should have the same date format
    recorded.match?(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/) &&
    actual.match?(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/)
  }]) do
  Open3.capture3("date '+%Y-%m-%d %H:%M:%S'")
end

puts "Current:  #{result.stdout.chomp}"
puts "Verified: #{result.verified?}"
puts

# Example 2: Multiple field matchers
puts "Example 2: Matching multiple fields with different patterns"
puts "-" * 50

# Record a command with dynamic content
Backspin.run("multi_field_example") do
  script = <<~BASH
    echo "PID: $$"
    echo "Error: Timeout at $(date '+%H:%M:%S')" >&2
    exit 1
  BASH
  Open3.capture3("bash", "-c", script)
end

# Verify with different PID and timestamp
result = Backspin.run("multi_field_example",
  match_on: [
    [:stdout, ->(recorded, actual) {
      # Both should have PID format
      recorded.match?(/PID: \d+/) && actual.match?(/PID: \d+/)
    }],
    [:stderr, ->(recorded, actual) {
      # Both should have timeout error, ignore timestamp
      recorded.match?(/Error: Timeout at/) && actual.match?(/Error: Timeout at/)
    }]
  ]) do
  script = <<~BASH
    echo "PID: $$"
    echo "Error: Timeout at $(date '+%H:%M:%S')" >&2
    exit 1
  BASH
  Open3.capture3("bash", "-c", script)
end

puts "Stdout:   #{result.stdout.chomp}"
puts "Stderr:   #{result.stderr.chomp}"
puts "Status:   #{result.status}"
puts "Verified: #{result.verified?}"
puts

# Example 3: Mixed matching - some fields exact, some custom
puts "Example 3: Mixed field matching"
puts "-" * 50

# Record with specific values
Backspin.run("mixed_matching") do
  script = <<~BASH
    echo "Version: 1.2.3"
    echo "Build: $(date +%s)"
    echo "Status: OK"
  BASH
  Open3.capture3("bash", "-c", script)
end

# Verify - stdout uses custom matcher, stderr must match exactly
result = Backspin.run("mixed_matching",
  match_on: [:stdout, ->(recorded, actual) {
    # Version and Status must match, Build can differ
    recorded_lines = recorded.lines
    actual_lines = actual.lines

    recorded_lines[0] == actual_lines[0] &&  # Version line must match
    recorded_lines[1].start_with?("Build:") && actual_lines[1].start_with?("Build:") &&  # Build line format
    recorded_lines[2] == actual_lines[2]  # Status line must match
  }]) do
  script = <<~BASH
    echo "Version: 1.2.3"
    echo "Build: $(date +%s)"
    echo "Status: OK"
  BASH
  Open3.capture3("bash", "-c", script)
end

puts "Output:\n#{result.stdout}"
puts "Verified: #{result.verified?}"

# Cleanup
FileUtils.rm_rf("fixtures/backspin")
