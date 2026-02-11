# Backspin Result API Sketch

Date: 2026-02-11  
Branch: `spike-backspin-result-api`

## Goals

- Keep the public API small and predictable.
- Make runtime output and baseline output explicit.
- Remove multi-command semantics from the result object.
- Keep command run and block capture under one consistent return type.

## Public API

### Entry points

```ruby
Backspin.run(command = nil, name:, env: nil, mode: :auto, matcher: nil, filter: nil, &block)
Backspin.capture(name, mode: :auto, matcher: nil, filter: nil, &block)
```

Both return `BackspinResult`.

### `BackspinResult`

Top-level aggregate with one responsibility: represent this run and its comparison.

```ruby
class BackspinResult
  attr_reader :mode, :record_path, :actual, :expected

  def recorded?; end
  def verified?; end
  def diff; end
  def error_message; end
  def success?; end
  def failure?; end
end
```

Rules:

- `actual` is always present and represents what just ran.
- `expected` is baseline snapshot when one exists.
- In `:record` mode, `expected` is `nil`, `verified?` is `nil`.
- In `:verify` mode, `expected` is present, `verified?` is boolean.

### `Snapshot`

Value object for one recorded/captured execution.

```ruby
class Snapshot
  attr_reader :command_type, :args, :env, :stdout, :stderr, :status, :recorded_at

  def success?; end
  def failure?; end
end
```

Notes:

- `command_type` is `Open3::Capture3` for command runs.
- `command_type` is `Backspin::Capturer` for block capture.
- Capture status remains placeholder `0`.

## Usage Examples

### Command verify mismatch

```ruby
result = Backspin.run(["echo", "changed"], name: "echo_case", mode: :verify)

result.actual.stdout      # "changed\n"
result.expected.stdout    # "original\n"
result.verified?          # false
result.diff               # unified-ish stdout/stderr/status diff
```

### First record

```ruby
result = Backspin.run(["echo", "hello"], name: "hello_case")

result.mode               # :record
result.actual.stdout      # "hello\n"
result.expected           # nil
result.verified?          # nil
```

### Capture verify

```ruby
result = Backspin.capture("capture_case", mode: :verify) do
  puts "runtime output"
end

result.actual.stdout
result.expected.stdout
```

### Unix CLI examples

```ruby
# 1) Record + verify a simple command
Backspin.run(["echo", "hello"], name: "echo_hello")
result = Backspin.run(["echo", "hello"], name: "echo_hello")
result.verified?          # true
result.actual.stdout      # "hello\n"
result.expected.stdout    # "hello\n"

# 2) Verify mismatch with a common command
Backspin.run(["date", "+%Y-%m-%d"], name: "today", mode: :record)
result = Backspin.run(["date", "+%Y-%m-%d"], name: "today", mode: :verify)
result.verified?          # true/false depending on day change

# 3) Capture a small shell pipeline output
result = Backspin.capture("grep_wc") do
  system("printf 'alpha\\nbeta\\nalpha\\n' | grep alpha | wc -l")
end
result.actual.stdout

# 4) Verify a directory listing snapshot
Backspin.run(["ls", "-1"], name: "project_listing", mode: :record)
result = Backspin.run(["ls", "-1"], name: "project_listing", mode: :verify)
result.actual.stdout
result.expected.stdout
```

## Matcher and Filter Semantics

- `matcher:` applies only during verify and compares `expected` vs `actual`.
- `filter:` applies only when writing snapshots to disk.
- Verify internals materialize compare hashes once and reuse them for both matcher and diff generation.
- Default match still compares stdout/stderr/status only.

## Error Semantics

- `Backspin::VerificationError` still raised by default when verification fails.
- Error message is generated from `BackspinResult#error_message`.
- Do not duplicate `diff` content in exception formatting.

## Record Format Sketch (v4)

Single-snapshot format to match single-snapshot runtime model:

```yaml
---
format_version: "4.0"
recorded_at: "2026-02-11T00:00:00Z"
snapshot:
  command_type: "Open3::Capture3"
  args: ["echo", "hello"]
  env:
    MY_VAR: value
  stdout: "hello\n"
  stderr: ""
  status: 0
```

For capture snapshots:

```yaml
snapshot:
  command_type: "Backspin::Capturer"
  args: ["<captured block>"]
  stdout: "..."
  stderr: "..."
  status: 0
```

## Implemented Simplifications

- Unified all run/capture return values under `BackspinResult`.
- Introduced `Snapshot` as the shared value object for `actual` and `expected`.
- Removed multi-command result semantics from the public return API.
- Kept `CommandDiff`, now operating directly on snapshots.
- Simplified persistence to one snapshot per record file.

## Current Status

Status date: 2026-02-11

1. `Snapshot` and `BackspinResult` classes are implemented and wired into runtime paths.
2. `Backspin.run` and `Backspin.capture` now return `BackspinResult`.
3. `Record` persistence moved to v4 single-snapshot format (`snapshot` key, no `commands` array).
4. `Matcher` and `CommandDiff` now operate on expected/actual snapshots.
5. Legacy result/command layering was removed from `lib/`.
6. Specs have been migrated to the new result contract and v4 format.
7. Validation is green: `66 examples, 0 failures` and Standard lint passes.
8. Public docs now use `result.actual` / `result.expected` terminology.

## Success Criteria

1. `Backspin.run` and `Backspin.capture` always return `BackspinResult` with `actual` populated.
2. In `:record` mode, `result.expected` is `nil` and `result.verified?` is `nil`.
3. In `:verify` mode, `result.expected` is present, `result.verified?` is boolean, and mismatch cases populate `result.diff` plus `result.error_message`.
4. No multi-command result API remains in the public result contract.
5. Snapshot object exposes a stable single-command shape: `stdout`, `stderr`, `status`, `args`, `env`, `command_type`.
6. Record format uses one snapshot (v4), not a commands array.
7. Existing strict verification behavior remains: default raises `Backspin::VerificationError`, while `raise_on_verification_failure = false` returns a failed result without raising.
8. End-to-end Unix command examples are covered in specs: `echo` record/verify, `ls -1` record/verify, `date` mismatch behavior (or matcher override), and captured `grep | wc` pipeline output via `Backspin.capture`.
9. Matcher behavior is preserved: default matching remains stdout/stderr/status, and custom `matcher:` contract (Proc, hash fields, `:all`) continues to work for both run and capture verification.
10. Credential scrubbing behavior is preserved: stdout/stderr/args/env are scrubbed on persistence, capture output is scrubbed, custom patterns still apply, and verification diffs/error messages do not re-expose scrubbed secrets.
