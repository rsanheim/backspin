# Backspin Capture-First Refactor Analysis

*Review of the `spike-simplify` branch (v0.8.0)*

## Summary

This refactor represents a **major simplification** of Backspin's architecture. The codebase goes from ~3500 lines of tests/implementation to ~650 - a net reduction of ~2850 lines. The new API is cleaner, more predictable, and removes the RSpec runtime dependency entirely.

## What Changed

### API Surface (Breaking)

**Before:**
* `Backspin.run` / `Backspin.run!` with RSpec mock-based interception
* `Backspin.capture` for block-based capture
* Support for `:playback` mode (return recorded values without executing)
* Multiple command recording per record

**After:**
* `Backspin.run(command, name:, env:, mode:, matcher:, filter:)` - direct command execution
* `Backspin.run(name:) { ... }` - block capture form
* `Backspin.capture("name") { ... }` - alias for block capture
* Only `:auto`, `:record`, `:verify` modes (no `:playback`)
* Single command per record

### Architecture Changes

| Component | Before | After |
|-----------|--------|-------|
| *Recorder* | 220+ lines, RSpec mocks, `allow(Open3).to receive(:capture3).and_wrap_original` | 110 lines, tempfile-based FD redirection |
| *Command execution* | Intercepted via mock stubs | Direct `Open3.capture3` calls |
| *RSpec dependency* | Required at runtime | Completely removed |
| *Record format* | Version 2.x, multiple command types | Version 3.0, only `Open3::Capture3` and `Backspin::Capturer` |

### Key Simplifications

1. **No more mock magic** - Commands run via `Open3.capture3` directly. This is significantly easier to reason about and debug.

2. **Two clear paths:**
   * *Command run*: `Backspin.run(["cmd", "args"], name: "foo")` → executes, records/verifies stdout/stderr/status
   * *Block capture*: `Backspin.run(name: "foo") { ... }` or `Backspin.capture("foo") { ... }` → captures all output from the block via FD redirection

3. **Strict by default** - `VerificationError` raised on mismatch (configurable via `raise_on_verification_failure`)

4. **Removed complexity:**
   * No multi-command records (each record = one command/capture)
   * No playback mode
   * No `system` call interception
   * No `run!` variant (the default `run` is now strict)

## New API Examples

### Command Runs

```ruby
# Array form (recommended - no shell invocation)
result = Backspin.run(["echo", "hello"], name: "my_test")

# String form (invokes shell)
result = Backspin.run("echo hello", name: "my_test")

# With environment variables
result = Backspin.run(
  ["ruby", "-e", "puts ENV['MY_VAR']"],
  name: "env_test",
  env: {"MY_VAR" => "value"}
)
```

### Block Capture

```ruby
# Captures stdout/stderr from anything in the block
result = Backspin.capture("my_capture") do
  puts "from puts"
  system("echo from system")
  `echo from backticks`
end

# Equivalent using run with a block
result = Backspin.run(name: "my_capture") do
  puts "from puts"
end
```

### Modes

```ruby
# Auto (default): record if no file exists, verify if it does
Backspin.run(["echo", "hi"], name: "test")

# Force record (overwrites existing)
Backspin.run(["echo", "hi"], name: "test", mode: :record)

# Force verify (fails if no record exists)
Backspin.run(["echo", "hi"], name: "test", mode: :verify)
```

### Matchers

Matchers work as overrides - only specified fields are checked:

```ruby
# Check only stdout (ignores stderr and status differences)
Backspin.run(["date"], name: "date_test", matcher: {
  stdout: ->(recorded, actual) { actual.match?(/\d{4}/) }
})

# Full control with :all
Backspin.run(["cmd"], name: "test", matcher: {
  all: ->(recorded, actual) { actual["status"] == 0 }
})
```

## Record Format (v3.0)

```yaml
---
first_recorded_at: '2026-02-04T10:30:00-06:00'
format_version: '3.0'
commands:
  - command_type: Open3::Capture3  # or Backspin::Capturer
    args: ["echo", "hello"]        # or "<captured block>"
    env:                           # optional, only if provided
      MY_VAR: value
    stdout: "hello\n"
    stderr: ""
    status: 0
    recorded_at: '2026-02-04T10:30:00-06:00'
```

## What's No Longer Supported

* **`:playback` mode** - Always executes real commands now
* **`Backspin.run!`** - Removed; `run` is strict by default
* **Multi-command records** - Each record holds exactly one command
* **`system` call interception** - Use block capture if you need to record `system` output
* **Legacy record formats** - Only v3.0 accepted; old records must be re-recorded
* **RSpec runtime dependency** - Can use Backspin in any test framework now

## Assessment

### Pros

* **Dramatically simpler** - ~80% reduction in test code, cleaner implementation
* **No mock magic** - Much easier to debug and understand
* **Framework agnostic** - No RSpec runtime dependency
* **Clearer mental model** - Two paths (command/block), one command per record
* **Fail-fast default** - Verification errors raised immediately

### Potential Concerns

* **Migration pain** - Existing records need re-recording (format v3.0)
* **Multi-command workflows** - Users who relied on recording multiple commands in sequence need a different approach (multiple records, or use block capture)
* **Playback gone** - Some testing patterns relied on not executing commands during CI

### Open Questions / Follow-ups

From the plan document:
* [ ] Add a default-behavior spec that calls `Backspin.run` twice with the same name (record then verify, no mode override).
* [ ] Add outside-in integration specs with real commands (`echo`, `ls`, `date`) covering `:auto`/`:record`/`:verify`, plus string vs array command forms.
* [ ] Rebuild behavior coverage for record/format errors, command type mismatch, command count mismatch, and invalid inputs (including `:playback`).
* [ ] Expand matcher/filter/credential scrubbing coverage across both run and capture, including failure messaging and diff output.
* [ ] Add negative tests for rejected modes/formats and missing records.
* [ ] Consider supporting splat args: `Backspin.run("ls", "-l", name: "test")`

## Verdict

This is a healthy simplification. The old architecture was over-engineered for the common case (testing a CLI tool's output). The new API is:

* Easier to teach
* Easier to debug
* Fewer moving parts
* Clear escape hatch (block capture) for complex scenarios

The breaking changes are worth it for a pre-1.0 library. The lack of backwards compatibility concern makes this the right time to do it.
