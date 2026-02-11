# Backspin

[![Ruby](https://img.shields.io/badge/ruby-%23CC342D.svg?style=flat&logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![Gem Version](https://img.shields.io/gem/v/backspin)](https://rubygems.org/gems/backspin)
[![CircleCI](https://img.shields.io/circleci/build/github/rsanheim/backspin/main)](https://circleci.com/gh/rsanheim/backspin)
[![Last Commit](https://img.shields.io/github/last-commit/rsanheim/backspin/main)](https://github.com/rsanheim/backspin/commits/main)

Backspin records command output and block output in Ruby for easy snapshot testing of command-line interfaces. It supports direct command runs via `Open3.capture3` and block capture for more complex scenarios.

**NOTE:** Backspin should be considered alpha while pre version 1.0. It is in heavy development along-side some real-world CLI apps, so expect things to change and mature.

Inspired by [VCR](https://github.com/vcr/vcr) and other [characterization (aka golden master)](https://en.wikipedia.org/wiki/Characterization_test) testing libraries.

## Overview

Backspin is a Ruby library for snapshot testing (or characterization testing) of command-line interfaces. While VCR records and replays HTTP interactions, Backspin records stdout, stderr, and exit status from shell commands, or captures all output from a block.

## Installation

Requires Ruby 3+.

Add this line to your application's Gemfile in the `:test` group:

```ruby
group :test do
  gem "backspin"
end
```

And then run `bundle install`.

## Usage

### Quick Start (Command Runs)

The simplest way to use Backspin is with the `run` method, which automatically records on the first execution and verifies on subsequent runs.

```ruby
require "backspin"

# First run: records the output
result = Backspin.run(["echo", "hello world"], name: "my_command")

# Subsequent runs: verifies the output matches and raises on mismatch
Backspin.run(["echo", "hello world"], name: "my_command")

# This will raise an error automatically
Backspin.run(["echo", "hello mars"], name: "my_command")
# Raises Backspin::VerificationError because output doesn't match
```

You can also pass a string command (which invokes a shell):

```ruby
Backspin.run("echo hello", name: "string_command")
```

### Block Capture

Use block capture when you need to run multiple commands or use APIs that already write to stdout/stderr:

```ruby
# Capture all output from the block
result = Backspin.run(name: "block_capture") do
  system("echo from system")
  puts "from puts"
  `echo from backticks`
end

# Alias form
Backspin.capture("block_capture") do
  puts "from capture"
end
```

Block capture records a single combined stdout/stderr snapshot. Exit status is a placeholder (`0`) in this mode.

### Recording Modes

Backspin supports different modes for controlling how commands are recorded and verified:

```ruby
# Auto mode (default): Record on first run, verify on subsequent runs
Backspin.run(["echo", "hello"], name: "my_command")

# Explicit record mode: Always record, overwriting existing recordings
Backspin.run(["echo", "hello"], name: "echo_test", mode: :record)

# Explicit verify mode: Always verify against existing recording
result = Backspin.run(["echo", "hello"], name: "echo_test", mode: :verify)
expect(result.verified?).to be true
```

### Environment Variable Mode Override

Set `BACKSPIN_MODE` to globally force a recording mode without changing any test code:

```bash
# Re-record all fixtures
BACKSPIN_MODE=record bundle exec rspec

# Verify-only (CI, no accidental re-records)
BACKSPIN_MODE=verify bundle exec rspec
```

Precedence (highest to lowest):

1. Explicit `mode:` kwarg (`:record` or `:verify`)
2. `BACKSPIN_MODE` environment variable
3. Auto-detection (record if no file exists, verify if it does)

Allowed values: `auto`, `record`, `verify` (case-insensitive). Invalid values raise `ArgumentError`.

### Record Metadata

Backspin writes records using `format_version: "4.1"` with top-level metadata:

```yaml
---
format_version: "4.1"
first_recorded_at: "2026-01-01T10:00:00Z" # immutable
recorded_at: "2026-02-01T10:00:00Z"       # updates on each write
record_count: 3                            # increments on each write
snapshot:
  command_type: "Open3::Capture3"
  args: ["echo", "hello"]
  stdout: "hello\n"
  stderr: ""
  status: 0
  recorded_at: "2026-02-01T10:00:00Z"
```

When re-recording with `mode: :record`, Backspin preserves `first_recorded_at`, updates `recorded_at`, and increments `record_count`.
Existing `4.0` records still load and are upgraded to `4.1` metadata on the next write.

### Environment Variables

```ruby
Backspin.run(
  ["ruby", "-e", "print ENV.fetch('MY_ENV_VAR')"],
  name: "with_env",
  env: {"MY_ENV_VAR" => "value"}
)
```

If `env:` is not provided, it is not passed to `Open3.capture3` and is not recorded.

### Custom Matchers

For cases where full matching isn't suitable, you can override via `matcher:`. **NOTE**: If you provide
custom matchers, that is the only matching that will be done. Default matching is skipped if user-provided
matchers are present.

You can override the full match logic with a proc:

```ruby
my_matcher = ->(recorded, actual) {
  recorded["stdout"] == actual["stdout"] && recorded["status"] == actual["status"]
}

result = Backspin.run(["echo", "hello"], name: "my_test", matcher: {all: my_matcher})
```

Or you can override specific fields:

```ruby
# Match dynamic timestamps in stdout
timestamp_matcher = ->(recorded, actual) {
  recorded.match?(/\d{4}-\d{2}-\d{2}/) && actual.match?(/\d{4}-\d{2}-\d{2}/)
}

result = Backspin.run(["date"], name: "timestamp_test", matcher: {stdout: timestamp_matcher})
```

For more matcher examples and detailed documentation, see [MATCHERS.md](MATCHERS.md).

### Filters and Canonicalization

Use `filter:` to normalize snapshot data (timestamps, random IDs, absolute paths).

By default (`filter_on: :both`), Backspin applies `filter`:
- when writing record snapshots
- during verify for both expected and actual, before matcher and diff

If you only want record-time filtering, use `filter_on: :record`.

Migration note: older behavior applied `filter` only at record write. To preserve that behavior, set `filter_on: :record`.

```ruby
normalize_filter = ->(snapshot) do
  snapshot.merge(
    "stdout" => snapshot["stdout"].gsub(/id=\d+/, "id=[ID]")
  )
end

# default: filter_on :both
Backspin.run(["echo", "id=123"], name: "canonicalized", filter: normalize_filter)
Backspin.run(["echo", "id=999"], name: "canonicalized", filter: normalize_filter) # verifies

# capture also supports verify-time canonicalization
Backspin.capture("capture_canonicalized", filter: normalize_filter) do
  puts "id=123"
end
Backspin.capture("capture_canonicalized", filter: normalize_filter) do
  puts "id=999"
end

# record-only filtering
Backspin.run(["echo", "id=123"], name: "record_only", filter: normalize_filter, filter_on: :record)
```

### Working with the Result Object

The API returns a `Backspin::BackspinResult` object with helpful methods:

```ruby
result = Backspin.run(["sh", "-c", "echo out; echo err >&2; exit 42"], name: "my_test")

# Check the mode
result.recorded?  # true on first run
result.verified?  # true/false on subsequent runs, nil when recording

# Access output snapshots
result.actual.stdout   # "out\n"
result.actual.stderr   # "err\n"
result.actual.status   # 42
result.expected        # nil in :record mode, populated in :verify mode
result.success?        # false (non-zero exit)
result.output     # [stdout, stderr, status] for command runs

# Debug information
result.record_path  # Path to the YAML file
result.error_message  # Human-readable error if verification failed
result.diff  # Diff between expected and actual output
```

### Configuration

You can configure Backspin's behavior globally:

```ruby
Backspin.configure do |config|
  config.raise_on_verification_failure = false # default is true
  config.backspin_dir = "spec/fixtures/cli_records" # default is "fixtures/backspin"
  config.scrub_credentials = false # default is true
end
```

The `raise_on_verification_failure` setting affects both `Backspin.run` and `Backspin.capture`:
- When `true` (default): Both methods raise `Backspin::VerificationError` on verification failure
- When `false`: Both methods return a result with `verified?` set to false

If you need to disable the raising behavior for a specific test, you can temporarily configure it:

```ruby
Backspin.configure do |config|
  config.raise_on_verification_failure = false
end

result = Backspin.run(["echo", "different"], name: "my_test")
# result.verified? will be false but won't raise

Backspin.reset_configuration!
```

### Logging

Backspin includes a configurable logger for diagnostics. By default it logs at `DEBUG` level to stdout using a logfmt-lite format:

```
level=debug lib=backspin event=mode_resolved mode=record source=env record=fixtures/backspin/my_test.yml
```

To reduce log output:

```ruby
Backspin.configure do |config|
  config.logger.level = Logger::WARN
end
```

To replace the logger entirely:

```ruby
Backspin.configure do |config|
  config.logger = Logger.new("log/backspin.log")
end
```

To disable Backspin logging entirely (for example in tests):

```ruby
Backspin.configure do |config|
  config.logger = nil
end
```

### Credential Scrubbing

If the CLI interaction you are recording contains sensitive data in stdout/stderr, you should be careful to make sure it is not recorded to YAML.

By default, Backspin automatically tries to scrub common credential patterns from recorded stdout, stderr, args, and env values. Always review your record files before commiting them to source control.

```ruby
# This will automatically scrub AWS keys, API tokens, passwords, etc.
Backspin.run(["aws", "s3", "ls"], name: "aws_command")

# Add custom patterns to scrub
Backspin.configure do |config|
  config.add_credential_pattern(/MY_SECRET_[A-Z0-9]+/)
end

# Disable credential scrubbing - use with caution!
Backspin.configure do |config|
  config.scrub_credentials = false
end
```

Automatic scrubbing includes:
- AWS access keys, secret keys, and session tokens
- Google API keys and OAuth client IDs
- Generic API keys, auth tokens, and passwords
- Private keys (RSA, etc.)

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rsanheim/backspin.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
