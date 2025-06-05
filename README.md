# Backspin   [![Gem Version](https://badge.fury.io/rb/backspin.svg)](https://badge.fury.io/rb/backspin) [![CircleCI](https://dl.circleci.com/status-badge/img/gh/rsanheim/backspin/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/rsanheim/backspin/tree/main)

Backspin records and replays CLI interactions in Ruby for easy snapshot testing of command-line interfaces. Currently supports `Open3.capture3` and `system` and requires `rspec-mocks`.  More system calls and flexible test integration are welcome - PRs welcome!

**NOTE:** Backspin should be considered alpha quality software while pre v1.0. It is in heavy development, and you can expect the API to change. It is being developed in conjunction with production CLI apps, so the API will be refined and improved as we get to 1.0.

Inspired by [VCR](https://github.com/vcr/vcr) and other [golden master](https://en.wikipedia.org/wiki/Golden_master_(software_development)) libraries.

## Overview

Backspin is a Ruby library for snapshot testing (or characterization testing) of command-line interfaces. While VCR records and replays HTTP interactions, Backspin records and replays CLI interactions - capturing stdout, stderr, and exit status from shell commands. 

## Installation

Add this line to your application's Gemfile in the `:test` group:

```ruby
group :test do
  gem "backspin"
end
```

And then run `bundle install`.

## Usage

### Quick Start - The Unified API

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
  Open3.capture3("echo hello world")
end
```

### Recording CLI interactions

```ruby
# Explicitly record a command's output
result = Backspin.run("echo_test", mode: :record) do
  Open3.capture3("echo hello")
end

# Or use the classic API
result = Backspin.call("echo_hello") do
  stdout, stderr, status = Open3.capture3("echo hello")
  # This will save the output to `spec/backspin_data/echo_hello.yaml`.
end
```

### Verifying CLI output

```ruby
# Explicitly verify against a recording
result = Backspin.run("echo_test", mode: :verify) do
  Open3.capture3("echo hello")
end

expect(result.verified?).to be true

# Or use the classic API
result = Backspin.verify("echo_hello") do
  Open3.capture3("echo hello")
end

expect(result.verified?).to be true
```

### Using verify! for automatic test failures

```ruby
# Automatically fail the test if output doesn't match
Backspin.run!("echo_test") do
  Open3.capture3("echo hello")
end

# Or with the classic API
Backspin.verify!("echo_hello") do
  Open3.capture3("echo hello")
end
```

### Playback mode for fast tests

```ruby
# Return recorded output without running the command
result = Backspin.run("slow_command", mode: :playback) do
  Open3.capture3("slow_command")  # Not executed - returns recorded output
end

# Or with the classic API
result = Backspin.verify("slow_command", mode: :playback) do
  Open3.capture3("slow_command")
end
```

### Custom matchers

```ruby
# Use custom logic to verify output
result = Backspin.run("version_check", 
                     matcher: ->(recorded, actual) {
                       # Just check that both start with "ruby"
                       recorded["stdout"].start_with?("ruby") && 
                       actual["stdout"].start_with?("ruby")
                     }) do
  Open3.capture3("ruby --version")
end

# Or with the classic API
Backspin.verify("version_check", 
                matcher: ->(recorded, actual) {
                  # Just check that both start with "ruby"
                  recorded["stdout"].start_with?("ruby") && 
                  actual["stdout"].start_with?("ruby")
                }) do
  Open3.capture3("ruby --version")
end
```

### VCR-style use_record

```ruby
# Record on first run, replay on subsequent runs
Backspin.use_record("my_command", record: :once) do
  Open3.capture3("echo hello")
end
```

### Working with the Result Object

The unified API returns a `UnifiedResult` object with helpful methods:

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

By default, Backspin automatically scrubs [common credential patterns](https://github.com/rsanheim/backspin/blob/f8661f084aad0ae759cd971c4af31ccf9bdc6bba/lib/backspin.rb#L46-L65) from records, but this will only handle some common cases.
Always review your record files before commiting them to source control. 

A tool like [trufflehog](https://github.com/trufflesecurity/trufflehog) or [gitleaks](https://github.com/gitleaks/gitleaks) run via a pre-commit to catch any sensitive data before commit. 

```ruby
# This will automatically scrub AWS keys, API tokens, passwords, etc.
Backspin.call("aws_command") do
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

## Features

- **Simple recording**: Capture stdout, stderr, and exit status
- **Flexible verification**: Strict matching, playback mode, or custom matchers
- **Auto-naming**: Automatically generate record names from RSpec examples
- **Multiple commands**: Record sequences of commands in a single record
- **RSpec integration**: Works seamlessly with RSpec's mocking framework
- **Human-readable**: YAML records are easy to read and edit
- **Credential scrubbing**: Automatically removes sensitive data like API keys and passwords

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rsanheim/backspin.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
