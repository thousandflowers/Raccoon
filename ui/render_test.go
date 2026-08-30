package main

import (
	"strings"
	"testing"

	"github.com/mattn/go-runewidth"
)

// Everything else here tests the helpers. This tests the wiring: runningView is
// where the art, the live output and the terminal size actually meet, and it is
// the one place none of the other tests touch.
func TestRunningViewRendersEveryScript(t *testing.T) {
	// One plausible line of output per command, enough to drive its reader.
	samples := map[string][]string{
		"audit.sh":   {"⚠ FileVault: Unknown", "✓ SIP: Enabled", "✗ boom"},
		"upgrade.sh": {},
		"apps.sh":    {},
		"network.sh": {},
		"disk.sh":    {"| /                    | 12Gi | 59Gi | 17%  |", "| /System/Volumes/Data | 352Gi | 59Gi | 86% |"},
		"memory.sh":  {"| Total RAM | 16 GB |", "| Wired | 2671 MB |", "| Compressed | 7709 MB |", "| Swap Total | 28672.00 MB |", "| Swap Used | 27965.56 MB |"},
		"ports.sh":   {"| 7000 | TCP | ControlCe | LISTEN |"},
		"battery.sh": {"| Cycle Count | 691 |", "| Max Capacity | 85% (good) |", "| Charging | No |"},
		"backup.sh":  {"| Destination | Not configured |", "| Backup | No backup found |"},
		"ssh.sh":     {"-- Unprotected Keys", "| id_ed25519 | (ED25519) | NO PASSPHRASE |"},
		"git.sh":     {"| home | 416 uncommitted, |", "| canary | 1 no upstream |"},
		"docker.sh":  {"| a1b2 | postgres | Up 2 hours |", "| c3d4 | redis | Exited (0) |"},
		"xcode.sh":   {"| Size | 12G |"},
		"env.sh":     {"-- PATH Entries", "| /usr/bin | OK |", "| /gone | MISSING |"},
		"startup.sh": {"[1/6] User LaunchAgents...", "| ✓ mailbrief | |", "[2/6] System LaunchAgents...", "| /Library/LaunchAgents/ | 7 |"},
		"trash.sh":   {"| Size | 6.0G |", "[3/3] Recent Items (Last 10)...", "| BarBeR_Dataset.zip |"},
		"fonts.sh":   {"| Duplicates | 12 families |", "| Corrupted fonts | 0 |"},
		"history.sh": {"| Total | 2195 |", "[2/2] Recent Commands...", "| claude |"},
		"certs.sh":   {"Total Valid Expiring Expired Self-Signed", "42 26 2 14 8"},
		"wifi.sh":    {"-- Known Networks", "| Pontrelli |", "| iPhone |"},
		"overlap.sh": {"| jq | /opt/homebrew/bin/jq | x | brew |", "| jq | /usr/bin/jq | x | system |"},
		"fleet.sh":   {"  ✓ lampone 12 pass 2 warn 0 fail", "  ✗ oldmini UNREACHABLE (TIMEOUT)"},
	}

	if len(samples) != len(scriptFrames) {
		t.Fatalf("%d scripts sampled, %d have animations", len(samples), len(scriptFrames))
	}

	// A narrow terminal is where an over-wide drawing shows up as a wrapped line.
	for _, size := range [][2]int{{80, 40}, {60, 24}, {200, 60}} {
		for script, out := range samples {
			for frame := 0; frame < 40; frame++ {
				m := model{
					state:         stateRunning,
					width:         size[0],
					height:        size[1],
					currentScript: script,
					spinnerFrame:  frame,
					outputTitle:   script,
					outputLines:   out,
					progressLabel: "brew: installing...",
					progressCurr:  3,
					progressTotal: 8,
				}
				view := m.runningView() // must not panic

				// Measure what is actually drawn, not what is stored: most of these
				// animations rewrite their own frames from live output, so the two
				// differ by design. The art is the block between the title and the
				// first separator.
				//
				// The progress bar is left out on purpose: it already overflows a
				// narrow terminal on main — checked in a worktree of main itself —
				// and this work neither caused that nor fixes it.
				lines := strings.Split(view, "\n")
				sawSilhouette := false
				for _, line := range lines[1:] {
					if strings.Contains(line, "─") {
						break // the separator ends the art
					}
					plain := stripANSI(line)
					// Display columns, not bytes: a box-drawing rune is three bytes
					// and one column, and len() would call every one an overflow.
					if w := runewidth.StringWidth(plain); w > size[0] {
						t.Errorf("%s frame %d at %dx%d: art is %d columns, terminal is %d:\n%q",
							script, frame, size[0], size[1], w, size[0], plain)
					}
					if strings.Contains(plain, `/ \_/\_`) {
						sawSilhouette = true
					}
				}
				if !sawSilhouette {
					t.Errorf("%s frame %d: the raccoon is not in its own view", script, frame)
				}
				if !strings.Contains(view, "Running") {
					t.Errorf("%s frame %d: the footer went missing", script, frame)
				}
			}
		}
	}
}

// The art must never grow past what the layout budgeted for it, or the streamed
// output loses lines off the bottom of the screen.
func TestArtNeverStarvesTheOutput(t *testing.T) {
	for script, frames := range scriptFrames {
		for i, f := range frames {
			if n := len(strings.Split(f, "\n")); n > 8 {
				t.Errorf("%s frame %d is %d lines tall; nothing should need more than 8", script, i+1, n)
			}
		}
	}
	for script, frames := range scriptFrames {
		want := len(strings.Split(frames[0], "\n"))
		for i, f := range frames {
			if n := len(strings.Split(f, "\n")); n != want {
				t.Errorf("%s: frame %d has %d lines, frame 1 has %d — the raccoon will jump",
					script, i+1, n, want)
			}
		}
	}
}

// The menu is the first thing rcc draws, and on an 80x24 terminal it used to
// draw 29 commands into 24 rows: the terminal scrolled and the raccoon at the
// top was gone before the user saw it. The view must fit the window it is given.
func TestMenuViewFitsTheTerminal(t *testing.T) {
	for _, height := range []int{10, 24, 40, 100} {
		m := model{items: items(), width: 80, height: height}
		lines := strings.Split(strings.TrimSuffix(m.menuView(), "\n"), "\n")

		// height-1, not height: the trailing newline the view ends on scrolls
		// the window if it lands on the last row, which is the whole bug.
		if len(lines) > height-1 {
			t.Errorf("height %d: menu rendered %d rows", height, len(lines))
		}
		if !strings.Contains(m.menuView(), "( o.o )") {
			t.Errorf("height %d: the raccoon is missing from the top", height)
		}
	}
}

// Scrolling past the last visible row must bring the selection with it, or the
// cursor lands on a command that is not on screen.
func TestMenuViewKeepsTheSelectionVisible(t *testing.T) {
	all := items()
	for _, selected := range []int{0, 5, len(all) / 2, len(all) - 1} {
		m := model{items: all, width: 80, height: 24, selected: selected}
		start, end := m.menuWindow(len(all))
		if selected < start || selected >= end {
			t.Errorf("selected %d outside the window [%d,%d)", selected, start, end)
		}
	}
}

// A model that has not been told its size yet must not hide anything.
func TestMenuWindowShowsEverythingBeforeTheFirstResize(t *testing.T) {
	m := model{items: items(), width: 0, height: 0}
	if start, end := m.menuWindow(len(m.items)); start != 0 || end != len(m.items) {
		t.Errorf("window [%d,%d), want the whole list of %d", start, end, len(m.items))
	}
}
