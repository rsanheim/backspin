# Compare API Plan — differential testing between two commands

Date: 2026-07-20 (revised 2026-07-25)

## Motivation

The most common way Backspin is used in the `plur` test suite is *differential
testing*: "does tool B produce the same output as reference tool A?" plur is a
Go reimplementation of a parallel RSpec runner, and its golden specs assert that
plur's output matches `rspec`'s own output byte-for-byte.

Backspin has no first-class API for this, so today it is expressed as an
implicit two-call dance with the same record name:

```ruby
# record rspec baseline
chdir(fixture) { Backspin.run(rspec_cmd, name: "x", filter: normalize) }
# verify plur against it
result = chdir(fixture) { Backspin.run(plur_cmd, name: "x", filter: normalize) }
expect(result.verified?).to be(true)
```

That pattern works but has sharp edges, each of which has bitten a real plur
spec:

1. **Ordering is load-bearing and invisible.** The first `run` records only
   because the record file happens not to exist yet; if it does exist, *both*
   calls verify against the stored baseline — a different meaning than the code
   reads like.
2. **A stale baseline requires a manual `rm`.** Change the fixture and the
   committed `.yml` no longer matches the reference command, so the first call
   fails on `reference-vs-stale-baseline`. Nothing signals that deleting the
   snapshot is the fix.
3. **The command line must be neutralized by hand.** The two commands *differ*
   on purpose (`rspec …` vs `plur …`), so specs stuff `"args" => ["[PLACEHOLDER]"]`
   into the filter to stop the recorded command from mismatching.
4. **The filter is passed twice** and must be identical on both calls.
5. **The dance can span two examples.** plur's minitest golden test records in
   one `it` and verifies in a *different* `it` — order-dependent across
   examples, so it only works because RSpec runs in defined order.

The gap is small and specific: `Backspin.run` assumes the *record command* and
the *verify command* are the same. Differential testing needs them to differ.

## The idea

Add `Backspin.compare`, which runs a **reference** command and an **actual**
command and compares their (filtered) output. It is pure orchestration over
primitives Backspin already has — no new filtering, snapshot, diff, matcher, or
result code, and no record file.

```ruby
Backspin.compare(
  reference:,   # String/Array command that defines correct output
  actual:,      # String/Array command under test
  env: nil,
  matcher: nil, # reused as-is
  filter: nil   # reused as-is
)
# => BackspinResult
```

`reference` maps to `result.expected`, `actual` maps to `result.actual` — which
is exactly the existing `BackspinResult` contract (expected = baseline, actual =
what just ran). See `docs/backspin-result-api-sketch.md`.

## Scope: live-vs-live only

An earlier draft also proposed a snapshot-backed mode (`name:` + `mode:`), where
`compare` would record the reference to a `.yml` and later verify `actual`
against it. That is deliberately **not** in scope:

- In `mode: :verify` the `reference:` argument would be silently ignored. You
  could change the reference command and nothing would happen until someone
  deleted the record — sharp edge #2 wearing a new hat, plus a dead keyword arg.
- It roughly doubles the API surface (`name`, `mode`, `BACKSPIN_MODE`,
  `filter_on`) for a caller that does not exist yet. plur always has `rspec`
  available, in dev and in CI.

If a real caller shows up with a reference command that is expensive or absent
in CI, add it then. `Backspin.run` already covers "freeze one command's output."

## Reuse map — what each need already maps to

| Need | Existing primitive | Location |
|---|---|---|
| Run a command → stdout/stderr/status | `execute_command(command, env)` | `lib/backspin.rb` |
| Build a snapshot value object | `Snapshot.new(command_type: Open3::Capture3, …)` | `lib/backspin/snapshot.rb` |
| Apply `filter` to both sides | `CommandDiff#build_comparison_snapshot` | `lib/backspin/command_diff.rb` |
| Compare (default = stdout/stderr/status; custom matcher/hash) | `CommandDiff` + `Matcher` | `lib/backspin/command_diff.rb`, `lib/backspin/matcher.rb` |
| `verified?` / `diff` / `summary` | `CommandDiff` | `lib/backspin/command_diff.rb` |
| Result object (`expected`, `actual`, `verified?`, `diff`, `error_message`) | `BackspinResult` | `lib/backspin/backspin_result.rb` |
| Raise on mismatch (config-gated) | `raise_on_verification_failure!(result)` | `lib/backspin.rb` |

