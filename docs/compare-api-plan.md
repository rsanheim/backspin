# Compare API Plan — differential testing between two commands

Date: 2026-07-20

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

The gap is small and specific: `Backspin.run` assumes the *record command* and
the *verify command* are the same. Differential testing needs them to differ.

## The idea

Add `Backspin.compare` that runs a **reference** command and an **actual**
command and compares their (filtered) output. It is pure orchestration over
primitives Backspin already has — no new filtering, snapshot, diff, matcher, or
result code.

```ruby
Backspin.compare(
  reference:,          # String/Array command that defines correct output
  actual:,             # String/Array command under test
  name: nil,           # optional: persist the reference snapshot (see modes)
  env: nil,
  matcher: nil,        # reused as-is
  filter: nil,         # reused as-is
  filter_on: :both,    # reused as-is
  mode: :auto          # only meaningful when name: is given
)
# => BackspinResult
```

`reference` maps to `result.expected`, `actual` maps to `result.actual` — which
is exactly the existing `BackspinResult` contract (expected = baseline, actual =
what just ran). See `docs/backspin-result-api-sketch.md`.

## Reuse map — what each need already maps to

Everything `compare` needs already exists; the plan is to wire it together, not
to re-implement it.

| Need | Existing primitive | Location |
|---|---|---|
| Run a command → stdout/stderr/status | `execute_command(command, env)` | `lib/backspin.rb:221` |
| Build a snapshot value object | `Snapshot.new(command_type: Open3::Capture3, …)` | `lib/backspin/snapshot.rb:8` |
| Apply `filter`/`filter_on` to both sides | `CommandDiff#build_comparison_snapshot` | `lib/backspin/command_diff.rb:109` |
| Compare (default = stdout/stderr/status; custom matcher/hash) | `CommandDiff` + `Matcher` | `lib/backspin/command_diff.rb`, `lib/backspin/matcher.rb` |
| `verified?` / `diff` / `summary` | `CommandDiff` | `lib/backspin/command_diff.rb:22` |
| Result object (`expected`, `actual`, `verified?`, `diff`, `error_message`) | `BackspinResult` | `lib/backspin/backspin_result.rb` |
| Raise on mismatch (config-gated) | `raise_on_verification_failure!(result)` | `lib/backspin.rb:233` |
| Persist / load a reference snapshot | `Record.load_or_create` / `record.save(filter:)` | `lib/backspin/record.rb` |
| Resolve record/verify/auto + `BACKSPIN_MODE` | `determine_mode` / `mode_from_env` | `lib/backspin.rb:244` |

The heart of it: `CommandDiff.new(expected:, actual:, matcher:, filter:, filter_on:)`
already takes two snapshots, applies the filter to both, runs the matcher, and
produces `verified?`/`diff`. `compare` just has to hand it two snapshots.

## Two modes, both built from existing pieces

### 1. Live-vs-live (no `name:`) — the primary win

When no `name:` is given, run both commands live and diff. No record file is
written or read.

```ruby
def compare_live(reference:, actual:, env:, matcher:, filter:, filter_on:)
  expected = capture_command_snapshot(reference, env)   # execute_command + Snapshot.new
  actual_s = capture_command_snapshot(actual, env)
  diff = CommandDiff.new(expected: expected, actual: actual_s,
                         matcher: matcher, filter: filter, filter_on: filter_on)
  result = BackspinResult.new(mode: :verify, record_path: nil,
                              actual: actual_s, expected: expected,
                              verified: diff.verified?, command_diff: diff)
  raise_on_verification_failure!(result)
  result
end
```

This removes every sharp edge above at once: no ordering trick, no stale-`.yml`,
no manual `args` placeholder (see below), one filter. It fits differential
testing where the reference is reproducible in CI (rspec always is, for plur).

`filter_on` in live mode is effectively always `:both` — there is no persistence
step for `:record` to key off of. The plan is to document that and either force
`:both` or reject `:record` when `name:` is absent.

### 2. Snapshot-backed (`name:` given) — reuse `Record`

When you *do* want a frozen baseline (reference tool is expensive, or not
installed in CI), pass `name:` and reuse the existing mode machinery:

- `mode: :record` → run `reference`, `record.save(filter:)` its snapshot. This is
  the one command whose output is the source of truth.
