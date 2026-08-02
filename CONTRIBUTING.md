# Contributing

Raccoon is a focused, zero-dependency macOS toolkit. PRs welcome for:

- **New audit checks** — follow the pattern of the existing checks in `lib/`
- **New `rcc` commands** — see the `rcc` entrypoint and `lib/`
- **Bug fixes** — open an issue first for anything non-trivial

## Guidelines

- **Keep it dependency-free.** Pure Bash, runs on the system Bash (3.2 → 5.x). No Homebrew required to run.
- **Stay shellcheck-clean.** Run `shellcheck` on any script you touch.
- **Add a bats test.** Tests live in `tests/`; run the suite before opening a PR.
- One change per commit, with a clear message.

Dev tools: `brew install bats-core shellcheck`.

## The Go TUI

The interactive menu lives in `ui/` (Go) and is optional — `rcc` works without it.
Build it only if your change touches the TUI.

## Releases

Tagged releases publish the `rcc` binary and bump the Homebrew tap
(`thousandflowers/homebrew-raccoon`). Maintainer-only; no manual steps for contributors.

## Questions

Open an issue or a discussion on GitHub.
