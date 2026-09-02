# Handoff — 2026-09-02, 04:30

Replaces the handoff of the same name written at the start of this session
(commit `639a799`, still in history). Everything that one listed is done: its
two unpushed commits are on `main`, its two known `--json` bugs shipped in
0.18.1, and `metadata/` is no longer empty.

Every claim below has the command that proves it. Run them.

---

## State

```
repo        /Users/eugeniozamengopontrelli/Raccoon
branch      fix/backup-counts-local-snapshots  (5 commits, pushed, PR #60 open)
main        51b3fd0 — merge of PR #59, matches origin/main, tree clean
released    v0.18.1, verified: brew upgrade gives 0.18.1 and the fixes are
            present in the installed binary
store       raycast/extensions#30701 — no longer a draft, in review
```

---

## What this session was about

It began with `rcc fonts` failing in Raycast — `Expected double-quoted property
name in JSON at position 254` — on a machine already running the newest
release, having already been told once that the emitter was fixed.

**One bug class explains nearly all of it: a report answering from the wrong
place, stated with the confidence of a measured answer.** Six instances, all
shipped, none caught by a test:

1. `fonts` read two of four font directories and printed the sum as
   `installed`. 812 where the truth was 1184.
2. `fonts` took 14.8s (an `fc-scan` per file), past the ten seconds `useExec`
   allows, so Raycast killed it mid-document and the extension blamed rcc for
   the fragment.
3. `disk` and `backup` never looked for local APFS snapshots. Two dozen held
   space the author believed he had freed.
4. `trash` read `~/.Trash` alone; a file deleted on an external volume was
   counted nowhere.
5. `history` looked for fish in `~/.local/share/fish/history/default` — a path
   no version of fish writes — and reported 0 as confidently as zsh's 1463.
   Fixing the path was not enough: fish writes two lines per command.
6. The backup screen read the external destination, found none, and titled
   itself **"This Mac has never been backed up"** on a machine holding 24
   hourly Time Machine snapshots from the day before.

The Raycast extension went from nine commands with no screen to zero, under one
rule: **opening a screen does not act.** `apps` opens in `--dry-run`; `fleet`
reads its config file and contacts nothing.

---

## Open work, in priority order

### 1. An audit was left running. Its results are not in this document.

A Workflow was auditing the twelve commands never examined for that same bug
class — `network`, `ports`, `memory`, `docker`, `xcode`, `env`, `wifi`,
`overlap`, `battery`, `ssh`, `certs`, `startup` — with three adversarial
verifiers per finding. It had not finished when the session ended.

```
runId    wf_46177378-729
script   ~/.claude/projects/-Users-eugeniozamengopontrelli-Raccoon/
         a3c406cf-fde3-469a-b2b3-27bf6ea533dc/workflows/scripts/
         raccoon-wrong-place-audit-wf_46177378-729.js
journal  ~/.claude/projects/-Users-eugeniozamengopontrelli/
         a3c406cf-fde3-469a-b2b3-27bf6ea533dc/subagents/workflows/
         wf_46177378-729/journal.jsonl
```

Read the journal first — it records each agent's actual return value. Resume
with `Workflow({scriptPath, resumeFromRunId: "wf_46177378-729"})`; completed
agents return from cache.

**Why this matters more than it looks.** Nine of twenty-one commands were
audited by hand earlier in the session, and **five of those nine were wrong**.
Twelve remain unexamined. At that rate there is more there.

The method is the point and is not optional: **audit by measuring, not by
reading.** All six bugs above lived in code that reads as correct and had green
tests. Run the command, ask macOS the same question independently, compare the
two numbers.

### 2. PR #60 is open

Five commits: the backup screen fix, the fish history fix, the CI time fix, and
two moving a spare icon out of the extension folder.

```sh
gh pr view 60 && gh pr checks 60
```

CI was green on the first three; the last two were pushed after and need
re-checking before merge.

### 3. Three screens have never been opened by a human

`Upgrade`, `Audit History`, `Scheduled Audit`. Built, typechecked, parsers
tested — but nobody has looked at them. `Fleet` and `Apps`, the two that could
do damage, were verified another way: the compiled bundle's `fleet.tsx` block
contains zero occurrences of `useRccStream`, `useExec`, `runRcc`, `streamRcc`,
`spawn` or `execFile`.

```sh
cd raycast-extension && npm run dev
```

