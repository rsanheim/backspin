# Contributing to Backspin

Thank you for your interest in contributing to Backspin! This guide will help you get started with development and walk you through the contribution process.

Note that Backspin is in early development and the API _will_ change before stabilizing at 1.0.

## Table of Contents

- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)
- [Code Style](#code-style)
- [Reporting Issues](#reporting-issues)
- [Feature Requests](#feature-requests)

## Getting Started

Backspin is a Ruby gem for characterization testing of command-line interfaces. It records and replays CLI interactions by capturing stdout, stderr, and exit status from shell commands - similar to how VCR works for HTTP interactions.

### Prerequisites

- Ruby 3.2, 3.3, or 3.4
- Bundler
- Git

## Development Setup

1. Fork and clone the repository:
   ```bash
   git clone https://github.com/rsanheim/backspin.git
   cd backspin
   ```

2. Run the setup script:
   ```bash
   bin/setup
   ```

3. Run the full build (specs & standardrb linting) to ensure everything is working:
   ```bash
   bin/rake spec
   ```

## Making Changes

### Development Workflow

1. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes following the project conventions

3. Run tests frequently:
   ```bash
   bin/rake spec
   ```

4. Run the linter:
   ```bash
   bin/rake standard
   ```

5. Commit your changes with clear, descriptive messages

### Architecture Overview

**Core Components:**

- **Backspin Module** (`lib/backspin.rb`)
  - Main API: `call`, `verify`, `verify!`, `use_record`
  - Credential scrubbing logic
  - Configuration management

- **Command Class** (`lib/backspin/command.rb`)
  - Represents a single CLI execution
  - Stores: args, stdout, stderr, status, recorded_at, etc

- **Record Class** (`lib/backspin/record.rb`)
  - Manages YAML record files
  - Handles recording/playback sequencing

### Common Development Tasks

#### Adding New Features

1. Write integration tests in `spec/backspin/`
2. Implement in appropriate module (usually `lib/backspin.rb`)
3. Update README.md if adding public API
4. Run the the full build

#### Updating Credential Patterns

- Add patterns to `DEFAULT_CREDENTIAL_PATTERNS` in `lib/backspin.rb`
- Test with appropriate fixtures in specs

#### Debugging Tests

- Records are saved to `fixtures/backspin/` by default
- Check YAML files to see recorded command outputs

## Testing

### Running Tests

```bash
# Run all tests
bin/rake spec

# Run specific test file
bundle exec rspec spec/backspin/record_spec.rb

# Run specific test
bundle exec rspec spec/backspin/record_spec.rb:42
```

### Writing Tests

Backspin uses integration-focused tests that exercise the full stack. When writing tests:

- Keep specs self-contained with their own setup, expectations, and cleanup
- Avoid shared contexts or helpers that hide important test details
- Use real shell commands (`echo`, `date`, etc.) for testing
- Ensure configuration is reset between tests to avoid side effects
- Verify new or updated test records in `fixtures/backspin/`

Example test structure:

```ruby
RSpec.describe "Feature name" do
  it "does something specific" do
    # Setup
    record_name = "my_test_record"
    
    # Exercise
    result = Backspin.call(record_name) do
      Open3.capture3("echo", "hello")
    end
    
    # Verify
    expect(result.stdout).to eq("hello\n")
  end
end
```

## Submitting Changes

### Pull Request Process

1. Ensure all tests pass
2. Update documentation if needed
3. Add entries to CHANGELOG.md following the existing format
4. Push your branch and create a pull request
5. Provide a clear description of your changes
6. Link any related issues

### Pull Request Guidelines

- Keep changes focused and atomic
- Include tests for new functionality
- Update examples in README.md if changing public APIs
- Ensure CI passes (tests against Ruby 3.2, 3.3, and 3.4)

## Code Style

Backspin uses [Standard Ruby](https://github.com/standardrb/standard) for code formatting. Run the linter before committing:

```bash
bin/rake standard
```

To automatically fix issues:

```bash
bin/rake standard:fix
```

## Reporting Issues

### Bug Reports

When reporting bugs, please include *full logs* including:

1. Ruby version (`ruby -v`) and ruby version manager info
2. Backspin version
3. Minimal reproduction code
4. Expected behavior vs actual behavior
5. Full error messages and stack traces
6. Relevant YAML record files (sanitized of sensitive data)

### Security Issues

For security vulnerabilities, please email the maintainers directly rather than opening a public issue.

## Feature Requests

We welcome feature requests! When proposing new features:

1. Check existing issues to avoid duplicates
2. Describe the use case and motivation
3. Provide code examples of how the feature would work
4. Be open to discussion and alternative approaches

## Additional Resources

- [Project README](README.md)
- [CLAUDE.md](CLAUDE.md) - AI assistant guidance
- [RSpec Documentation](https://rspec.info/)
- [Standardrb linting](https://github.com/standardrb/standard)

## Questions?

If you have questions about contributing, feel free to:

- Open an issue for discussion
- Check existing issues and pull requests
- Review the test suite for examples

Thank you for contributing to Backspin!