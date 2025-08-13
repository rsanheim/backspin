# Changelog

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