- `mode: :verify` → load the stored reference snapshot as `expected`, run
  `actual`, `CommandDiff`, return the verified result. The reference command is
  **not** re-run.
- `mode: :auto` → record if the file is missing, else verify (existing
  `determine_mode`), and `BACKSPIN_MODE` overrides as usual (existing
  `mode_from_env`).

This is the missing capability stated plainly: **decouple the record command
from the verify command.** `Backspin.run` records and verifies the *same*
command; snapshot-backed `compare` records `reference` and verifies `actual`.
Everything else — `Record`, `Snapshot`, `CommandDiff`, `Matcher`, `filter`,
`BackspinResult`, `determine_mode` — is unchanged.

## Semantics that fall out for free

- **args/env are not compared.** The default matcher only looks at stdout,
  stderr, status (`Matcher#evaluate_default`, `lib/backspin/matcher.rb:54`), and
  `CommandDiff#diff` only diffs those three. So two intentionally-different
  commands compare cleanly with no `args` placeholder — deleting plur boilerplate.
- **command_type matches.** Both sides are `Open3::Capture3`, so
  `CommandDiff#command_types_match?` is true.
- **Strict-by-default is preserved.** `raise_on_verification_failure!` already
  raises `VerificationError` (with `result.diff`) unless
  `raise_on_verification_failure = false`. `compare` reuses it verbatim.

## The only new code

1. `Backspin.compare` public method (arg validation + the orchestration above).
2. A small private helper `capture_command_snapshot(command, env)` that wraps
   `execute_command` + `Snapshot.new`. This is **extracted from existing
   duplication** — `perform_command_run` builds that same snapshot twice
   (`lib/backspin.rb:155` and `:182`), so pulling it out DRYs `run` as well.

No changes to `CommandDiff`, `Matcher`, `Snapshot`, `Record`, or
`BackspinResult`. `compare` lives beside `run`/`capture` in `lib/backspin.rb`.

## Before / after (plur golden spec)

Today (`spec/integration/spec/aggregate_failure_golden_spec.rb` in plur):

```ruby
chdir(fixture) { Backspin.run(rspec_cmd, name: "x", filter: normalize) }
result = chdir(fixture) { Backspin.run(plur_cmd, name: "x", filter: normalize) }
expect(result.verified?).to be(true)
```

With `compare` (live):

```ruby
result = Backspin.compare(reference: rspec_cmd, actual: plur_cmd,
                          filter: normalize, dir: fixture)
expect(result.verified?).to be(true)
```

(`dir:` is a tiny optional add to drop the `chdir` wrapper; not required for the
core plan and can be deferred.)

## Open questions

1. **Live `filter_on`:** force `:both`, or raise if `:record` is passed without
   `name:`? Leaning: force `:both` and document.
2. **Block support:** `run` has a block form via `Backspin.capture`. Should
   `compare` accept blocks for `reference`/`actual` too? Not needed by plur;
   defer. If added, reuse `Recorder#capture_output` the same way.
3. **`record_path` on live results:** `nil` is honest (nothing persisted).
   Confirm `BackspinResult#to_h` and error formatting tolerate a nil path.
4. **Snapshot-backed record ergonomics:** should `mode: :record` also run
   `actual` and report the diff for convenience, or only capture the reference?
   Leaning: capture reference only, matching `run`'s record semantics.

## Success criteria

1. `Backspin.compare(reference:, actual:)` runs both and returns a
   `BackspinResult` with `expected` = reference snapshot, `actual` = actual
   snapshot, and boolean `verified?`.
2. On mismatch, `result.diff` / `result.error_message` are populated by the
   existing `CommandDiff`, and `VerificationError` is raised unless
   `raise_on_verification_failure = false`.
3. `filter` / `filter_on` / `matcher` behave exactly as in `run` (same objects,
   same code paths).
4. Two commands with different argv compare on output only — no `args`
   normalization needed.
5. Live mode writes and reads no record file.
6. Snapshot-backed mode (`name:`) reuses `Record` + `determine_mode` +
   `BACKSPIN_MODE`; recording captures the reference, verifying compares actual
   against the stored reference snapshot.
7. The plur golden specs (single-failure, pending, aggregate) each collapse to a
   single `Backspin.compare` call with no stale-`.yml` deletion step.
8. No new filtering / snapshot / diff / matcher / result implementation — only a
   `compare` entry point plus the extracted `capture_command_snapshot` helper.