The heart of it: `CommandDiff.new(expected:, actual:, matcher:, filter:)`
already takes two snapshots, applies the filter to both, runs the matcher, and
produces `verified?`/`diff`. `compare` just has to hand it two snapshots.

## Semantics that fall out for free

- **args/env are not compared.** The default matcher only looks at stdout,
  stderr, status (`Matcher#evaluate_default`), and `CommandDiff#diff` only diffs
  those three. So two intentionally-different commands compare cleanly with no
  `args` placeholder — deleting plur boilerplate.
- **command_type matches.** Both sides are `Open3::Capture3`, so
  `CommandDiff#command_types_match?` is true.
- **Strict-by-default is preserved.** `raise_on_verification_failure!` already
  raises `VerificationError` (with `result.diff`) unless
  `raise_on_verification_failure = false`. `compare` reuses it verbatim.

## Guard: a broken reference must not pass

Live-vs-live has one failure mode the two-call dance did not: if the reference
command fails to *run at all* — wrong directory, `bundle` not on `PATH`, a load
error — it produces empty stdout and a non-zero status. If `actual` fails the
same way, `verified?` is true and the spec goes green while testing nothing.

`compare` raises `Backspin::ReferenceCommandError` when the reference command
produces no output on either stream. Exit status can't be the signal: plur's
golden specs deliberately run failing suites that exit 1.

## The new code

1. `Backspin.compare` public method (validation + orchestration + the guard).
2. A private `capture_command_snapshot(command, env)` wrapping
   `execute_command` + `Snapshot.new`. This is **extracted from existing
   duplication** — `perform_command_run` builds that same snapshot twice, so
   pulling it out DRYs `run` as well.
3. One fix in `raise_on_verification_failure!`: only emit the `Record:` line
   when there is a record path, so `compare` failures don't render a dangling
   `Record: ` label.

No changes to `CommandDiff`, `Matcher`, `Snapshot`, `Record`, or
`BackspinResult`. `compare` lives beside `run`/`capture` in `lib/backspin.rb`.

### Notes

- There is no `filter_on:` keyword. `filter_on: :record` would mean "filter only
  when persisting", and `compare` never persists — passing it would silently
  disable filtering. Omitting the keyword makes that a plain `ArgumentError`.
- `record_path` is `nil` on the result, and `mode` is `:verify` (nothing was
  recorded, so `recorded?` is false).

## Before / after (plur golden spec)

Today (`spec/integration/spec/aggregate_failure_golden_spec.rb` in plur):

```ruby
chdir(fixture) { Backspin.run(rspec_cmd, name: "x", filter: normalize) }
result = chdir(fixture) { Backspin.run(plur_cmd, name: "x", filter: normalize) }
expect(result.verified?).to be(true)
```

With `compare`:

```ruby
result = chdir(fixture) do
  Backspin.compare(reference: rspec_cmd, actual: plur_cmd, filter: normalize)
end
expect(result.verified?).to be(true)
```

A `dir:` option to drop the `chdir` wrapper is a possible follow-up; not needed
here, since one wrapper now covers what took two.

## Success criteria

1. `Backspin.compare(reference:, actual:)` runs both and returns a
   `BackspinResult` with `expected` = reference snapshot, `actual` = actual
   snapshot, and boolean `verified?`.
2. On mismatch, `result.diff` / `result.error_message` are populated by the
   existing `CommandDiff`, and `VerificationError` is raised unless
   `raise_on_verification_failure = false`. The failure message has no empty
   `Record:` line.
3. `filter` / `matcher` behave exactly as in `run` (same objects, same code
   paths).
4. Two commands with different argv compare on output only — no `args`
   normalization needed.
5. No record file is written or read.
6. A reference command that produces no output raises
   `ReferenceCommandError` rather than comparing empty-to-empty.
7. No new filtering / snapshot / diff / matcher / result implementation — only a
   `compare` entry point, the extracted `capture_command_snapshot` helper, and
   the nil-`record_path` message fix.

## Downstream: what this buys plur

Six call-site pairs across four files collapse to a single call each:
`single_failure_golden_spec.rb` (three examples), `aggregate_failure_golden_spec.rb`,
`pending_output_spec.rb`, and `minitest_integration_spec.rb` (the cross-example
one). Five fixture YAMLs get deleted, along with every `"args" => [...]`
placeholder line. plur's other five Backspin specs are ordinary single-command
snapshot tests and are untouched.
