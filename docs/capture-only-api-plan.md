# Capture-first run API plan

## Analysis
- Current API splits behavior: `Backspin.run` uses RSpec mocks to stub `Open3.capture3`/`system` and record per-command outputs, while `Backspin.capture` uses FD-level redirection to capture all stdout/stderr from a block.
- PR #17 details: capture was implemented by redirecting `$stdout`/`$stderr` to tempfiles, recording a single `Backspin::Capturer` command with an `args` marker (e.g., `"<captured block>"`) and `status` `0`, and returning the block result.
- New target API keeps a CLI-first path without mocks:
  - `Backspin.run("command here", name: "record-name", env: {})` runs `Open3.capture3` directly and records stdout/stderr/status.
  - `Backspin.run(name: "record-name") { ... }` uses the tempfile capture approach and records a single `Backspin::Capturer` entry.
  - `Backspin.capture(name: "record-name") { ... }` is a thin alias to the block form of `run`.
- Records remain type-specific: command runs store `Open3::Capture3` entries (args preserved as passed, env hash included if provided); block capture stores a `Backspin::Capturer` entry with the args marker and `status` placeholder `0`.
- Playback is removed; block capture can run multiple commands but records them as a single combined stdout/stderr snapshot.
- Backwards compatibility is explicitly not required, so we can break signatures, record formats, and drop Open3/system stubbing entirely.

## Decisions
- Remove `:playback` support.
- Keep `status` as a placeholder (`0`) for block capture; only command runs have meaningful exit status.
- Keep the `"<captured block>"` args marker for capture records.
- Require `name:` keyword for `run` and `capture`.
- Keep `Backspin.capture` as an alias to the block form of `run`.
- Make `run` strict by default and remove `run!`.
- Bump `Record::FORMAT_VERSION` and hard-reject legacy records.

## Plan
1. Define the public API signature and behavior for the dual-mode `run` and the `capture` alias, including `env:` handling and the removal of `:playback`.
2. Add high-level integration specs for the new API (command run + `env:`, block capture, capture alias, strict verification failure) to drive implementation.
3. Remove RSpec runtime dependency (`rspec-mocks`) and strip all mocking/stubbing paths from `Recorder`.
4. Implement the command run path using `Open3.capture3` directly, recording a single `Open3::Capture3` command and verifying against it.
5. Implement the block capture path using the tempfile redirection, recording a single `Backspin::Capturer` command with `status` placeholder `0` and the args marker.
6. Update record loading and validation to accept only `Open3::Capture3` and `Backspin::Capturer`, bumping `Record::FORMAT_VERSION` and rejecting older formats.
7. Update docs (`README.md`, `MATCHERS.md`) to show the new `run("command", name:, env:)` and block capture usage, document strict `run`, and note the placeholder `status` for block capture.
8. Update the remaining tests and fixtures: remove `run!` specs, remove multi-command/playback specs, and refresh fixtures for the new signatures.
9. Cleanup/refactor pass: delete legacy API paths, remove unused code, and verify docs/tests only reference the new API.
10. Update `CHANGELOG.md` with the breaking API change and bump version accordingly.
