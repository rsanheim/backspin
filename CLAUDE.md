# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Backspin is a Ruby gem for characterization testing of command-line interfaces. It records and replays CLI interactions by capturing stdout, stderr, and exit status from shell commands - similar to how VCR works for HTTP interactions. Backspin uses "records" (YAML files) to store recorded command outputs.

## Development Commands

### Setup
```bash
bundle install
bin/setup
```

### Testing
```bash
bin/rake spec                    # Run all tests
bin/rspec spec/[file]           # Run specific test file
bin/rspec spec/[file]:[line]    # Run specific test
```

### Building and Releasing
```bash
bin/rake install     # Install gem locally for testing
bin/rake release     # Release to RubyGems (updates version, tags, pushes)
```

### Code Quality
```bash
script/lint                      # Run Standard Ruby linter
script/lint --fix                # Auto-fix linting issues
bin/rake standard                # Alternative: Run via Rake task
```

**Important**: Always use `standardrb` for linting, never use `rubocop` directly. The project uses Standard Ruby for consistent code style.

## Architecture

### Core Components

**Backspin Module** (`lib/backspin.rb`)
- Main API: `run`, `run!` (both raise on verification failure by default)
- Legacy API: `call`, `verify`, `verify!`, `use_record`
- Credential scrubbing logic
- Configuration management (including `raise_on_verification_failure` which defaults to `true`)

**Command Class** (`lib/backspin.rb`)
- Represents a single CLI execution
- Stores: args, stdout, stderr, status, recorded_at

**Record Class** (`lib/backspin/record.rb`)
- Manages YAML record files
- Handles recording/playback sequencing

**RSpecMetadata** (`lib/backspin/rspec_metadata.rb`)
- Auto-generates record names from RSpec context

### Key Design Patterns

- Uses RSpec mocking to intercept `Open3.capture3` calls
- Records are stored as YAML arrays to support multiple commands
- Automatic credential scrubbing for security (AWS keys, API tokens, passwords)
- VCR-style recording modes: `:once`, `:all`, `:none`, `:new_episodes`

### Testing Approach

- Integration-focused tests that exercise the full stack
- Default record directory is `fixtures/backspin` (can be configured)
- Tests use real shell commands (`echo`, `date`, etc.)
- Configuration is reset between tests to avoid side effects
- **Important**: Backspin specs MUST be as local and un-DRY as possible. Each spec should be self-contained with its own setup, expectations, and cleanup if needed. Avoid shared contexts or helpers that hide important test details.

## Common Development Tasks

### Adding New Features
1. Write integration tests in `spec/backspin/`
2. Implement in appropriate module (usually `lib/backspin.rb`)
3. Update README.md if adding public API
4. Run tests with `rake spec`

### Debugging Tests
- Records are saved to `fixtures/backspin/` by default
- Check YAML files to see recorded command outputs

### Updating Credential Patterns
- Add patterns to `DEFAULT_CREDENTIAL_PATTERNS` in `lib/backspin.rb`
- Test with appropriate fixtures in specs