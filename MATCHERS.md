# Custom Matcher Usage Guide

Backspin supports custom matchers for flexible verification of command outputs. This is useful when dealing with dynamic content like timestamps, process IDs, or version numbers.

## Matcher Behavior

**Important**: Matchers work as overrides - only the fields you specify will be checked. Fields without matchers are ignored completely.

## Matcher Formats

### 1. Simple Proc Matcher

A proc matcher receives full command hashes and can check any combination of fields:

```ruby
# Check that output starts with expected prefix
result = Backspin.run("version_test",
  matcher: ->(recorded, actual) {
    recorded["stdout"].start_with?("v") && 
    actual["stdout"].start_with?("v")
  }) do
  Open3.capture3("node --version")
end
```

### 2. Field-Specific Hash Matchers

Use a hash to specify matchers for individual fields. Only specified fields are checked:

```ruby
# Only check stdout - stderr and status are ignored
result = Backspin.run("timestamp_test",
  matcher: {
    stdout: ->(recorded, actual) {
      # Both should contain a timestamp
      recorded.match?(/\d{4}-\d{2}-\d{2}/) &&
      actual.match?(/\d{4}-\d{2}-\d{2}/)
    }
  }) do
  Open3.capture3("date")
end

# Check multiple specific fields
result = Backspin.run("api_test",
  matcher: {
    stdout: ->(recorded, actual) {
      # Check JSON structure exists
      recorded.include?("\"data\":") &&
      actual.include?("\"data\":")
    },
    status: ->(recorded, actual) {
      # Both should succeed
      recorded == 0 && actual == 0
    }
    # Note: stderr is NOT checked
  }) do
  Open3.capture3("curl", "-s", "https://api.example.com")
end
```

### 3. The :all Matcher

The `:all` matcher receives complete command hashes with all fields:

```ruby
# Cross-field validation
result = Backspin.run("build_test",
  matcher: {
    all: ->(recorded, actual) {
      # Check overall success: stdout has "BUILD SUCCESSFUL" AND status is 0
      actual["stdout"].include?("BUILD SUCCESSFUL") &&
      actual["status"] == 0
    }
  }) do
  Open3.capture3("./build.sh")
end
```

### 4. Combining :all with Field Matchers

When both `:all` and field matchers are present, all must pass:

```ruby
result = Backspin.run("complex_test",
  matcher: {
    all: ->(recorded, actual) {
      # Overall check: command succeeded
      actual["status"] == 0
    },
    stdout: ->(recorded, actual) {
      # Specific check: output contains result
      actual.include?("Result:")
    },
    stderr: ->(recorded, actual) {
      # No errors expected
      actual.empty?
    }
  }) do
  Open3.capture3("./process_data.sh")
end
```

## Matcher Proc Arguments

Field-specific matchers receive field values:
- For `:stdout`, `:stderr` - String values
- For `:status` - Integer exit code

The `:all` matcher receives full hashes with these keys:
- `"stdout"` - String output
- `"stderr"` - String error output  
- `"status"` - Integer exit code
- `"command_type"` - String like "Open3::Capture3"
- `"args"` - Array of command arguments
- `"recorded_at"` - Timestamp string

## Examples

### Matching Version Numbers

```ruby
# Match major version only
matcher: {
  stdout: ->(recorded, actual) {
    recorded_major = recorded[/(\d+)\./, 1]
    actual_major = actual[/(\d+)\./, 1]
    recorded_major == actual_major
  }
}
```

### Ignoring Timestamps

```ruby
# Strip timestamps before comparing
matcher: {
  stdout: ->(recorded, actual) {
    pattern = /\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/
    recorded.gsub(pattern, '[TIME]') == actual.gsub(pattern, '[TIME]')
  }
}
```

### JSON Response Validation

```ruby
# Validate JSON structure, ignore values
matcher: {
  stdout: ->(recorded, actual) {
    begin
      recorded_data = JSON.parse(recorded)
      actual_data = JSON.parse(actual)
      
      # Same keys at top level
      recorded_data.keys.sort == actual_data.keys.sort
    rescue JSON::ParserError
      false
    end
  }
}
```

### Logging/Debugging with :all

```ruby
# Use :all for side effects while other matchers do validation
logged_commands = []

result = Backspin.run("debug_test",
  matcher: {
    all: ->(recorded, actual) {
      # Log for debugging
      logged_commands << {
        args: actual["args"],
        exit: actual["status"],
        output_size: actual["stdout"].size
      }
      true  # Always pass
    },
    stdout: ->(recorded, actual) {
      # Actual validation
      actual.include?("SUCCESS")
    }
  }) do
  Open3.capture3("./test.sh")
end

# Can inspect logged_commands after run
```

## Using with run!

The `run!` method automatically fails tests when matchers return false:

```ruby
# This will raise an error if the matcher fails
Backspin.run!("critical_test",
  matcher: {
    stdout: ->(r, a) { a.include?("OK") },
    status: ->(r, a) { a == 0 }
  }) do
  Open3.capture3("./health_check.sh")
end
```

## Migration from match_on

The `match_on` option is deprecated. To migrate:

```ruby
# Old match_on style:
Backspin.run("test", 
  match_on: [:stdout, ->(r, a) { ... }])

# New matcher style:
Backspin.run("test",
  matcher: { stdout: ->(r, a) { ... } })

# Old match_on with multiple fields:
Backspin.run("test",
  match_on: [
    [:stdout, ->(r, a) { ... }],
    [:stderr, ->(r, a) { ... }]
  ])

# New matcher style:
Backspin.run("test", 
  matcher: {
    stdout: ->(r, a) { ... },
    stderr: ->(r, a) { ... }
  })
```

Key difference: `match_on` required other fields to match exactly, while the new `matcher` hash only checks specified fields.