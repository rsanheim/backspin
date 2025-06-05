# Backspin

Backspin records and replays CLI interactions in Ruby for easy snapshot testing of command-line interfaces. Currently supports `Open3.capture3` and `system` and requires `rspec-mocks`.  More system calls and flexible test integration are welcome - PRs welcome!

**NOTE:** Backspin is in early development (version 0.2.0), and you can expect the API to change. It is being developed along-side real-world CLI apps, so changes to make things as easy as possible as we get towards version 1.0.

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

### Recording CLI interactions

```ruby
require "backspin" 

# Record a command's output
result = Backspin.call("echo_hello") do
  stdout, stderr, status = Open3.capture3("echo hello")
  # This will save the output to `spec/backspin_data/echo_hello.yaml`.
end

```

### Verifying CLI output

```ruby
# Verify that a command produces the expected output
result = Backspin.verify("echo_hello") do
  Open3.capture3("echo hello")
end

expect(result.verified?).to be true
```

### Using verify! for automatic test failures

```ruby
# Automatically fail the test if output doesn't match
Backspin.verify!("echo_hello") do
  Open3.capture3("echo hello")
end
```

### Playback mode for fast tests

```ruby
# Return recorded output without running the command
result = Backspin.verify("slow_command", mode: :playback) do
  Open3.capture3("slow_command")  # Not executed - will playback from the record yaml (assuming it exists)
end
```

### Custom matchers

```ruby
# Use custom logic to verify output
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

_The plan is to make something like this the main entry point API for ease of use_

```ruby
# Record on first run, replay on subsequent runs
Backspin.use_record("my_command", record: :once) do
  Open3.capture3("echo hello")
end
```

### Credential Scrubbing

If the CLI interaction you are recording contains sensitive data in stdout or stderr, you should be careful to make sure it is not recorded to yaml!

By default, Backspin automatically scrubs [common credential patterns](https://github.com/backspin-rb/backspin/blob/main/lib/backspin/scrubbers.rb) from records, but this will only handle some common cases.
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