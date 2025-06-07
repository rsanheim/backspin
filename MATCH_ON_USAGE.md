# Using match_on for Field-Specific Verification

The `match_on` option allows you to use custom matchers for specific fields while maintaining exact equality checks for all other fields. This is useful when dealing with dynamic content like timestamps, process IDs, or version numbers.

## Basic Usage

### Single Field Matcher

```ruby
# Record a command with a timestamp
Backspin.run("timestamp_test") do
  Open3.capture3("date")
end

# Verify with a custom matcher for stdout
result = Backspin.run("timestamp_test",
  match_on: [:stdout, ->(recorded, actual) {
    # Both should contain a day of the week
    recorded.match?(/Mon|Tue|Wed|Thu|Fri|Sat|Sun/) &&
    actual.match?(/Mon|Tue|Wed|Thu|Fri|Sat|Sun/)
  }]) do
  Open3.capture3("date")
end
```

### Multiple Field Matchers

```ruby
# Match different fields with different rules
result = Backspin.run("multi_field_test",
  match_on: [
    [:stdout, ->(recorded, actual) {
      # Match process ID format
      recorded.match?(/PID: \d+/) && actual.match?(/PID: \d+/)
    }],
    [:stderr, ->(recorded, actual) {
      # Match error type, ignore details
      recorded.include?("Error:") && actual.include?("Error:")
    }]
  ]) do
  Open3.capture3("./my_script.sh")
end
```

## Matcher Format

The `match_on` option accepts two formats:

1. **Single field**: `[:field_name, matcher_proc]`
2. **Multiple fields**: `[[:field1, matcher1], [:field2, matcher2], ...]`

Valid field names are:
- `:stdout` - Standard output
- `:stderr` - Standard error
- `:status` - Exit status code

## Matcher Proc

The matcher proc receives two arguments:
- `recorded_value` - The value from the saved recording
- `actual_value` - The value from the current execution

It should return `true` if the values match according to your criteria, `false` otherwise.

## Examples

### Matching Version Numbers

```ruby
# Match major version only
match_on: [:stdout, ->(recorded, actual) {
  recorded.match(/Version: (\d+)\./) && 
  actual.match(/Version: (\d+)\./) &&
  $1 == $1  # Major versions match
}]
```

### Ignoring Timestamps

```ruby
# Match log format but ignore timestamp
match_on: [:stdout, ->(recorded, actual) {
  # Remove timestamps before comparing
  recorded.gsub(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/, '') ==
  actual.gsub(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/, '')
}]
```

### Handling Dynamic IDs

```ruby
# Match API response structure, ignore dynamic IDs
match_on: [:stdout, ->(recorded, actual) {
  recorded_json = JSON.parse(recorded)
  actual_json = JSON.parse(actual)
  
  # Compare structure, not values
  recorded_json.keys.sort == actual_json.keys.sort
}]
```

## Important Notes

1. **Other fields must match exactly**: When using `match_on`, all fields not specified in the matcher list must match exactly. If stdout has a custom matcher but stderr doesn't, stderr must be identical to pass verification.

2. **Precedence**: If both `matcher` and `match_on` options are provided, `matcher` takes precedence (for backward compatibility).

3. **Error messages**: When verification fails with `match_on`, the error will indicate which fields failed and whether they failed exact matching or custom matching.

4. **Works with run!**: The `match_on` option works with both `run` and `run!` methods.