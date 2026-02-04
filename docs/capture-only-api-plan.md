# Capture-first run API plan

## Analysis
- Current API splits behavior: `Backspin.run` uses RSpec mocks to stub `Open3.capture3`/`system` and record per-command outputs, while `Backspin.capture` uses FD-level redirection to capture all stdout/stderr from a block.
- PR #17 details: capture was implemented by redirecting `$stdout`/`$stderr` to tempfiles, recording a single `Backspin::Capturer` command with an `args` marker (e.g., `"<captured block>"`) and `status` `0`, and returning the block result.
- New target API keeps a CLI-first path without mocks:
  - `Backspin.run("command here", name: "record-name", env: {"MY_ENV_VAR" => "value"})` runs `Open3.capture3` directly and records stdout/stderr/status.
  - also support Backspin.run(["command", "here"], name: "record-name")
  - capture3 supports _both_ argument forms, and the string form invokes a shell, while the array form does not.
    - our examples should prioritize the array form, as it is safer and generally recommended
  - NOTE: if 'env' is NOT provided, we do not record the env hash or pass it to capture3
  - `Backspin.run(name: "record-name") { ... }` uses the tempfile capture approach and records a single `Backspin::Capturer` entry.
  - `Backspin.capture("record-name") { ... }` is a thin alias to the block form of `run` that uses the tempfile capture approach - note that we don't support the 'name:' keyword here, as there is no reason to (this does not support command args)
- Records remain type-specific: command runs store `Open3::Capture3` entries (args preserved as passed, env hash included if provided); block capture stores a `Backspin::Capturer` entry with the args marker and `status` placeholder `0`.
- Playback is removed; block capture can run multiple commands but records them as a single combined stdout/stderr snapshot.
- Backwards compatibility is explicitly not required, so we can break signatures, record formats, and drop Open3/system stubbing entirely.
- Output, args, and env values MUST be scrubbed using the existing credential scrub patterns (defaults plus user-provided additions).

## Decisions
- Remove `:playback` support.
- Keep `status` as a placeholder (`0`) for block capture; only command runs have meaningful exit status.
- Keep the `"<captured block>"` args marker for capture records.
- Require `name:` keyword for `run`; `capture` uses a positional record name.
- Keep `Backspin.capture` as an alias to the block form of `run` (positional only).
- Make `run` strict by default and remove `run!`.
- Bump `Record::FORMAT_VERSION` and hard-reject legacy records.
- Always scrub stdout/stderr, args, and env values using the current credential patterns (defaults + user-provided).
- Keep `raise_on_verification_failure` supported (default `true`) and cover it with a spec.
- Preserve the existing matcher contract (Proc, hash with fields, and `:all`) for both command and block capture paths.

## Plan
- [x] Define the public API signature and behavior for the dual-mode `run` and the `capture` alias, including `env:` handling and the removal of `:playback`.
- [x] Add high-level integration specs for the new API (command run + `env:`, block capture, capture alias, strict verification failure, and `raise_on_verification_failure` behavior) to drive implementation.
- [x] Remove RSpec runtime dependency (`rspec-mocks`) and strip all mocking/stubbing paths from `Recorder`.
- [x] Implement the command run path using `Open3.capture3` directly, recording a single `Open3::Capture3` command and verifying against it.
- [x] Implement the block capture path using the tempfile redirection, recording a single `Backspin::Capturer` command with `status` placeholder `0` and the args marker.
- [x] Update record loading and validation to accept only `Open3::Capture3` and `Backspin::Capturer`, bumping `Record::FORMAT_VERSION` and rejecting older formats.
- [x] Update docs (`README.md`, `MATCHERS.md`) to show the new `run("command", name:, env:)` and block capture usage, document strict `run`, and note the placeholder `status` for block capture.
- [x] Update the remaining tests and fixtures: remove `run!` specs, remove multi-command/playback specs, and refresh fixtures for the new signatures.
- [x] Cleanup/refactor pass: delete legacy API paths, remove unused code, and verify docs/tests only reference the new API.
- [x] Update `CHANGELOG.md` with the breaking API change and bump version accordingly.

## Follow-up Spec Coverage
- [ ] Rebuild coverage for behavior formerly tested via mock-based specs, rewritten for the new API surface:
  - Command verification edge cases (record missing, format mismatch, command type mismatch).
  - Matcher error paths and failure reasons (proc/hash/:all with failing branches).
  - Record filters and custom matchers in both command and block capture paths.
  - Record loading errors (invalid YAML, missing keys) and clearer error messages.
  - Scrubbing behavior across command args + env + captured block output.
- [ ] Add a small set of focused negative tests to ensure we reject unsupported modes (`:playback`) and legacy formats consistently.
