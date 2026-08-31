# Recapturing the demo GIFs

Working note for the session that refreshes `docs/gifs/`. Written 2026-08-31,
right after 0.17.0 was prepared locally. Everything below was verified by
reading the repo, not by memory.

The GIFs are stale in two different ways. Nineteen of the twenty Remotion
fixtures were captured on 2026-06-22 and show 0.11.0-era output. `hero.gif`,
the first image in the README, is older still and is not produced by the
harness at all - nothing here regenerates it.

Only one of them is urgent. The fixtures are synthetic and clean; `hero.gif` is
the single file in the repository that carries real data. It is recaptured
first, for that reason and no other.

---

## Step 0 - resolve the `rcc-menu.gif` collision first

**Do this before generating anything.** Two independent pipelines write the
same file:

| pipeline | writes |
|---|---|
| `docs/remotion/scripts/render-all.mjs` (`const outDir = join(root, '..', 'gifs')`) | `docs/gifs/rcc-<id>.gif`, including `rcc-menu.gif` |
| `docs/tapes/rcc-menu.tape` (`Output ../gifs/rcc-menu.gif`) | `docs/gifs/rcc-menu.gif` |

Whichever runs last wins, silently. Since the hero rework needs vhs (see
below) and the fixture pass needs Remotion, both will run in the same session
and one will overwrite the other's `rcc-menu.gif`.

Pick one owner for that path before the first render. Running them in either
order without deciding produces a `rcc-menu.gif` whose provenance nobody can
tell afterwards.

The twenty-two `.tape` files are referenced by nothing in the repo - dead
tooling that still works. `vhs`, `asciinema` and `agg` are all installed.

---

## Recapture order

0. **Resolve the `rcc-menu.gif` collision** - above.
1. **`hero.gif`** - reshoot, see below.
2. **`menu.txt`** - hand-written, see below.
3. **The eleven safe ones**: `disk`, `memory`, `ports`, `battery`, `backup`,
   `docker`, `git`, `xcode`, `ssh`, `startup`, `history`.
4. **The six that need scrubbing after capture**: `audit`, `network`, `certs`,
   `env`, `trash`, `fonts`.

**Why `hero` goes first.** Checking the fixtures for this note turned up
something that reorders the whole session. The twenty fixtures are synthetic
and clean: `/Users/alex` is invented, there is no real username and no real
hostname anywhere in them. `50fd94d` did the sanitisation properly and it has
held.

Which leaves `hero.gif` as **the only file in the repository carrying real
data** - the full home path of the machine it was recorded on, and two personal
tap names, one of them a proxy client. Not one defect among seven: the only
one of its kind in the whole project, and it sits at the top of the README,
above the title.

That makes it the first thing to fix, before any cosmetic work. Everything else
in this session is staleness - screens showing an old face, an old menu, an old
version number. hero is the only item that is a disclosure, and it stays a
disclosure for exactly as long as it takes to replace it.

**Why `menu` comes next.** It is the only fixture where the raccoon face
appears - the other nineteen are reports, and the face neither is nor should be
in them. It is also the only fixture that depends on the menu reorganisation
done in 0.17.0. If the session stops after hero, it has to have stopped after
`menu` too: a pass that skipped it leaves the one screen that actually changed
still showing the old flat list and the old cat face.

---

## The twenty fixtures