### 4. The store submission is in review

`raycast/extensions#30701`. Raycast's team responds in days. Their requests are
satisfied by a commit here followed by another `npm run publish` — which copies
a **snapshot**, so anything committed after a publish is absent from the PR
until you publish again. That caught this session once.

Six screenshots in `metadata/`, all 2000×1250. The first is the audit of this
Mac and shows Stealth Mode off, Bluetooth on, ports open — the third being
Remote Login. Flagged twice; the author chose to keep it.

---

## Things this repository has now taught twice

- **`grep -c` prints `0` and exits 1** when it matches nothing, so under `set -e`
  it takes the script with it. `lib/audit/checks.sh:344` carries a comment;
  `bin/network.sh` and `bin/history.sh` did it anyway.
- **Two implementations of one answer will drift.** `fonts` and `history` each
  had separate text and `--json` paths; both were wrong about the same thing,
  and the first fix landed in only one of them.
- **"Could not check" is not "none".** Without `diskutil` the snapshot count is
  0 either way, and on a full disk those are opposite answers.
- **A skipped test proves nothing.** The external-volume trash test skipped
  itself when `/Volumes` was not writable. The root is a parameter now.
- **A test that assumes its environment fails only in CI.** The unskipped
  software-update test inherited `RCC_SKIP_SOFTWARE_UPDATE` from the workflow
  env. It unsets it explicitly now.
- **Do not edit files while a test suite runs.** A `bats` run mid-edit produced
  a false failure on `disk` that cost twenty minutes.
- **`ray develop` stops rebuilding, silently,** when two source files share a
  basename (`audit-history.ts` and `audit-history.tsx`). No error; the build
  just stays at an old timestamp. Renaming fixed it.
- **Raycast store screenshots must be exactly 2000×1250** and `ray lint`
  enforces it. Window Capture is not required: a macOS window capture is
  1724×1174 with a transparent surround, so scaling the whole window and
  centring it on a 2000×1250 canvas distorts nothing. Resizing directly does —
  1.47 against 1.60.
- **CI cost 17 minutes for one line.** `softwareupdate -l` was 14m43s of it,
  paid twice per release. `RCC_SKIP_SOFTWARE_UPDATE` now makes that check report
  "Not checked" — never "Up to date".

---

## Constraints the author has stated

Not preferences. Rules.

- **No push, no PR, no tag, no release, no publishing** without being told so in
  a separate message, each time.
- **Branch and PR, never straight to `main`**, even though `main` is unprotected.
  To move commits already made locally: `git switch -c <branch>` then
  `git branch -f main origin/main`. Never `reset --hard`.
- **`raycast-extension/assets/extension-icon.png` is read only.** The author's
  own drawing, 512×512, no vector source.
- **Never run `bin/fleet.sh` with no arguments.** It starts an audit and SSHes
  to real machines.
- **Never delete what you did not create.** Archive with `mv`.
- Answers in Italian; code, commits and identifiers in English.
- **No markdown tables in replies.** Prose or lists.
- Verify by running the thing. "It looks right" is not done.

---

## How to check any claim here

```sh
cd /Users/eugeniozamengopontrelli/Raccoon

git log --oneline origin/main..HEAD     # the 5 unmerged commits
gh pr view 60 && gh pr checks 60
rcc --version                           # 0.18.1, from Homebrew
bats tests/                             # 531 tests; ~2 min now, was ~17
shellcheck -S warning -x rcc bin/*.sh lib/core/*.sh lib/audit/*.sh

cd raycast-extension
npx tsc --noEmit && npm run lint && npm test && npm run build
ls metadata/                            # six PNGs at 2000x1250
```

The check that found the real scale of the original bug is **not in the
repository**. It runs every `--json` command under five environments and feeds
each result to the extension's own parser rather than a generic JSON check, so
it catches schema drift as well as syntax:

```
/private/tmp/claude-501/-Users-eugeniozamengopontrelli/
  a3c406cf-fde3-469a-b2b3-27bf6ea533dc/scratchpad/parser-matrix.ts
```

Copy it into `raycast-extension/`, run `node parser-matrix.ts <path-to-rcc>`,
remove it after. Last run: 90 cells, 0 failures against the repo; 9 failures
against the released 0.18.0, where only 2 were known. **It belongs in the
repository.** It has been lost once and rebuilt once.
