#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/inline"

# Example usage of Backspin matchers

gemfile do
  source "https://rubygems.org"
  gem "backspin", path: ".."
end

# Example 1: Single field matcher
puts "Example 1: Matching timestamps with custom matcher"
puts "-" * 50

result = Backspin.run(["date", "+%Y-%m-%d %H:%M:%S"], name: "timestamp_example")
puts "Recorded: #{result.stdout.chomp}"

sleep 1

result = Backspin.run(["date", "+%Y-%m-%d %H:%M:%S"], name: "timestamp_example",
  matcher: {
    stdout: ->(recorded, actual) {
      recorded.match?(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/) &&
        actual.match?(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/)
    }
  })

puts "Current:  #{result.stdout.chomp}"
puts "Verified: #{result.verified?}"
puts

# Example 2: Multiple field matchers
puts "Example 2: Matching multiple fields with different patterns"
puts "-" * 50

script = <<~SH
  echo "PID: $$"
  echo "Error: Timeout at $(date '+%H:%M:%S')" >&2
  exit 1
SH

Backspin.run(["sh", "-c", script], name: "multi_field_example")

result = Backspin.run(["sh", "-c", script], name: "multi_field_example",
  matcher: {
    stdout: ->(recorded, actual) {
      recorded.match?(/PID: \d+/) && actual.match?(/PID: \d+/)
    },
    stderr: ->(recorded, actual) {
      recorded.match?(/Error: Timeout at/) && actual.match?(/Error: Timeout at/)
    }
  })

puts "Stdout:   #{result.stdout.chomp}"
puts "Stderr:   #{result.stderr.chomp}"
puts "Status:   #{result.status}"
puts "Verified: #{result.verified?}"
puts

# Example 3: Mixed matching - some fields exact, some custom
puts "Example 3: Mixed field matching"
puts "-" * 50

script = <<~SH
  echo "Version: 1.2.3"
  echo "Build: $(date +%s)"
  echo "Status: OK"
SH

Backspin.run(["sh", "-c", script], name: "mixed_matching")

result = Backspin.run(["sh", "-c", script], name: "mixed_matching",
  matcher: {
    stdout: ->(recorded, actual) {
      recorded_lines = recorded.lines
      actual_lines = actual.lines

      recorded_lines[0] == actual_lines[0] &&
        recorded_lines[1].start_with?("Build:") && actual_lines[1].start_with?("Build:") &&
        recorded_lines[2] == actual_lines[2]
    }
  })

puts "Output:\n#{result.stdout}"
puts "Verified: #{result.verified?}"
