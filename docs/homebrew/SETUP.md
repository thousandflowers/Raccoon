# Homebrew tap - thousandflowers/homebrew-tap

`rcc` installs from the tap shared by every CLI in this account:

```bash
brew install thousandflowers/tap/rcc
```

## Why one tap

rcc used to have its own, `thousandflowers/homebrew-raccoon`. Four projects
meant four taps, four release workflows pushing to four places, and any tap
that stops being bumped keeps serving an old version without saying so -
canary's tap did exactly that for months after canary became a Go binary.

`thousandflowers/homebrew-raccoon` still exists and still resolves: it carries
a `tap_migrations.json` that moves anyone who installed from it over to
`thousandflowers/tap` on their next `brew update`. Nobody has to reinstall, and
`brew install thousandflowers/raccoon/rcc` still works.

## How a release bumps the formula

`.github/workflows/release.yml` does it on a `v*` tag:

1. run CI (shellcheck + bats)
2. create the GitHub Release from the CHANGELOG section for that tag
3. compute the SHA256 of the source tarball
4. clone the tap, rewrite the url and sha256 in `Formula/rcc.rb`, push

## The token

The workflow needs the `RACCOONTAPPUSH` secret on this repo: a fine-grained PAT
with **Contents: write** on `thousandflowers/homebrew-tap`.

The tap is public, so a token without write access clones it perfectly well and
only fails at the push - by which point the tag is already published. The
workflow therefore asks GitHub whether the token can push *before* it clones,
and stops with a readable error if it cannot.

## Verify a release landed

```bash
brew update
brew info thousandflowers/tap/rcc   # should show the tag you just pushed
brew upgrade rcc && rcc --version
```
