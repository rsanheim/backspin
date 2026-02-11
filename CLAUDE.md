# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Backspin is a Ruby gem for characterization testing of command-line interfaces. It records and verifies CLI interactions by capturing stdout, stderr, and exit status from shell commands, similar to how VCR works for HTTP interactions. Backspin uses YAML "records" to store snapshots.

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
- Main API: `run` (direct command execution and block capture), `capture` (alias for block form)
- Credential scrubbing logic
- Configuration management (including `raise_on_verification_failure` which defaults to `true`)

**Snapshot Class** (`lib/backspin/snapshot.rb`)
- Represents a single captured execution snapshot
- Stores: command type, args, env, stdout, stderr, status, recorded_at

**BackspinResult Class** (`lib/backspin/backspin_result.rb`)
- Return object from `run` and `capture`
- Exposes `actual` and `expected` snapshots plus verification metadata

**Record Class** (`lib/backspin/record.rb`)
- Manages YAML record files
- Handles record/verify sequencing

**Recorder Class** (`lib/backspin/recorder.rb`)
- Implements block capture recording and verification
- Restores stdout/stderr streams safely after capture

### Key Design Patterns

- Direct `Open3.capture3` execution for command runs
- Tempfile-based FD capture for block forms
- Single-command records stored as YAML
- Automatic credential scrubbing for security (AWS keys, API tokens, passwords, env values)
- Recording modes: `:auto`, `:record`, `:verify`

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
