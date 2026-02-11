# Custom Matcher Usage Guide

Backspin supports custom matchers for flexible verification of command outputs. This is useful when dealing with dynamic content like timestamps, process IDs, or version numbers.

## Matcher Behavior

**Important**: Matchers work as overrides - only the fields you specify will be checked. Fields without matchers are ignored completely.

## Matcher Formats

### 1. Simple Proc Matcher

A proc matcher receives full command hashes and can check any combination of fields:

```ruby
result = Backspin.run(["node", "--version"], name: "version_test",
  matcher: ->(recorded, actual) {
    recorded["stdout"].start_with?("v") &&
    actual["stdout"].start_with?("v")
  })
```

### 2. Field-Specific Hash Matchers

Use a hash to specify matchers for individual fields. Only specified fields are checked:

```ruby
# Only check stdout - stderr and status are ignored
result = Backspin.run(["date"], name: "timestamp_test",
  matcher: {
    stdout: ->(recorded, actual) {
      recorded.match?(/\d{4}-\d{2}-\d{2}/) &&
      actual.match?(/\d{4}-\d{2}-\d{2}/)
    }
  })
```

### 3. The :all Matcher

The `:all` matcher receives complete command hashes with all fields:

```ruby
result = Backspin.run(["./build.sh"], name: "build_test",
  matcher: {
    all: ->(recorded, actual) {
      actual["stdout"].include?("BUILD SUCCESSFUL") &&
      actual["status"] == 0
    }
  })
```

### 4. Combining :all with Field Matchers

When both `:all` and field matchers are present, all must pass:

```ruby
result = Backspin.run(["./process_data.sh"], name: "complex_test",
  matcher: {
    all: ->(recorded, actual) { actual["status"] == 0 },
    stdout: ->(recorded, actual) { actual.include?("Result:") },
    stderr: ->(recorded, actual) { actual.empty? }
  })
```

## Matcher Proc Arguments

Field-specific matchers receive field values:
- For `:stdout`, `:stderr` - String values
- For `:status` - Integer exit code

The `:all` matcher receives full hashes with these keys:
- `"stdout"` - String output
- `"stderr"` - String error output
- `"status"` - Integer exit code (placeholder `0` for block capture)
- `"command_type"` - String like "Open3::Capture3" or "Backspin::Capturer"
- `"args"` - String or Array of command arguments
- `"env"` - Optional Hash of env vars (command runs only)
- `"recorded_at"` - Timestamp string

Matcher inputs are copies of comparison data so in-place mutation inside matcher callbacks
does not mutate Backspin's stored snapshots.

## Examples

### Matching Version Numbers

```ruby
matcher = {
  stdout: ->(recorded, actual) {
    recorded_major = recorded[/\d+/, 0]
    actual_major = actual[/\d+/, 0]
    recorded_major == actual_major
  }
}

Backspin.run(["ruby", "--version"], name: "ruby_version", matcher: matcher)
```

### Ignoring Timestamps

```ruby
matcher = {
  stdout: ->(recorded, actual) {
    pattern = /\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/
    recorded.gsub(pattern, "[TIME]") == actual.gsub(pattern, "[TIME]")
  }
}

Backspin.run(["date"], name: "timestamp_test", matcher: matcher)
```

### Logging/Debugging with :all

```ruby
logged_commands = []

Backspin.run(["./test.sh"], name: "debug_test",
  matcher: {
    all: ->(recorded, actual) {
      logged_commands << {
        args: actual["args"],
        exit: actual["status"],
        output_size: actual["stdout"].size
      }
      true
    },
    stdout: ->(recorded, actual) { actual.include?("SUCCESS") }
  })
```
