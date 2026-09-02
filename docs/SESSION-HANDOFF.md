# Handoff — 2026-09-02, morning

Replaces the handoff written at 04:30 the same day (commit `3b81d84`, still
in history). That one said nine of twenty-one commands had been audited and
five were wrong, and that twelve were unexamined. This session examined the
twelve — by measuring, not reading — and fixed what it found. Every claim
below has the command that proves it. Run them.

---

## State

```
repo        /Users/eugeniozamengopontrelli/Raccoon
branch      fix/backup-counts-local-snapshots  (PR #60 open; 12 commits
            ahead of origin/main; everything after c077c45 is NOT pushed — see "Not pushed")
main        51b3fd0 — matches origin/main, untouched this session
released    v0.18.1 (brew). Nothing tagged this session.
store       raycast/extensions#30701 in review. The fixes for its two red
            checks and four review findings are committed HERE and are not
            in the PR until `npm run publish` runs again.
```

## Not pushed, not published — on purpose

The author's rule: no push, no PR, no tag, no release, no publish without
being told in a separate message. So, when told:

```sh
cd /Users/eugeniozamengopontrelli/Raccoon
git push origin fix/backup-counts-local-snapshots      # updates PR #60
cd raycast-extension && npm run publish                # updates raycast/extensions#30701
```

`npm run publish` copies a snapshot of `raycast-extension/` into the fork's
`ext/raccoon` branch. The PR still holds `design/extension-icon-raccoon.png`
from before it was moved out; check after publishing that the copy removed it.

---

## What this session did

### The store PR (raycast/extensions#30701)

Two failing checks and four Greptile findings, all addressed (commit `9b11474`):

- **Prettier**: the monorepo has no `.editorconfig`, so CI reformatted all 90
  files to two spaces. `.prettierrc` now carries the tab style with the
  extension. Verify like CI does: `npx prettier --no-editorconfig --check "src/**/*.{ts,tsx}"`.
