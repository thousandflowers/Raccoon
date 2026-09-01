# Changelog

All notable changes to Raccoon are documented here.
Format: [Keep a Changelog](https://keepachangelog.com) · Versioning: [SemVer](https://semver.org)

## [0.18.0] - 2026-09-01

0.17.0 was tagged and never released. Its CI failed on three tests asserting
that eight commands refuse `--json`, which the same release had just taught them
to answer, so the job that publishes never ran and the tap stayed on 0.16.0.
Nothing reached anyone under that tag, so everything 0.17.0 prepared ships here
alongside the work that followed it.

### Added

- **Every command that produces a report answers `--json`.** Twenty-one of the
  twenty-two: `backup`, `certs`, `disk`, `docker`, `env`, `fonts`, `git`,
  `history`, `network`, `ssh`, `startup` and `xcode` joined the nine that
  already did. `apps` is the exception and stays one on purpose — like
  `upgrade` it streams `__RCC_PROGRESS__` markers because it is an action, not
  a report, and its output is not clean text to begin with.

- **The `curl | bash` installer draws the raccoon while it works.** Same face
  the TUI draws, four eye shapes, one caption per step. It degrades on purpose:
  a pipe, a CI log or a terminal that cannot move the cursor gets plain lines,
  decided by `[[ -t 1 ]]`, and nothing in it is required for the install.

- **The Raycast extension answers two keystrokes in all nineteen views.** Enter
  resolves the row under the cursor, Cmd+Enter resolves everything on screen.
  What resolving is differs per command: quit that process, close that port,
  stop that login item, forget that network, remove that dangling symlink or
  that expired certificate, push that clean repository, add a passphrase to that
  key, delete DerivedData, empty the trash — or, where nothing is put right by a
  command, open the one place the setting actually lives. Before this, five
  views did something on Enter and fourteen only reloaded, including on rows
  drawn in red.

- **A view per command, built for what that command reports.** Nineteen of
  them, none a table: colour means one thing everywhere (red needs doing now,
  orange deserves attention, green is in order, grey is information), and each
  list is grouped and ordered by what the reader came for. `git` ranks by where
  the work exists rather than how much there is — two commits that were never
  pushed outrank four hundred uncommitted files. `ssh` ranks by what the finding
  costs. `backup` says the answer in its first line.

- `rcc audit --fix-only NAMES` fixes the named checks and nothing else.
  `--only` takes groups, and the smallest group holds six checks, so a caller
  with one finding in hand could not act on it without changing five
  neighbours. `fix_issue` was already keyed by check name; the flag was the
  missing piece. Comma-separated, matched case-insensitively, and an unknown
  name fixes nothing rather than falling back to everything.
- `rcc docker --json`. It reports three states the text collapsed into one
  line: no Docker, Docker installed with the daemon stopped, and Docker
  running with its images, containers, volumes and reclaimable space.
- The Raycast extension has purpose-built screens for `audit`, `battery`,
  `memory`, `ports`, `trash`, `wifi`, `overlap` and `docker` instead of the
  raw text report, and the launcher opens them. Enter on a finding runs its
  fix in Terminal, where sudo has a tty to ask on; Cmd+Enter fixes everything
  on screen.

- The Raycast extension's `audit` command is a list of checks instead of a wall
  of text. It reads `rcc audit --json`, which it had never done, and gives one
  selectable row per check with the report's own status deciding the colour;
  the panel beside it is fields rather than prose, carrying the category, the
  finding, the CIS reference where there is one, and the command that verifies
  it by hand. Per row: copy that command, copy the reference, and add the check
  to `~/.raccoon/audit.conf` so the audit stops offering to fix it, which is
  offered only where a fix exists and is gone once used. Nothing is shown that
  would do nothing: a Mac with nothing wrong reports no fixable checks at all,
  which is the ordinary case, and the thirty rows are all still there.
- Both Raycast integrations are under version control. They existed on one disk
  only, and the extension's icon was the sole copy of a drawing with no vector
  source.
- Each result of `rcc audit --json` carries `fix_available`. It answers whether
  a fix exists for that check right now, not whether the check has one in the
  source, because the audit only offers a fix when there is something to change.

### Changed

- `rcc ssh` scans `~/.ssh` once. Its three checks each walked the directory and
  ran `ssh-keygen` from inside their own loop, so every key was read three times
  and the answers agreed by coincidence. The table's output is unchanged, down
  to the parenthesised `(ED25519)` it has always shown.

- `rcc git` builds its table from counts rather than a rendered sentence, which
  also drops the trailing `", "` every row used to carry unless it happened to
  end on a no-upstream count.

- `rcc fleet` with no subcommand now prints its subcommands instead of running an audit. The default was `audit`, so the shortest thing anyone could type opened SSH connections to every host in `~/.raccoon/fleet.conf` - the most invasive thing the command can do, reached by typing the least. **This is a visible change of behaviour**: a script with a bare `rcc fleet` in it will get the help text and do nothing. `rcc fleet audit` is unchanged and is how the audit is run. Every other command was checked for the same shape; the only other subcommand default is `rcc fleet group`, which falls back to `list` and reads nothing but a text file.
- The menu is four categories - Maintenance, System, Network, Development - and lists commands, not ways of launching them. The six flag forms of audit (`deep`, `quiet`, `fix`, `json`, `history`, `watch`) are out of it: a flag's place is `rcc audit --help` and the man page, where all six already were. `fleet` is one row that opens its five subcommands in place rather than five rows of the twenty-five, which is what made the first screen read as a fleet manager. `wifi` is in the menu at last: it has had a script since the beginning, its own animation since 0.16.0, and no way into the interface. Twenty-two rows, one per script in `bin/`, and the tests now check each list against the scripts that exist rather than against each other - comparing the two menus to one another is what let both of them go on missing `wifi`.
- `rcc ports` reports the local port. On a connected socket it reported the
  peer's: `172.20.10.3:51794->160.79.104.10:443` came back as port 443, which is
  Apple's, not one open here, and 92 of the 150 sockets on the machine this was
  found on were reported that way. The table got it wrong differently, returning
  a hextet out of `[fe80:e::479:7b38:ef37:a217]:56122` as if it were a port. It
  also showed three rows out of a hundred and fifty, because `sort -u` keyed on
  the rendered line whose first field is the border. Anyone parsing that output
  was parsing wrong numbers, which is why this is here rather than under fixes.
- `rcc audit --json` and `rcc memory --json` print JSON and nothing else. They
  printed the human report first and appended the JSON to the same stdout: valid
  JSON started at line 66 of 96 for audit, and the machine invocation was
  `--json --quiet` with nobody having written that down. `--quiet` still means
  what it meant.
- `certs`, `disk`, `docker`, `fonts`, `history`, `network`, `startup` and `xcode`
  refuse `--json` with exit 64 instead of accepting it and printing the human
  report. The flag was parsed and advertised in their help, and the branch was
  empty: it did nothing at all, in silence, for six releases. The refusal says
  "not implemented yet" rather than "unknown option", because the flag is coming.
  64 is EX_USAGE and deliberately not 2, which audit and fleet already spend on
  "warnings only".

- `rcc --help` lists the same twenty-eight commands in the new order. The order is one editorial decision, not two, so it follows the menu; the format is unchanged, two columns and no category rows, which is what `raycast/generate.sh` parses. Regenerating produces the same twenty-eight script commands byte for byte.

### Fixed

- **`rcc audit` asked for Touch ID a second time, part way through the report.**
  Two defects in a row. `start_sudo_keepalive` runs its refresh loop in a
  subshell, a subshell inherits the caller's shell options, every script that
  starts it runs `set -euo pipefail`, and the `sudo -n true` inside the loop was
  unguarded — so one failed refresh killed the whole keepalive without printing
  anything. The timestamp then ran out mid-run and `_sudo` called plain `sudo`,
  which prompts. Under a caller that owns the terminal it now asks
  non-interactively and degrades: the remaining root checks are skipped and say
  so, which is a worse report than a full one but an honest one, and it cannot
  hang behind a screen nobody is looking at.

- **The sudo handover looked like a crash.** sudo needs the real terminal —
  Touch ID and the password prompt only exist outside the alt screen — so the
  TUI has to step aside, and what replaced it was two lines of prose on a bare
  shell. It now draws the same face the TUI draws, in the same colour: the
  notice is rendered through the interface's own styles rather than a
  hand-written escape, which was bold white against a honey-gold menu.

- **The menu opened with nothing selected.** Row zero is the "Maintenance"
  heading, a label with nothing to run and no highlight, so the first Down
  keypress was spent landing on the first command instead of moving to the
  second. `g` and `G` already walked the cursor off a heading; startup, Esc out
  of search and backspace out of an empty search did not.

- `rcc battery` exited 1 and printed nothing on a Mac without a battery, and
  reported "fully charged: no" at 100% because `SPPowerDataType` prints
  `Charging:` twice and the record became two lines.

- `rcc git` crashed with `repos[@]: unbound variable` on a Mac with no
  repositories: in bash 3.2 an empty array expanded under `set -u` is unbound,
  not an empty list.

- The `fleet` box drew as a row of replacement characters. `LC_ALL=C` makes `tr`
  substitute bytes, which cuts multi-byte box characters in half, and makes
  padding count bytes rather than columns.

- `rcc certs` counted its steps two ways in the same run, printing `[1/3]` and
  then `[3/4]`.

- `rcc fonts --json` printed nothing at all on a Mac with no `~/Library/Fonts`.

- `rcc disk --json` never returned: the flag was parsed in a `while` loop with
  no `shift`, so it spun on its own argument.

- `rcc disk --help` did not mention the flag it had just been given.

- The demo GIFs named the software installed on the machine they were captured
  on. `rcc-startup.gif` listed Notion, Raycast, AutoRaise and DockDoor,
  `rcc-network.gif` named a VPN, `rcc-memory.gif` named a browser and a chat
  client, and `rcc-env.gif` listed nine Claude Code plugins by name, one of
  which is a health disclosure. None of it is a machine identifier, which is why
  every check passed: `docs/gif-helpers/preflight.sh` looked for usernames,
  hostnames and paths, and an inventory of installed software is none of those.
  It now carries a list of third-party names as well, matched case-insensitively
  and on word boundaries. `rcc-help.gif` also still printed `Raccoon version
  0.16.0`, having been captured in the same commit that raised VERSION, one step
  too early.

- `rcc battery` exited 1 and printed nothing on any Mac without a battery: a
  mini, a Studio, an iMac, or a CI runner. `pmset` prints no percentage there,
  so `grep` exited 1, `pipefail` propagated it and `set -e` killed the script
  one line before the defaults that existed for exactly that case. Text mode was
  affected too, not just `--json`. A missing battery is now a result: one line
  in text, and `"present": false` with nulls in JSON, both exiting 0. `present`
  is emitted in the normal case as well.
- `rcc battery` reported `Fully Charged: No` on a Mac sitting at 100%.
  `SPPowerDataType` prints `Charging:` twice, once for the battery and once for
  the AC charger; both lines were taken, which turned the internal record into
  two lines and dropped every field after `charging`. Found because it was what
  broke the new `present` field.

- `rcc audit` stopped at the end to ask "Fix N issue(s) automatically? [y/N]" and
  read stdin with nothing checking whether there was anyone to answer, so every
  text-mode run - a bare `rcc audit`, `--dry-run`, `--explain` - waited forever
  wherever stdin does not close. Under cron it never returned; in the test suite
  it held one test for eleven minutes before it was killed. `--dry-run` reaching
  it was its own contradiction: a run that promises to change nothing stopping to
  ask permission to change something. The question is now asked only behind
  `[[ -t 0 ]]`, the guard already used forty lines earlier in the same file, and
  not behind a timeout, which would have spent that wait on every non-interactive
  run for good. The guard sits on the question, not on the block: a script still
  reads how many fixes are available and how to apply them, and loses only the
  question it could not answer. Machine formats never reached the prompt and are
  unchanged.
- `rcc ports --json` was not JSON. `lsof` writes a space in a command name as
  `\x20` and only quotes were escaped, so a Mac with Adobe installed produced
  `{"process": "Adobe\x20"}` and every parser refused it. The output now carries
  `pid`, `user` and `address` as well; `address` is the one that matters, since
  `127.0.0.1:8765` is reachable from this machine alone and `*:7000` is reachable
  from the network, and that distinction was being thrown away before the JSON
  was built.
- `rcc fleet` split every IPv6 literal into a truncated host and an invented
  port. `fe80::1` became host `fe80:` on port 1, `::1` became host `:` on port 1,
  and only the bracketed-with-a-port form came out right. Unlike the ports
  defect this one did not print a wrong number, it sent ssh to a machine that
  does not exist. A port now has to be digits in 1..65535 or it is not treated
  as one, and brackets are dropped because `ssh` takes a bare literal.
- `rcc network` read its listening ports correctly only by accident. It used the
  same idiom `ports` got wrong, and was saved by a `grep LISTEN` upstream that
  removed every connected socket first; widening that filter would have brought
  the bug straight back. The rule now lives in one place, where the shape of the
  address decides rather than the filter, and the section's output is unchanged.
- A step handed to the progress bar without its separator was reported as done
  without ever running. It fell into the branch that treats a missing command as
  nothing to do, and reported a pass for work that did not happen.
- `raycast/generate.sh` read a help format that stopped existing in 0.16.0 and
  removed all twenty-eight script commands before parsing. The parse returned
  nothing, so running it would have wiped them and written an empty command table
  over the extension's. It reads the current format and runs to completion before
  anything is removed.
- Four things in the Raycast extension: a failed command looked exactly like a
  successful one, because the exit status was resolved and never read; a command
  that finished without printing anything left "Running" on screen for good;
  stdout and stderr went into one buffer with no way to tell them apart; and a
  hint told the user to press an action that did not exist.

- `MENU_ITEMS` was three things at once: the menu, the source of `rcc --help`, and through that help the source of the Raycast extension. Three consumers reading one array shaped for the first of them is why the two menus drifted apart - the bash one grew the audit flags as rows, the Go one grew five fleet subcommands instead, and twenty of the twenty-eight entries they shared were in a different order. There is one array now, and each entry says where it appears.

### Appearance

- The raccoon reads as a raccoon. The ears were `/ \_/\_` and the eyes `( o.o )`,
  which is a cat; they are `n___n` and `[ o.o ]` now, across all 114 frames, the
  banner in both interfaces, and the frames the animations fall back on. The row
  above the head is blank rather than gone, so every frame keeps its height, and
  eyes and muzzle stay on the column they were on. The package box swapped the
  other way, `[o]` to `(o)`, so it cannot collide with the eyes.

### Known defects

- `rcc apps` still ignores `--json`. It is the one command left, and it is left
  on purpose: like `upgrade` it streams `__RCC_PROGRESS__` markers on stdout
  because it is an action rather than a report, so there is no clean text to
  serialise in the first place. Giving it structured output means deciding what
  an in-progress upgrade looks like as a document, which is a design question
  nobody has asked yet.

- The Raycast extension does not ship with this release. `release.yml` builds
  the CLI and the Go TUI and bumps the Homebrew formula; it does not touch
  `raycast-extension/`, so none of the view work above reaches anyone through
  `brew upgrade`. It is a separate channel — `npm run dev` locally, or a
  publish to the Raycast store — and that publish is a decision, not a build
  step.

- `rcc audit --csv` still prints the boxed report and then appends the CSV to
  the same stdout, which is what `--json` did until this release. A reader has
  to be told which line to start at. The fix is one token in the same condition
  that made `--json` clean, in `bin/audit.sh`; it is left undone deliberately,
  because it is a second visible change of behaviour and nobody has asked for
  it yet.
- Four confirmation prompts still read stdin with nothing checking whether anyone
  can answer: `bin/audit.sh:622` ("Remove the baseline?"), `bin/audit.sh:716`
  ("Remove profile 'X'?"), and `bin/startup.sh:104` and `:129` (removing orphan
  launch agents). Under cron or CI they wait forever. The guard is `[[ -t 0 ]]`,
  which this repository already uses five times - `bin/fleet.sh:501` and `:862`,
  `bin/upgrade.sh:655`, and twice in `bin/audit.sh` - but it is not a mechanical
  edit: at the audit fix prompt, not asking meant not fixing, which is what
  already happened; at `startup.sh` not asking means deciding whether to delete a
  plist, and that decision belongs to whoever makes it, one prompt at a time.
- `rcc audit` shells out to `softwareupdate -l` (`lib/audit/checks.sh:62`) for the
  Software Updates check, so how long an audit takes depends on what the machine
  is doing rather than on the audit. Seven seconds here; minutes elsewhere. Every
  test that runs a full audit inherits that, which makes the audit files the slow
  half of the suite. Independent of the two entries above.
- The Raycast audit list shows no time. Everything on that screen describes an
  instant - `fix_available` turns false the moment the thing is fixed - and a
  window left open shows a photograph with no date on it. The report carries a
  `timestamp` and the list drops it. It is not done because all three places it
  could go require moving something else first: `navigationTitle` already holds
  the three counts and would have to give them up; `searchBarAccessory` is a
  dropdown, not a label; and a pinned first row costs one of the fifteen visible
  lines and brings back the non-selectable-row problem. There is a fourth
  obstacle that is not about placement: `useExec` keeps the previous data across
  a revalidate, so during a reload the screen would show the *old* time next to a
  loading indicator, and a stale clock beside a spinner is worse than no clock.
  When every option asks for something else to move, the thing is not ready.

## [0.16.0] - 2026-08-31

### Added

- Every command draws its own animation while it runs, and reads live output to do it. All 22 scripts had shared five frames of a raccoon blinking, or one of nineteen variants of the same face with a different symbol stuck to its right; now `audit` follows the failures already printed, `disk` reads the Percent column volume by volume (APFS volumes share free space, so dividing per volume lies), `memory` shows four fatigue bands from wired+compressed against swap fill, `env` walks the PATH as a trail with holes where entries are missing, and so on for the rest. Three rules hold across all of them, and the tests fail if they stop holding: the silhouette is never deformed - objects hang beside the raccoon or the whole shape translates, but it never loses a piece, where the old frames mutilated the head into `__\_/\_`; every frame in an animation is the same height, where 92 of the old 157 had three lines against the rest's four and made the raccoon jump between beats; and nothing is claimed that has not happened, so `audit` announces no verdict before its checks finish and `git` never shows a commit crossing to a remote, which `rcc git` cannot push to.

### Fixed

- `rcc apps` no longer writes to `/Applications` at all. Layer 4 installed by hand: `_install_from_url` moved the existing bundle aside and copied the new one in with `|| true` on every line, so a failed copy left no app behind and still printed `✓ <app>`. That is how Disk Drill was destroyed on 2026-06-25 - it survives only as four `.raccoon-bak-*` folders. Every layer 4 app carries `SUFeedURL` in its plist, which means it ships Sparkle, and Sparkle swaps the bundle atomically and verifies the EdDSA signature; a bash script can do neither. The layer now reports the update and opens the app, letting the updater written for it do the install. Falling out of that: the manifest carries `app_path` because pass 3 opens the app after the loop that knew where it lives has ended, `_sparkle_decide` returns just the version (the enclosure URL had no consumer left, though its presence is still the gate - an item nobody can download is not an update), `/Applications` leaves the sudo gate so only brew can still need root, and `RCC_OPEN` seams the launch the way `RACCOON_SSH` already does in `fleet.sh` so the suite can exercise the path without opening anything. Layers 1-3 and `--no-sparkle`/`--auto-launch` are untouched.
- `rcc help` printed the raw menu entries, colon and all - `rcc upgrade:Update packages`. The list is stored as `name:description` and the loop echoed it whole; names and descriptions are two padded columns now, the width computed from the longest name so a new command cannot break it.
- `rcc --version` printed the entire command list: `show_help` was an alias for `show_version`, so asking for a version got thirty lines. `--version` is the two lines it claims to be, and the command list belongs to `help`.
- The interactive menu drew past the bottom of the window. It listed all twenty-nine commands unconditionally, and twenty-nine plus eight rows of chrome is thirty-seven rows in the 80x24 terminal `rcc` opens in: the window scrolled and the raccoon at the top was gone before it could be read. The list is a window now, sized to the height and positioned to keep the selection inside it, with one row held back because the view ends in a newline and writing that on the last row scrolls by one. The running and output views had clamped to the terminal height all along; the menu was the one that never did.
- The menu banner drew a raccoon one column off from every other one in the program. Its head sat at column five where the ninety-three frames the animations draw - and the bash banner - put it at four, which is one column right of the notch between the ears, so the tip landed over an ear instead of between them. The five default fallback frames had the same drift. All of them start from one silhouette now, and a test ties the banner to the default frame.
- The `curl | bash` installer ended every run with `installed successfully (v${VERSION:-dev})`, printed literally. `get_version` grepped `commands.sh` for `^VERSION=`, and that file stopped holding a literal version once the formula began stamping the tag into a `VERSION` file - the only line still matching was its own `VERSION="${VERSION:-dev}"` fallback. It reads the `VERSION` file now.
- `apps` was missing from the bash tab-completion word list. Its flags had a branch further down the file, and zsh has offered it all along, but the first word was never suggested, so tab did not know the command existed.
- The man page still identified itself as 0.8.0, dated 2026-06-08, eight releases back.

## [0.15.1] - 2026-08-25

### Fixed

- The sudo password prompt raised from inside the TUI could not be answered (#23). `rcc apps` asked for it while the TUI held the terminal in raw mode with its own key reader running: raw mode turns off CR-to-newline translation, so pressing Enter never ended sudo's read, and the password came back with whatever was typed next appended to it - "Sorry, try again", every time, on any Mac without Touch ID. Reproduced against a stub sudo that reads a real password: before the fix it received `hunter2qq`, the two keystrokes meant for the TUI swallowed into the read. Root access is now authenticated up front with the terminal released, so no prompt is ever raised underneath the interface, and any script the TUI spawns is told never to prompt. `ensure_sudo` gates its own password path on a reachable `/dev/tty` rather than on stdin being a terminal, which it never is for a spawned script - that mismatch is why the TUI reported "sudo unavailable" and skipped root-only work outright.
- The TUI crashed on its first running frame whenever the terminal reported a width below two, which is what a pty opened without a size reports. Both the running and output views handed `width - 2` straight to `strings.Repeat`, and that panics on a negative count, taking the whole program down with `strings: negative Repeat count`. Separator widths are clamped now.
- The sudo keepalive left its `sleep` behind. Stopping it killed the loop but not the sleep the loop was blocked in, so every run that primed sudo left a process reparented to launchd for up to fifty seconds after `rcc` had exited.
- Quitting the TUI while a script ran did not stop the script. The exit-time kill asserted the wrong model type - the key handlers hand back a pointer - so it never matched, and the script outlived the interface that started it, still holding a primed sudo timestamp.
- `RCC_DRY_RUN` was read as a knob throughout `apps` and `upgrade` but reset to false at the top of both, so exporting it did nothing and `RCC_DRY_RUN=true rcc upgrade` ran for real. An inherited value is honoured now; `--dry-run` still sets it.
- `upgrade` removed its failure log only on the happy path, stranding a `/tmp/raccoon-fail-XXXXXX` behind whenever a run was interrupted.
- The sudo pre-authentication was gated on Homebrew alone. A Mac with a root-owned global npm prefix and no brew never primed a timestamp, so the `sudo -n` behind the npm upgrade could only fail; the same held for the Sparkle install path where `/Applications` is not writable. Both gates ask what actually needs root now.
- `audit` holds a sudo keepalive for the length of a scan. A deep scan can outlive the five-minute timestamp - `softwareupdate` alone takes minutes - and the re-prompt landed mid-report where it could not be answered.
- The TUI asked sudo whether a timestamp was cached from inside its update loop, freezing the interface for as long as that call took. On a Mac whose sudoers comes from a directory service, that is not instant.

## [0.15.0] - 2026-08-18

### Added

- `overlap`: maps every PATH entry to the package manager behind it - brew, npm, cargo, go, pipx, macports, nix - resolving symlinks first. Resolution is the whole point: Homebrew's `bin` entries are relative links into `Cellar`, so an unresolved PATH makes every brew binary look unowned. Two extra categories keep the result readable: `system` for Apple's binaries under SIP (1208 of 2448 entries on the Mac this was written on - no manager installed them, none can remove them), and `shim` for mise/asdf/pyenv/rbenv/nvm/volta, whose per-project shadowing is their job rather than a problem. What survives in `orphan` is the part worth reading: the `curl | sh` scripts and stray `pip install`s that nothing manages any more. One row per PATH entry, not per executable, so broken and circular symlinks are listed and a name shipped by two managers stays two rows. Read-only, and no binary is ever executed - versions belong to manager metadata, so none are reported. `--json` for the machine-readable form.
- CI now runs the `overlap` tests on `ubuntu-latest` as well as macOS. They build their own fake filesystem and never touch the host, so they are the one suite that is meaningful on Linux - enough to catch GNU-vs-BSD drift in `readlink` and `awk` that a macOS-only CI would hide.

### Fixed

- `audit`: a value wider than the report box ran straight through the right border and left the report ragged. `_box_row` padded a short value but did nothing to a long one; two real values were enough here - an IPv6 link-local DNS server and a six-digit quarantined-file count. Long values are now cut and marked with `>`, carrying any trailing colour reset across the truncation.

## [0.14.0] - 2026-08-05

### Added

- `audit`: CIS Benchmark mapping (`--cis`), an HTML report (`--html`), per-check evidence with `--verbose`, `--only` to run a subset of groups, and semantic exit codes so CI can gate on the result.
- `audit`: reports redact secrets **by default** - password/key/token-named values, IPv4 and IPv6 addresses, and MAC addresses. `--no-redact` restores raw output.
- `fleet`: integrity checking, with `--print-bundle` to inspect what is sent.
- `SECURITY.md` and `CONTRIBUTING.md`.

### Fixed

- IPv6 addresses were not redacted in reports (#49). Times (`10:30:45`), zone identifiers (`%en0`) and bracketed hosts (`[::1]:443`) are no longer mangled by the redactor.
- The TUI binary (8.8 MB) was tracked in git; it is untracked now and the repo is correspondingly smaller.

### Changed

- `upgrade`: no longer updates Homebrew **casks**. A bare `brew upgrade` covers formulae *and* casks, so `rcc upgrade` was silently replacing GUI apps despite advertising "package managers and tools" - duplicating `rcc apps`, which already covers every cask via `--greedy`. Both `brew upgrade` and `brew outdated` are now scoped with `--formula`. If you relied on `rcc upgrade` for GUI apps, use `rcc apps`.

### Added

- `upgrade --parallel`: run all twelve tools at once instead of one after another (5.0s → 2.0s on a dry run here). Serial stays the default - this path installs software, so concurrency is opt-in. `--serial` forces the old behaviour and overrides `RCC_PARALLEL=1`. Per-tool output is replayed in the usual order once every tool has finished, rather than as it happens: bash gives each subshell a private copy of the progress counter, so the parent has to own it.

### Fixed

- `upgrade`: reported success no matter what broke. Sixteen pipelines ended in `|| true` and no path ever returned non-zero, so a tool could fail outright and the command still printed "Completed" and exited 0 - a cron job or a piped caller had no way to tell an upgrade from a no-op. Failures are now collected per tool, listed on a `Failed: …` line, and the command exits 1. `npm outdated` keeps its `|| true`: it exits 1 whenever it finds something to update, so treating that as failure would cry wolf every run. Turning this on immediately surfaced three tools failing silently here, one of them Raccoon's own bug (see below).
- `apps`: Sparkle appcasts were fetched one at a time, which dominated the command (16s for 13 feeds here). They are now fetched concurrently - read-only GETs, so nothing installs any faster or in a different order - and a dead feed no longer costs the full 10s, since `--connect-timeout 5` bounds the connect phase separately. Measured 16s → 5.3s. `RCC_FETCH_JOBS` (default 8) caps the concurrency.
- `apps`: the ~16MB Homebrew cask catalog was re-downloaded on every run. It is now cached in `~/.raccoon/cask-catalog.json` for a day, written atomically so an interrupted download cannot leave a truncated cache behind. Measured 5.3s → 3.5s per run, plus 16MB of traffic saved each time. `--no-catalog` still skips the layer entirely.

## [0.13.4] - 2026-06-28

### Fixed

- `fleet remove`: matched hosts by substring, so `remove user@192.168.1.1` also deleted `user@192.168.1.10` (and any line containing that text). Now matches whole lines.
- `fleet scan`: hosts that need `ssh-copy-id` were silently dropped - under `set -e` a failed probe `ssh` aborted before it could report "setup needed". Those hosts are reported again.
- `fleet scan`: could run for minutes with no output on a busy network. Probes now run fully in parallel under a per-host timeout and an overall `SCAN_MAX` budget (default 45s, env-overridable), and it prints how many hosts it is probing.
- `fleet scan` / `run` / `audit`: a background timeout killing `ssh` leaked a shell "Terminated" job message into stdout/JSON; suppressed without losing `ssh`'s own output.
- `fleet run`: quoted multi-word arguments were flattened (`grep "a b"` → `grep a b`); arguments are now preserved with `printf %q`. Added a per-command timeout and a temp-dir cleanup trap.
- `fleet audit`: a truncated remote JSON response could abort the whole aggregation; the parse now falls back to zero.
- `fleet audit` / `run`: a non-numeric or zero `--parallel` value crashed or spun; it is now validated.
- `fleet`: an unknown subcommand now exits non-zero; `fleet add` / `remove` no longer print Italian strings; `fleet group list` pluralizes "host(s)".

## [0.13.3] - 2026-06-27

### Fixed

- `apps`: outdated GUI apps were detected but often not updated. Three causes in the Homebrew-catalog layer:
  - Casks with a built-in auto-updater (`auto_updates`) were skipped, deferring to the app's own - frequently stale - updater. They are now updated via `brew install --cask --force` by default, matching `brew --greedy`. `--auto-launch` becomes opt-in to instead open the app so its internal updater runs.
  - The catalog version was parsed with a greedy regex that grabbed the last `version` on the line - an older fallback inside per-OS `variations` blocks (e.g. VS Code read as 1.97.2 instead of 1.126.0), so the installed copy looked newer and was skipped as up to date. Now reads the top-level version. Never downgrades.
  - `pkg`/installer casks ship no `app` artifact and were dropped from the lookup entirely; they are now matched by the cask display name, recovering Microsoft Teams / Multipass-class apps. Pure awk, no new dependency.
- `apps`: trim the `,revision` suffix from cask versions in the displayed output.

## [0.13.2] - 2026-06-26
### Added
- TUI: fleet entries in the interactive menu (scan, audit, status, list, groups).
  Argument-heavy subcommands (`run`, `group add`, `audit --group`) remain CLI-only.

## [0.13.1] - 2026-06-26
### Added
- `fleet scan` - discover Macs on the LAN (Bonjour + ping-sweep) and classify each host as ready / setup-needed / non-Mac; `--add` (or an interactive prompt) appends the fleet-ready hosts to `fleet.conf`. Options: `--user`, `--subnet`, `--timeout`, `--json`.
- `fleet group add|remove|list` - named groups of already-added hosts (`~/.raccoon/fleet-groups.conf`).
- `fleet run [--group NAME] [--parallel N] -- COMMAND` - run a command over SSH on every host, or just one group, in parallel.
- `fleet audit --group NAME` - audit only the hosts in a group.
### Fixed
- `apps`: Sparkle update detection now reads the latest appcast `<item>` and compares like-for-like (marketing version vs `shortVersionString`, or build vs `sparkle:version`). Apps that auto-update and are installed outside Homebrew (e.g. Arc, IINA) are detected correctly instead of being mis-compared against build numbers or skipped.
### Changed
- All user-facing output is now in English.

## [0.12.0] - 2026-06-25
### Added
- `audit --explain` - plain-language notes for each check.
- `audit --remediation` - before/after report for MSP technicians.
- `startup --clean` - interactively remove orphaned LaunchAgents (with backup).
- First-run onboarding wizard.
- `wifi` - active network, known SSIDs, opt-in Keychain passwords.
- `audit --baseline` / `--baseline-diff` / `--baseline-reset` - reference-state monitoring.
- `audit --schedule daily|weekly|monthly` (+ `status`/`remove`); native macOS alerts via `--alert`.
- Audit health-history sparkline in the menu banner.
- `disk --large` (`--min`, `--top`) - biggest files.
- `audit --profile` - per-client config, branding, and baseline.
- `audit --share` - publish the report as an anonymous GitHub Gist.
- `audit --sheet` (`--hours`, `--notes`) - fill-in intervention sheet (Markdown/RTF).
- `fleet` - SSH audit across multiple Macs (`audit`/`status`/`add`/`remove`/`list`); the remote runs a self-contained bundle, so no install is needed on the remote Macs.
### Changed
- `audit --json --quiet` now emits clean JSON (powers fleet mode); `print_output_json` includes the per-check `results` array.
- The bash fallback menu is data-driven; assorted internal de-duplication.

## [0.11.1] - 2026-06-23
### Fixed
- `apps`: pre-cache sudo so cask upgrades don't garble the password prompt.
- `apps`: suppress `mas` Spotlight warnings that flooded the output.
### Changed
- Regenerated demo GIFs (Remotion, synthetic and PII-free) and optimized their file sizes.

## [0.11.0] - 2026-06-22
### Added
- `audit --fix`: destructive fixes (SSH `authorized_keys`, cron, LaunchAgents, login items) now snapshot the originals to `~/.raccoon/fix-backups/<timestamp>/` first.
- Per-machine opt-out: list check names in `~/.raccoon/audit.conf` to report-but-never-fix them.
- `lib/audit/checks.sh` is now shellcheck-linted in CI.
### Changed
- `audit --fix` is safe by default: dropped the auto-set of Google DNS (a DHCP-provided resolver is now reported as a pass) and the recursive `com.apple.quarantine` strip (report-only, so Gatekeeper is preserved).
### Fixed
- APFS disk/memory crashes, TUI progress abort, and hidden sudo prompt (#23, #24).
- Failed fixes now surface their error instead of failing silently.
- ~40 bugs across a full-repo audit (shell + Go TUI).

## [0.10.3] - 2026-06-19
### Fixed
- CI version detection is robust under `pipefail` with a dynamic VERSION.
- Guard `git describe` to avoid a Homebrew tag leak.

## [0.10.2] - 2026-06-19
### Added
- `apps` entry in the interactive TUI menu.
### Fixed
- `audit`: correct `softwareupdate` parsing for modern macOS.

## [0.10.1] - 2026-06-19
### Fixed
- CI: use the `RACCOONTAPPUSH` secret and make releases idempotent.
- Derive the version from the git tag.

## [0.10.0] - 2026-06-19
### Added
- `rcc apps`: update both Mac App Store and non-App-Store applications.
### Changed
- UI improvements, especially for `rcc update` and `rcc audit`.
### Fixed
- Various audit fixes.

## [0.9.1] - 2026-06-18
### Added
- `upgrade`: tap-trust preflight; support for pnpm, bun, uv, Go, Docker, and claude; npm sudo fallback.
- `backup`: Time Machine destination mount-point display and exclusion handling.
- `disk`: MOUNT POINT column, dynamic `/Volumes/*` scan, internal/external classification.
### Fixed
- Test teardown runs `chmod -R +w` before `rm -rf` to handle read-only `go install` files.

## [0.9.0] - 2026-06-18
### Added
- `disk`: network-mounts section (smbfs/nfs/afpfs) and external-drive detection.
- `memory`: system RAM stats (wired, active, cached, compressed, swap).
- `ssh`: `--export` (copy public key to clipboard) and `--export-gpg`.
### Fixed
- GUI hang: child processes no longer inherit TTY raw mode.

## [0.8.0] - 2026-06-12
### Changed
- Split the monolithic `audit.sh` into plumbing plus `lib/audit/checks.sh`.
### Fixed
- bash 3.2 resilience: `|| true` fallback on sudo/command substitutions under `set -euo pipefail`; non-interactive audit now exits 0 instead of crashing.

## [0.7.0] - 2026-06-09
### Fixed
- Restored the v0.5.0 animated Bubble Tea TUI (v0.6.x had replaced it with a plain-grid draft).
- `rcc --version` now reports the real version.
### Changed
- TUI palette contrast raised for dark terminals.

## [0.6.1] - 2026-06-09
### Fixed
- `audit`: category box right-border padding (SC2154); removed dead `CURRENT_CATEGORY` (SC2034).
- `install.sh`: use `fetch + reset` instead of `git pull` so installs survive force-pushes.

## [0.6.0] - 2026-06-08
### Added
- bash/zsh completions, man page, install script, bats suite (14 tests), CI workflow, issue/PR templates, and LICENSE.
### Fixed
- All shellcheck warnings across `bin/` and `lib/core/`.
- Non-interactive sudo guard in `audit.sh` (no more hang on the sudo prompt).

## [0.5.0] - 2026-06-07
### Added
- Animated TUI: per-script raccoon animations and a real-time progress bar.
### Changed
- bash 3.2 compatibility.

## [0.2.5] - 2026-04-29
### Added
- `trash --empty` with a confirmation prompt.
### Fixed
- `startup`: launch-agent name parsing and uptime column overflow.
- `env`: duplicate PATH detection.
- `fonts`: variable scope when computing totals.

## [0.2.4] - 2026-04-29
### Fixed
- `startup`: launch-agent prefix stripping and load-average extraction.
- `fonts`: duplicate sections and total-row placement.
- `history`: zsh extended-history parsing.
- `docker`: placeholders for empty columns.

## [0.2.3] - 2026-04-29
### Added
- Progress labels across `fonts`, `trash`, `backup`, and `certs`.
### Fixed
- Table alignment via shared helpers in `startup`, `docker`, and `history`.
- `env`: summary line and symlink check.
- `audit`: `while/shift` argument parsing and correct `--report FILE`.

## [0.2.2] - 2026-04-29
### Added
- All 18 `bin/*.sh` scripts and the `ui/` directory to the public repo.
- `upgrade`: inline spinner for long operations.
### Fixed
- `rcc`: removed `exec` so the bash fallback menu triggers when the Go UI fails.
- `memory`: JSON trailing comma.
- `common`: removed dead table functions.

## [0.2.1] - 2026-04-29
### Added
- `ui/build.sh` to compile `rcc-ui`; install compiles it when Go is present.
### Fixed
- Table alignment in `disk`/`memory`; `memory --top N` parsing.
- `rcc audit` multi-word subcommands (`fix`, `deep`).
- Audit category header padding and auto-fix prompt reliability.

## [0.2.0] - 2026-04-29
### Added
- Interactive auto-fix prompt after the audit summary, plus a `MANUAL:` fix pattern.
- All commands wired into `rcc` (audit variants, network, disk, memory, and more).
### Fixed
- rcc-ui terminal corruption via `tea.ExecProcess`; table alignment; four failing auto-fix actions.

## [0.1.0] - 2026-04-28
### Added
- Initial release: `rcc audit` (quick and `--deep`), output formats (`--json`/`--csv`/`--html`), `certs`, and an interactive menu.
