# Changelog

## 0.12.0
* Added `BACKSPIN_MODE` environment variable to globally override recording mode (`auto`, `record`, `verify`).
* Explicit `mode:` kwarg still takes highest precedence, followed by the env var, then auto-detection.
* Added configurable logger to `Backspin::Configuration` (defaults to WARN level, logfmt-lite format, and can be disabled with `config.logger = nil`).

## 0.11.0 - 2026-02-11
* Added immutable top-level `first_recorded_at` metadata for record files.
* Added mutable top-level `recorded_at` metadata that updates on each successful re-record.
* Added top-level `record_count`, incremented on each successful record write.
* Bumped record format to 4.1; loading remains backward-compatible with 4.0 record files.

## 0.10.0 - 2026-02-11
* Added `filter_on` to `Backspin.run` and `Backspin.capture` (`:both` default, `:record` opt-out).
* Changed default filter behavior: `filter` now applies during verify comparisons/diffs when `filter_on: :both`.
* Matcher callbacks now receive mutable copies of comparison data so in-place mutations do not mutate snapshots.
* Snapshot serialization is now immutable: `Snapshot#to_h` returns a frozen representation built at initialization.

## 0.9.0 - 2026-02-11
* Breaking: `Backspin.run` and `Backspin.capture` now return `Backspin::BackspinResult` with explicit `result.actual` / `result.expected` snapshots.
* Breaking: result convenience accessors (`result.stdout`, `result.stderr`, `result.status`) were removed in favor of snapshot access.
* Breaking: record format bumped to 4.0 and now persists a single `snapshot` object (v3 records are rejected).
* Simplification: removed legacy `Command`, `CommandResult`, and `RecordResult` layers; matcher/diff now operate directly on snapshots.
* Updated project docs to reflect the BackspinResult + Snapshot API surface.

## 0.8.0 - 2026-02-05
* Breaking: new `Backspin.run("command", name:, env:)` command API plus block capture via `Backspin.run(name:) { ... }` and `Backspin.capture("name") { ... }`
* Breaking: remove `run!` and `:playback`
* Breaking: drop RSpec dependency; verification failures raise `Backspin::VerificationError`
* Breaking: record format bumped to 3.0 and only `Open3::Capture3` / `Backspin::Capturer` records are accepted
* Scrub credential patterns apply to stdout, stderr, args, and env values

## 0.7.1 - 2025-12-02
* Include result object on VerificationError to make it easier for callers to debug verification errors

## 0.7.0 - 2025-08-13
* Breaking change: `Backspin.run` and `Backspin.capture` now raise an error if verification fails by default. Use `Backspin.configure` to opt-out. https://github.com/rsanheim/backspin/pull/18

## 0.6.0 - 2025-08-13
* Introduce `Backspin.capture` for rspec-less, simpler stdout/stderr testing https://github.com/rsanheim/backspin/pull/17

## 0.5.0 - 2025-06-11
* Simplify matcher API so user provided matchers override defaults - [#14](https://github.com/rsanheim/backspin/pull/14)
* Also extract a proper `Matcher` object

## 0.4.2 - 2025-06-10
Unified `:match` API for customizing how actual commands are matched against recorded commands. - [#11](https://github.com/rsanheim/backspin/pull/11)

## 0.4.0 - 2025-06-06

Simpler, unified API: `Backspin.run` and `Backspin run!` methods that automatically record on first use and verify on subsequent runs. `run!` will raise an error if results differ, whereas `run` will return the result for the caller to decide what to do with

## 0.3.0 - 2025-06-05
- Scrub credentials from command arguments

## 0.2.0 - 2025-06-05
- First public release of Backspin, extracteed from `name-TBD` CLI tool

## 0.2.1 - 2025-06-04
- major refactoring, add support for `system` calls

## 0.1.0 - 2025-06-02
- Initial (internal) release of Backspin
- `record` method to capture CLI command outputs
- `verify` and `verify!` methods for output verification
- `use_cassette` method for VCR-style record/replay
- Support for multiple verification modes (strict, playback, custom matcher)
- Multi-command recording support
- RSpec integration using RSpec's mocking framework
