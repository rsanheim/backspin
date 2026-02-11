# DummyCliGem Fixture

This is a minimal fixture gem used by Backspin's full-stack integration checks.

- It shells out to standard unix utilities (`echo`, `ls`).
- Its RSpec suite verifies command output through `Backspin.run`.
- Snapshot YAML records are stored in-repo under `spec/fixtures/backspin`.