All from `50fd94d` (2026-06-22, *"regenerate demo GIFs with Remotion
(synthetic, PII-free) + harness"*) except `help`, recaptured 2026-08-31. On-disk
mtimes read 06-23; that is a checkout timestamp, not authorship.

| fixture | command | lines | contains paths/hosts | needs sudo |
|---|---|---:|---|---|
| `menu` | `rcc` | 12 | no | no |
| `audit` | `rcc audit --deep` | 57 | yes | **yes** |
| `disk` | `rcc disk` | 32 | no | no |
| `network` | `rcc network` | 75 | yes | no |
| `memory` | `rcc memory` | 29 | no | no |
| `ports` | `rcc ports` | 10 | no | no |
| `battery` | `rcc battery` | 12 | no | no |
| `backup` | `rcc backup` | 11 | no | no |
| `upgrade` | `rcc upgrade --dry-run` | 86 | no | **yes** |
| `docker` | `rcc docker` | 27 | no | no |
| `git` | `rcc git` | 24 | no | no |
| `xcode` | `rcc xcode` | 35 | no | no |
| `certs` | `rcc certs` | 15 | yes | no |
| `ssh` | `rcc ssh` | 18 | no | no |
| `env` | `rcc env` | 88 | yes | no |
| `startup` | `rcc startup` | 57 | no | no |
| `trash` | `rcc trash` | 20 | yes | no |
| `fonts` | `rcc fonts` | 28 | yes | no |
| `history` | `rcc history` | 22 | no | no |
| `help` | `rcc help` | 34 | no | no |

**The current fixtures are clean.** No real username, no real hostname: the
paths in them read `/Users/alex`. The "contains paths/hosts" column is not a
list of leaks - it is a list of the six commands whose output *includes* paths
and hosts, and which will therefore come back dirty the moment they are
recaptured on a real machine. The synthetic substitution that `50fd94d`
applied has to be reapplied by hand after each of those six captures. The
other eleven have no such surface, which is why they are safe to capture almost
blind.

`audit --deep` and `upgrade --dry-run` need an active sudo session. The commit
that replaced the old vhs GIFs noted they "rendered blank for sudo-gated
commands"; that is the trap to avoid repeating.

---

## `menu.txt` - the one that cannot be captured

Twelve lines, and the only fixture that is not the output of a command. The TUI
is an interactive Go program that redraws the screen; it prints nothing to
stdout, so there is no capture to take. The current fixture is a hand-drawn
frame showing a menu that no longer exists: a grid inside a box, no raccoon, no
categories, no `wifi`, and a `←→ Navigate · ↑↓ Rows` footer the TUI does not
have.

Rewrite it by hand, transcribing from `menuView()` in `ui/main.go`, which is
what actually renders it. Print it from a throwaway Go test and copy the
result. It must show:

- the banner face: `n___n` / `[ o.o ]` / `> ^ <`
- the four category headings rendered by `headingRule()`
- twenty-two commands plus `wifi`
- the `fleet` expansion marker

---

## `hero.gif`

### How it was made

Two commits, not more. An earlier `git log --follow` reports eleven going back
to April; that is a false trail, there are no rename records.

```
55aa4b1  2026-06-23  Add files via upload      <- uploaded, not generated
d1a4854  2026-08-03  re-encoded 8.6 MB -> 2.9 MB
```

`Add files via upload` is the GitHub web UI. **No tool in this repo produced
it.** It arrived alongside `docs/gifs/9e2dljw17g8h1.mp4` - a Reddit-style media
id, and `docs/REDDIT_POST.md` exists - a screen recording made for a post.

That mp4 is the source and is still recoverable from `55aa4b1`:

```
mp4  1080x798  18.25 s  h264
gif   640x473  18.27 s  268 frames
```

Same duration, same aspect ratio: `hero.gif` is that video scaled down.
`d1a4854` re-encoded it and deleted the mp4 from the tree.

**The source is not re-editable.** It is a recording of a live session, not a
project - there is nothing in it to re-render with different content. hero has
to be shot again from scratch.

Remotion cannot do it: it renders static fixture text, there is no `hero`
composition, and hero is an interactive session. `docs/tapes/rcc-menu.tape`
already drives the real TUI (`Type "rcc" Sleep 500ms Enter`), so a `hero.tape`
is the recipe - subject to Step 0.

### What it shows today - 18.3 s, 640x473, 268 frames

| t | content |
|---|---|
| 0-2 s | old menu. **Cat** face `/ \_/\_` `( o.o )` `> ^ <`. Flat single column, 17 commands, no categories, no `wifi`, no `fleet`. Cursor on `upgrade`. Footer `↑↓ j/k Navigate · Enter Run · / Search` |
| 2 s | Enter, running view. Animated face `( *.* )[=]`. `1/18 (5%)`, `==> Updating Homebrew...` |
| 5 s | `2/18 (11%)`, `Already up-to-date.` |
| 7.5-10 s | brew untrusted-tap warnings for `steipete/tap` and `v2raya/v2raya`, `brew untap …`, `export HOMEBREW_NO_REQUIRE_TAP_TRUST=1`, then `thousandflowers/raccoon/rcc 0.8.0 -> 0.9.1` |
| 12.5 s | **the upgrade fails.** `==> go build -o /opt/homebrew/Cellar/rcc/0.9.1/libexec/bin/rcc-ui`, `Last 15 lines from /Users/<real home>/Library/Logs/Hom…`, `If reporting this issue please do so at … homebrew-raccoon/issues` |
| 15 s | `10/18 (55%)`, `nvm: upd`, `pip: no outdated packages`, `npm: not installed`, `v24.17.0 is already installed.` |
| 17.5 s | scroll view `↑↓ 1/75`, the brew trust block again, footer `↑↓ Scroll · Enter Return · q Quit` |

### The seven defects, worst first

1. **The first image of the project is Raccoon failing to upgrade itself**,
   showing the `rcc-ui` build error and an invitation to open an issue.
2. **It is the only file in the repository carrying real data.** The full home
   path `/Users/<real username>/` is on screen, and so are two personal taps,
   `steipete/tap` and `v2raya/v2raya` - `v2raya` being a proxy client. Every
   fixture around it is synthetic; this one is not. It is a data problem, not a
   stale-content problem: recapturing it for looks would still ship the paths
   and the tap names unless they are removed deliberately. Say it out loud so
   it does not get filed as cosmetic. This is why hero is recaptured first.
3. Old face and flat menu - both changed in 0.17.0.
4. It shows `rcc 0.8.0 -> 0.9.1`. Current is 0.17.0.
5. 640 px clips text on every right edge: `brew: up`, `Hom`, `thousan`,
   `repositori`. The other GIFs are 900 or 1400 px wide.
6. The README `alt` reads `"Raccoon - rcc audit running"`. It is not `audit`,
   it is `upgrade`.
7. Heaviest file in `docs/gifs`: 2.8 MB of 15 MB.

### What the replacement should show

The new menu with its four categories, then **a command that starts, runs and
finishes cleanly** - `disk` or `battery` - instead of `upgrade`.

**The right length is not eighteen seconds.** Eighteen was how long `upgrade`
happened to take; it was never a choice. `upgrade` is the reason this GIF shows
a failure at all - it was the only command slow enough to fill the frame. Six
or seven seconds of a command that completes shows a whole cycle, rather than a
fragment of a process that stalls.
