# Changelog

## [Unreleased]

WIP: New unified API with `run` and `run!` methods that automatically record on first use and verify on subsequent runs

## [0.3.0] - 2025-06-05
- Scrub credentials from command arguments

## [0.2.0] - 2025-06-05
- First public release of Backspin, extracteed from `name-TBD` CLI tool

## [0.2.1] - 2025-06-04
- major refactoring, add support for `system` calls

## [0.1.0] - 2025-06-02

### Added
- Initial (internal) release of Backspin
- `record` method to capture CLI command outputs
- `verify` and `verify!` methods for output verification
- `use_cassette` method for VCR-style record/replay
- Support for multiple verification modes (strict, playback, custom matcher)
- Multi-command recording support
- RSpec integration using RSpec's mocking framework