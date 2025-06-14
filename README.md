# Backspin 

[![Ruby](https://img.shields.io/badge/ruby-%23CC342D.svg?style=flat&logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![Gem Version](https://img.shields.io/gem/v/backspin)](https://rubygems.org/gems/backspin)
[![CircleCI](https://img.shields.io/circleci/build/github/rsanheim/backspin/main)](https://circleci.com/gh/rsanheim/backspin)
[![Last Commit](https://img.shields.io/github/last-commit/rsanheim/backspin/main)](https://github.com/rsanheim/backspin/commits/main)

Backspin records and replays CLI interactions in Ruby for easy snapshot testing of command-line interfaces. Currently supports `Open3.capture3` and `system` and requires `rspec`, as it uses `rspec-mocks` under the hood.

**NOTE:** Backspin should be considered alpha while pre version 1.0. It is in heavy development along-side some real-world CLI apps, so expect things to change and mature.

Inspired by [VCR](https://github.com/vcr/vcr) and other [golden master](https://en.wikipedia.org/wiki/Golden_master_(software_development)) testing libraries.

## Overview

Backspin is a Ruby library for snapshot testing (or characterization testing) of command-line interfaces. While VCR records and replays HTTP interactions, Backspin records and replays CLI interactions - capturing stdout, stderr, and exit status from shell commands. 

## Installation

Requires Ruby 3+ and will use rspec-mocks under the hood...Backspin has not been tested in other test frameworks.

Add this line to your application's Gemfile in the `:test` group:

```ruby
group :test do
  gem "backspin"
end
```

And then run `bundle install`.

## Usage

### Quick Start

The simplest way to use Backspin is with the `run` method, which automatically records on the first execution and verifies on subsequent runs:

```ruby
require "backspin"

# First run: records the output
result = Backspin.run("my_command") do
  Open3.capture3("echo hello world")
end

# Subsequent runs: verifies the output matches
result = Backspin.run("my_command") do
  Open3.capture3("echo hello world")
end

# Use run! to automatically fail tests on mismatch
Backspin.run!("my_command") do
  Open3.capture3("echo hello mars")
end
# Raises an error because stdout will not match the recorded output
```

### Recording Modes

Backspin supports different modes for controlling how commands are recorded and verified:

```ruby
# Auto mode (default): Record on first run, verify on subsequent runs
result = Backspin.run("my_command") do
  Open3.capture3("echo hello")
end

# Explicit record mode: Always record, overwriting existing recordings
result = Backspin.run("echo_test", mode: :record) do
  Open3.capture3("echo hello")
end
# This will save the output to `fixtures/backspin/echo_test.yml`.

# Explicit verify mode: Always verify against existing recording
result = Backspin.run("echo_test", mode: :verify) do
  Open3.capture3("echo hello")
end
expect(result.verified?).to be true

# Playback mode: Return recorded output without running the command
result = Backspin.run("slow_command", mode: :playback) do
  Open3.capture3("slow_command")  # Not executed - returns recorded output
end
```

### Using run! for automatic test failures

The `run!` method works exactly like `run` but automatically fails the test if verification fails:

```ruby
# Automatically fail the test if output doesn't match
Backspin.run!("echo_test") do
  Open3.capture3("echo hello")
end
# Raises an error with detailed diff if verification fails from recorded data in "echo_test.yml"
```

### Custom matchers

For cases where full matching isn't suitable, you can override via `matcher:`. **NOTE**: If you provide
custom matchers, that is the only matching that will be done. Default matching is skipped if user-provided
matchers are present.

You can override the full match logic with a proc:

```ruby
# Match stdout and status, ignore stderr
my_matcher = ->(recorded, actual) {
  recorded["stdout"] == actual["stdout"] && recorded["status"] != actual["status"]
}

result = Backspin.run("my_test", matcher: { all: my_matcher }) do
  Open3.capture3("echo hello")
end
```

Or you can override specific fields:

```ruby
# Match dynamic timestamps in stdout
timestamp_matcher = ->(recorded, actual) {
  recorded.match?(/\d{4}-\d{2}-\d{2}/) && actual.match?(/\d{4}-\d{2}-\d{2}/)
}

result = Backspin.run("timestamp_test", matcher: { stdout: timestamp_matcher }) do
  Open3.capture3("date")
end

# Match version numbers in stderr
version_matcher = ->(recorded, actual) {
  recorded[/v(\d+)\./, 1] == actual[/v(\d+)\./, 1]
}

result = Backspin.run("version_check", matcher: { stderr: version_matcher }) do
  Open3.capture3("node --version")
end
```

For more matcher examples and detailed documentation, see [MATCHERS.md](MATCHERS.md).

### Working with the Result Object

The API returns a `RecordResult` object with helpful methods:

```ruby
result = Backspin.run("my_test") do
  Open3.capture3("echo out; echo err >&2; exit 42")
end

# Check the mode
result.recorded?  # true on first run
result.verified?  # true/false on subsequent runs, nil when recording
result.playback?  # true in playback mode

# Access output (first command for single commands)
result.stdout     # "out\n"
result.stderr     # "err\n" 
result.status     # 42
result.success?   # false (non-zero exit)
result.output     # The raw return value from the block

# Debug information
result.record_path  # Path to the YAML file
result.error_message  # Human-readable error if verification failed
result.diff  # Diff between expected and actual output
```

### Multiple Commands

Backspin automatically records and verifies all commands executed in a block:

```ruby
result = Backspin.run("multi_command_test") do
  # All of these commands will be recorded
  version, = Open3.capture3("ruby --version")
  files, = Open3.capture3("ls -la")
  system("echo 'Processing...'")  # Note: system doesn't capture output
  data, stderr, = Open3.capture3("curl https://api.example.com/data")
  
  # Return whatever you need
  { version: version.strip, file_count: files.lines.count, data: data }
end

# Access individual command results
result.commands.size       # 4
result.multiple_commands?  # true

# For multiple commands, use these accessors
result.all_stdout  # Array of stdout from each command
result.all_stderr  # Array of stderr from each command
result.all_status  # Array of exit statuses

# Or access specific commands
result.commands[0].stdout  # Ruby version output
result.commands[1].stdout  # ls output
result.commands[2].status  # system call exit status (stdout is empty)
result.commands[3].stderr  # curl errors if any
```

When verifying multiple commands, Backspin ensures all commands match in the exact order they were recorded. If any command differs, you'll get a detailed error showing which commands failed.

### Credential Scrubbing

If the CLI interaction you are recording contains sensitive data in stdout or stderr, you should be careful to make sure it is not recorded to yaml!

By default, Backspin automatically tries to scrub [common credential patterns](https://github.com/rsanheim/backspin/blob/f8661f084aad0ae759cd971c4af31ccf9bdc6bba/lib/backspin.rb#L46-L65) from records, but this will only handle some common cases.
Always review your record files before commiting them to source control. 

Use a tool like [trufflehog](https://github.com/trufflesecurity/trufflehog) or [gitleaks](https://github.com/gitleaks/gitleaks) run via a pre-commit to catch any sensitive data before commit. 

```ruby
# This will automatically scrub AWS keys, API tokens, passwords, etc.
Backspin.run("aws_command") do
  Open3.capture3("aws s3 ls")
end

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