- **Screenshots**: five of six failed the padding check because the window sat
  at 6.5% from the top, outside the 8–17% band the validator scans. Recomposed
  from the original captures on the Desktop at 75% width, centred. Raycast's
  own validator (`scripts/check_raycast_images.py` from raycast/extensions,
  a copy is in this session's scratchpad) passes all six.
- **Login items** (P1, security): a name with an apostrophe ended the shell
  quote. AppleScript-quoted, then shell-quoted, with a test.
- **Upgrade** (P1): ran `rcc upgrade` on open. Opens in `--dry-run` now,
  through a shared `DryRunFirst` screen with `apps`.
- **Preferences** (P2): generated `Preferences` type; tsconfig includes
  `raycast-env.d.ts`.
- **Trash** (P2): kept as Finder — Raycast's `trash()` cannot empty the Trash.
  The docstring says so.

### The twelve commands, audited by measuring

Findings that survived a measured comparison, all fixed, each with a bats test
that measures rather than asserts exit 0. Per command, what was wrong:

- **ports** — 81 outbound connections labelled "Reachable", bulk kill offered
  on the browser and the shell (extension). lsof off PATH → "No ports found".
  lsof as a user hides root's sshd on 22 and did not say so.
- **memory** — ranked by RSS; the 23 GB process (56 MB RSS) never appeared.
  "Total RSS" double-counted shared pages. sysctl off PATH → "Total RAM 0 GB".
  Machine-wide figures now reach `--json`.
- **env** — Raycast screen audited the extension's 7-dir PATH, not the
  reader's 26. Symlinked PATH dir never descended. Empty tool version.
  Text/JSON duplicate rules disagreed.
- **network** — hardcoded nine interfaces (Tailscale's utun8 invisible).
  172.20.x "WireGuard". Firewall tool failure → "disabled". System proxies
  never read. AirPlay/rapportd/networkserviceproxy misidentified. "14/10 scans".
- **xcode** — `installed` = `command -v xcrun`, always true. Two simulator
  implementations (10 vs 15 vs 17). Vision Pro filtered out. DerivedData
  counted itself.
- **docker** — RECLAIMABLE in `size`; "hours" as status; header as a row;
  daemon down = "No images found" under a tick.
- **certs** — 13/42 names mangled and PATH-dependent; delete by name hit a
  valid cert sharing the expired one's name; local-vs-GMT expiry; `--expiring`
  listed valid certs; nonexistent keychain in the list.
- **wifi** — link up with SSID withheld = "Not connected"; tools off PATH →
  "no networks", exit 0; bulk forget promised to keep a network it could not
  identify.
- **startup** — labels were filename fragments (every bootout wrong); 539
  "running" of which 352 idle; System Events refused = "no login items";
  SMAppService background items unlisted; dead login item marked as opening.
- **battery** — "0 cycles, 0% (poor)" in text when unmeasured; "on battery"
  for a MacBook on AC holding its charge; README promised temperature.
- **ssh** — measured (one key; passphrase, perms, .pub all agree with
  ssh-keygen and stat). No finding. Caveat unmeasured here: a hardware key
  (`-sk`) always fails `ssh-keygen -y` and would read as "no passphrase: no".
- **overlap** — 35 vs 34 clashes against an independent count (one
  edge: a doc dir under /Library/TeX/texbin). Fifty `/usr/bin` symlinks into
  `/System/Library` read as orphans; attributed to `system` now, CLT/Xcode to
  `xcode`, MacTeX to `tlmgr`. The remaining 400 orphans are XQuartz, Mono
  and pip --user: genuinely unmanaged.

One shared mechanism: `rcc_require_tools` in `lib/core/common.sh`. A tool
missing from PATH is exit 3 with a message and NO document on stdout. The
extension shows the message. `scripts/parser-matrix.ts` counts these as
"declined", not failures.

### JSON shape changes (the extension reads both old and new)

`memory` is now an object (`memory` + `processes`, `footprint_kb`/`rss_kb`);
`startup.user_agents` are objects with `label`; `certs` rows carry
`keychain`/`sha256`; `wifi` has `connected`/`ssid_hidden`; `battery` has
`power_source`; `docker.space` has `total`/`active`; `xcode` has
`developer_dir`. Listed in CHANGELOG.md under Unreleased. This is a 0.19.0.

---

## Open, in order of value

1. **Publish and push** (above), when told. Then re-run the store checks on
   the PR and answer Greptile if it re-reviews.
2. **PR #60** now carries 12 commits and is no longer about backups. Merge as
   is or split; the author decides.
3. **Three screens never opened by a human**: Upgrade (now dry-run first),
   Audit History, Scheduled Audit. `cd raycast-extension && npm run dev`.
4. **A stale launchd job from the test suite**: `com.raccoon.audit` is loaded
   in gui/501 from a plist in a deleted bats temp HOME (program =
   this repo's bin/audit.sh). The tests bootstrap it and never boot it out.
   `launchctl print gui/$(id -u)/com.raccoon.audit | grep path` shows it.
   Not removed this session — not this session's to remove. The test that
   loads it should `launchctl bootout` in teardown.
5. **Not done, known**: wifi link quality (channel, RSSI) is in
   system_profiler and not in the report; `network.dns` flattens supplemental
   resolvers; `docker` says nothing about orphaned Docker Desktop state when
   the CLI is gone; `startup --clean` still prompts interactively.

---

## How to check any claim here

```sh
cd /Users/eugeniozamengopontrelli/Raccoon
git log --oneline origin/main..HEAD          # 12 commits
bats tests/                                  # ~600 tests
shellcheck -S warning -x rcc bin/*.sh lib/core/*.sh lib/audit/*.sh
cd raycast-extension
npx tsc --noEmit && npm run lint && npm test && npm run build
npx prettier --no-editorconfig --check "src/**/*.{ts,tsx}" "scripts/*.ts"
npm run test:matrix -- /Users/eugeniozamengopontrelli/Raccoon/rcc   # 90 cells
```

Measure, do not read. The method that found all of this:

```sh
./rcc ports --json | jq '[.[]|select(.state=="LISTEN" and (.address|startswith("*:")))]|length'
netstat -an -p tcp | awk '$NF=="LISTEN" && $4 ~ /^\*\./' | wc -l         # must agree
./rcc memory --json --top 1 | jq '.processes[0].pid' | xargs -I{} sh -c 'top -l1 -o mem -n1 -stats pid | tail -1; echo {}'
./rcc startup --json | jq -r '.user_agents[]|select(.loaded)|.label' | xargs -I{} launchctl print gui/$(id -u)/{} >/dev/null && echo "every label exists"
env -i PATH=/usr/bin:/bin HOME=$HOME ./rcc network --json; echo "exit=$? (must be 3)"
```

---

## Constraints the author has stated

Not preferences. Rules.

- **No push, no PR, no tag, no release, no publishing** without being told
  so in a separate message, each time.
- **Branch and PR, never straight to `main`.** Never `reset --hard`.
- **`raycast-extension/assets/extension-icon.png` is read only.**
- **Never run `bin/fleet.sh` with no arguments.** It SSHes to real machines.
- **Never delete what you did not create.** Archive with `mv`.
- Answers in Italian; code, commits and identifiers in English.
- **No markdown tables in replies.**
- Verify by running the thing. "It looks right" is not done.
