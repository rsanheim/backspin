# Contributing

Ideas welcome. PRs cool. Just ensure your 
Backspin is in early development and the API _will_ change before stabilizing at 1.0.

## Development Setup

```bash
git clone https://github.com/rsanheim/backspin.git
cd backspin
mise install
mise exec -- ruby -v
bin/setup
# run full build
bin/rake spec
```

## Release Maintainer Setup

Setup, trusted publishing, workflow updates, verification, and recovery live in
[the shared release guide](https://github.com/rsanheim/.github#readme).

## Reporting Issues

### Bug Reports

When reporting bugs, please include *full logs* including:

1. full ruby version (`ruby -v`) 
2. Backspin version
3. reproduction code
4. Expected behavior vs actual behavior
5. Full error messages and stack traces
6. Relevant YAML record files if applicable (sanitized of sensitive data)

## Questions?

If you have questions about contributing, feel free to open an issue and holler
