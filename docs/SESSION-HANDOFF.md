# Handoff — 2026-09-02

Written at the end of a session the user stopped trusting, for whoever picks this
up next. Every claim below has the command that proves it. Run them; do not take
this document's word for anything.

The user's words, and the reason this file exists: *"ti ho chiesto di controllare
comando per comando per evitare appunto di dover far uscire release successive e
ora sbagli di nuovo."* That is a fair description of what happened. Read
[What went wrong](#what-went-wrong) before doing anything, because the mistake is
easy to repeat.

---

## State, as of this file

```
repo          /Users/eugeniozamengopontrelli/Raccoon   branch main, tree clean
origin/main   2 commits behind local: ea06aff and this file (see "Open work")
VERSION       0.18.0
brew          rcc 0.18.0, tap thousandflowers/homebrew-raccoon at v0.18.0
releases      v0.18.0 (published), v0.16.0. v0.17.0 is an orphan tag: its CI
              failed and nothing was ever published under it.
extension     raycast-extension/, 21 commands, author "eugenio", 165 tests pass,
              lint and build green. NOT published to the Raycast store.
```

A `ray develop` process may still be running (`pgrep -fl 'ray develop'`). It was
started by the previous session. Killing it is safe.

---

## Open work, in priority order

### 1. One commit is unpushed

`ea06aff` — fixes `network --json` printing the connection count twice. It is a
real bug that reaches users. The user was asked whether to push and tag 0.18.1
and did not answer; **do not push or tag without asking again.**

```sh
git log --oneline origin/main..HEAD    # ea06aff, plus the commit adding this file
```

### 2. 0.18.0 ships two known-bad `--json` emitters

Both are fixed in the working tree, neither is in the released binary. Anyone who
installs `rcc` from Homebrew today gets the broken ones.

| command | what breaks | when |
|---|---|---|
| `fonts` | reads `$HOME` under `set -u`; aborts with zero output | the caller does not pass HOME |
| `network` | prints `"connections": 0` then a bare `0` on the next line | `netstat` is not on PATH (`/usr/sbin` missing) |

Both were reported by the user as Raycast errors saying *"upgrade with brew
upgrade rcc"* — on a machine already running the newest release. That misleading
message is itself fixed (see `raycast-extension/src/json-out.ts`).

Reproduce the shipped bug:

```sh
env -i PATH=/opt/homebrew/bin:/usr/bin:/bin NO_COLOR=1 \
  /opt/homebrew/bin/rcc fonts --json | wc -c        # 0 bytes on 0.18.0
env -i PATH=/usr/bin:/bin HOME="$HOME" NO_COLOR=1 \
  /opt/homebrew/bin/rcc network --json | tail -3    # stray 0 on 0.18.0
```

The same commands against `./rcc` in the repo produce valid documents.

**A 0.18.1 is needed before the extension goes to the store**, because store
users install `rcc` from Homebrew and would hit exactly these two errors. The
user has not agreed to that release yet.

### 3. The Raycast extension is not published, and one thing blocks it

```
README.md      done
CHANGELOG.md   done, Raycast {PR_MERGE_DATE} format
author         "eugenio" — verified: raycast.com/eugenio is the user's profile
icon           512x512, the user's own drawing — READ ONLY, see Constraints
metadata/      EMPTY  <-- the blocker
```

Screenshots must be taken with Raycast's own **Window Capture** command while the
extension runs in development mode; it writes correctly sized PNGs into
`metadata/`. Hand-made screenshots are the wrong size and the review rejects
them. Only the user can take them.

Publishing is `npm run publish` from `raycast-extension/`. It opens a pull
request against `raycast/extensions` using the user's Raycast authentication and
goes through a human review. **You cannot run it for them.**

The release pipeline does not touch the extension:

```sh
grep -c raycast .github/workflows/release.yml    # 0
```

`brew upgrade` ships the CLI and the Go TUI. The extension is a separate channel.

---

## What went wrong

The previous session verified every command like this:

```sh
./rcc "$c" --json | python3 -c 'import json,sys; json.load(sys.stdin)'
```

from an interactive shell with a full environment, and reported "19/19 valid"
twice. Raycast spawns commands with a **trimmed environment** — its own PATH, no
guarantee of `HOME`. Neither bug is visible from a normal shell. The verification
was real work that measured the wrong thing, and it was reported as proof.

The correct check exists now and is the one to trust:

```sh
bats tests/test_json_hostile.bats
```

It runs every command that implements `--json` under four environments (full, no
HOME, empty HOME, only system directories on PATH) and refuses any document
containing a bare number on its own line — the shape of the `network` bug, not
just its instance.

There is a stronger check that is **not** in the suite, because it needs Node and
the extension's sources. It feeds each captured output to the extension's own
parser rather than a generic JSON check, so it catches schema drift as well as
syntax. It lived in a session-scoped scratch directory and is gone. Rebuilding it
is worth doing before touching any `--json` emitter: capture `rcc <cmd> --json`
in each environment, then `import` the matching `parse*` from
`raycast-extension/src/<cmd>-json.ts` and call it on the captured text. Last run:
76 cells, 0 failures.

### Traps this repository has already taught, twice

- **`grep -c` prints `0` and exits 1** when it matches nothing, so `|| printf '0'`
  prints a second one. `lib/audit/checks.sh:344` carries a comment explaining
  this; `bin/network.sh` did it anyway. Search for the shape before adding one.
- **zsh does not word-split unquoted variables.** `for c in $CMDS` runs once with
  the whole string. This produced a false "everything passes" in this session and
  a false diagnosis in an earlier one.
- **`set -u` and `$HOME`.** A spawned process may not have it.
- **`set -e` is inherited by subshells.** One unguarded failing command inside a
  backgrounded loop kills it silently — this is how the sudo keepalive died and
  produced a second Touch ID prompt part way through an audit.
- **`LC_ALL=C` makes `${#s}`, `printf '%-Ns'` and `tr` count and substitute
  bytes**, which cuts multi-byte box characters in half.
- **Raycast binds Enter to the first action in the panel**, whatever shortcut that
  action carries. Ordering is a safety property, not cosmetics.

---

## Constraints the user has stated

These are not preferences. They were given as rules.

- **No push, no PR, no tag, no release, no publishing** without the user saying so
  in a separate message, each time.
- **`raycast-extension/assets/extension-icon.png` is read only.** It is the
  raccoon the user drew, 512x512, the only copy, no vector source. Do not
  overwrite, move or rename it.
- **Never run `bin/fleet.sh` with no arguments.** With no subcommand it starts an
  audit and attempts SSH connections to real machines. Read the dispatch first.
- **Never delete what you did not create.** Archive with `mv`.
- Answers in Italian; code, commits and identifiers in English.
- Verify by running the thing, not by reading it. "It looks right" is not done.

---

## How to check any claim in this file

```sh
cd /Users/eugeniozamengopontrelli/Raccoon

git log --oneline origin/main..HEAD      # unpushed work
cat VERSION                              # 0.18.0
rcc --version                            # what the user actually runs
bats tests/test_json_hostile.bats        # the four hostile environments
bats tests/                              # full suite, 8-10 min: audit calls
                                         # softwareupdate and it is slow

cd raycast-extension && npm test && npm run lint && npm run build
ls metadata/                             # empty until the user takes screenshots
```

The full bats suite was last green at 512 tests, 0 failures, before `ea06aff`.
Run it again rather than believing that.
