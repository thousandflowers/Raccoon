package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ─── Messages ──────────────────────────────────────────────

type scriptOutput struct {
	line    string
	scanner *bufio.Scanner
	cmd     *exec.Cmd
}

type scriptDone struct {
	err error
}

type tickMsg struct{}

// sudoPrimed reports the result of the pre-script `sudo -v` run by primeSudo.
type sudoPrimed struct {
	err error
}

// ─── Raccoon animation frames ──────────────────────────────
// Every frame within one animation has the same number of lines — four for
// most, more where the scene needs the room — because a frame of a different
// height makes the raccoon jump between beats. Title is rendered separately
// above the art, so the lines are pure ASCII scene.

type raccoonAnimation []string

// Default fallback (5 basic frames)
var raccoonFrames = raccoonAnimation{
	`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	`    _
   / \_/\_
  ( -.- )
   > ^ <`,
	`    _
   / \_/\_
  ( ^.^ )
   > ^ <`,
	`    _
   / \_/\_
  ( *.* )
   > ^ <`,
	`    _
   / \_/\_
  ( >.< )
   > ^ <`,
}

// Each script gets its own animation with a completely unique
// visual style — different body shapes, objects, and action
// sequences. Frame height is per-animation, not four everywhere.
var scriptFrames = map[string]raccoonAnimation{
	// wifi — a field of waves filling the width, with the name of each
	// remembered network sailing through it. Not connected leaves the field
	// moving and nothing joined, which is exactly what is happening.
	"wifi.sh": {
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	},

	// overlap — the fork. One command name on top, the places that provide it
	// below, and a mark on the one the PATH actually reaches first. env shows
	// the trail's order; this shows what that order decides.
	"overlap.sh": {
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	},

	// fleet — he goes under and leaves: an SSH audit is not a probe sent from
	// here, it is him inside other machines. His body stays with an empty face
	// while the machines appear around him as visions, each wearing its own
	// state — a host that never answered included, since an audit that skipped
	// it proves nothing about it.
	"fleet.sh": {
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	},

	// upgrade — a hyperbolic ray crosses the sky and lands on the raccoon's
	// head: flat and slow far away, dropping fast as it arrives, the way a
	// download behaves. Sixteen frames at the 300ms tick is a 4.8s crossing.
	//
	// The box is a placeholder here. upgradeBox rewrites it at render time from
	// the phase the script actually declared, so the animation reports the run
	// rather than miming a fixed story. The silhouette itself never deforms.
	"upgrade.sh": {
		`                              *

    _
   / \_/\_
  ( o.o ) [o]
   > ^ <`,
		`                            * ,

    _
   / \_/\_
  ( o.o ) [o]
   > ^ <`,
		`                          * , ,

    _
   / \_/\_
  ( -.- ) [o]
   > ^ <`,
		`                        * , , ,

    _
   / \_/\_
  ( -.- ) [o]
   > ^ <`,
		`                      * , , ,

    _
   / \_/\_
  ( o.o ) [o]
   > ^ <`,
		`                    * , , ,

    _
   / \_/\_
  ( o.o ) [o]
   > ^ <`,
		`                  * , , ,

    _
   / \_/\_
  ( *.* ) [o]
   > ^ <`,
		`                * , , ,

    _
   / \_/\_
  ( *.* ) [o]
   > ^ <`,
		`              * , , ,

    _
   / \_/\_
  ( o.o ) [o]
   > ^ <`,
		`              , , ,
            *
    _
   / \_/\_
  ( o.o ) [o]
   > ^ <`,
		`              , ,
          * ,
    _
   / \_/\_
  ( -.- ) [o]
   > ^ <`,
		`              ,
        * , ,
    _
   / \_/\_
  ( o.o ) [o]
   > ^ <`,
		`
        * , ,
    _
   / \_/\_
  ( ^.^ ) [o]
   > ^ <`,
		`
      * , ,
    _
   / \_/\_
  ( o.o ) [o]
   > ^ <`,
		`

    _
   / \_/\_
  ( ^.^ ) [o]
   > ^ <`,
		`

    _
   / \_/\_
  ( o.o ) [o]
   > ^ <`,
	},

	// apps — the same hyperbola upgrade uses, but what crosses the sky is the
	// name of the application being updated, eaten a letter at a time as it
	// lands. Only the raccoon is stored here; appsSky composes the two rows
	// above it at render time, because the name is only known while running.
	"apps.sh": {
		`    _
   / \_/\_
  ( o.o ) [o]
   > ^ <`,
		`    _
   / \_/\_
  ( o.o ) [o]
   > ^ <`,
		`    _
   / \_/\_
  ( -.- ) [o]
   > ^ <`,
		`    _
   / \_/\_
  ( o.o ) [o]
   > ^ <`,
		`    _
   / \_/\_
  ( <.< ) [o]
   > ^ <`,
		`    _
   / \_/\_
  ( o.o ) [o]
   > ^ <`,
		`    _
   / \_/\_
  ( >.> ) [o]
   > ^ <`,
		`    _
   / \_/\_
  ( o.o ) [o]
   > ^ <`,
		`    _
   / \_/\_
  ( -.- ) [o]
   > ^ <`,
		`    _
   / \_/\_
  ( o.o ) [o]
   > ^ <`,
		`    _
   / \_/\_
  ( *.* ) [o]
   > ^ <`,
		`    _
   / \_/\_
  ( ^.^ ) [o]
   > ^ <`,
	},

	// audit — the raccoon hunts: the eyes sweep left and right while the
	// magnifying glass extends. The silhouette never deforms and every frame is
	// 4 lines, so the head does not jump between frames.
	//
	// These are the neutral frames. auditMood swaps the eyes at render time when
	// the run has already turned up warnings or failures, so the face reports
	// what was actually found rather than miming a fixed story.
	"audit.sh": {
		`    _
   / \_/\_
  ( o.o ) o
   > ^ <`,
		`    _
   / \_/\_
  ( <.< ) o-
   > ^ <`,
		`    _
   / \_/\_
  ( >.> ) o--
   > ^ <`,
		`    _
   / \_/\_
  ( *.* ) o--
   > ^ <`,
		`    _
   / \_/\_
  ( ^.^ ) o-- ok
   > ^ <`,
	},

	// network — the raccoon pings and listens: one arc, two, three, then a beat
	// of silence before the next burst. That pause is what makes it read as a
	// pulse rather than a flicker, and it matches what the command does — it
	// sends a volley of probes and waits.
	//
	// The arcs' outer rows sit one column back, which is where the curve comes
	// from; the silhouette itself is untouched.
	"network.sh": {
		`    _
   / \_/\_ '
  ( o.o )   )
   > ^ <   ,`,
		`    _
   / \_/\_ '  '
  ( o.o )   )  )
   > ^ <   ,  ,`,
		`    _
   / \_/\_ '  '  '
  ( o.o )   )  )  )
   > ^ <   ,  ,  ,`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	},

	// disk — the raccoon reads and reports, so the art shows the one thing the
	// progress bar cannot: how full each volume is. The gauges are hung beside
	// the four lines at render time, since the numbers only exist while running.
	"disk.sh": {
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( -.- )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	},

	// memory — the raccoon wears the machine's condition. Calm it roams; under
	// pressure it carries more, its eyes close and its mouth opens; spent, it
	// barely moves. canary reads your fatigue, this reads the Mac's.
	//
	// These are the calm frames; memStateFor rewrites them once the table has
	// been printed and the pressure is known.
	"memory.sh": {
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( <.< )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( >.> )
   > ^ <`,
	},

	// ports — a port is a door, so the raccoon tries them one at a time. The
	// number and process are real; "<" marks the ones left standing open.
	//
	// The frames are bare: portsSlot hangs the door beside them at render time,
	// because which doors exist is only known while running.
	"ports.sh": {
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	},

	// battery — the gauge is the pack's health, not its charge. The charge is
	// already in the menu bar every second of the day; how far the battery has
	// aged is the thing you open this command to find out.
	"battery.sh": {
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	},

	// backup — a backup is a copy of you, so the copies stand behind the raccoon
	// in a row and grow as the copying goes on. With no destination and no
	// backup there is nothing behind him at all, which is the point.
	"backup.sh": {
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	},

	// ssh — the raccoon tries the keys one at a time, and the key's own shape
	// says whether it closes: o== locks, o-- has no passphrase, o=/ has file
	// permissions anyone can read, o=? has nothing to match it.
	"ssh.sh": {
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	},

	// git — the gap between what is in your hands and what is safe on a remote.
	// On a clean repository the signal climbs away; where work is pending the
	// symbols simply sit there, because this command only looks.
	"git.sh": {
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	},

	// docker — the raccoon counts the containers, adding one box to the pile per
	// beat. Running ones at the bottom, stopped ones capping it: the base is what
	// is working, the top is what someone forgot to turn off.
	"docker.sh": {
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	},

	// xcode — the heap of build leftovers, as tall as DerivedData really is.
	// That cache is the only reason to run this command: it grows to tens of
	// gigabytes in silence and every grain of it can be thrown away today.
	"xcode.sh": {
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	},

	// env — a PATH is a trail the shell walks on every command, so the raccoon
	// walks it too. Stones are directories that exist; the gaps are entries it
	// searches and never finds.
	"env.sh": {
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	},

	// startup — everything that wakes with the Mac falls in behind him and stays
	// there. The procession is the honest part: these are not events at boot,
	// they are company for the rest of the session.
	"startup.sh": {
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	},

	// trash — the one command whose subject is the raccoon itself. The bin fills
	// from the floor with what is really in it, and he fishes the items out by
	// name, because six gigabytes in two files is a different problem from six
	// gigabytes in ten thousand.
	"trash.sh": {
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	},

	// fonts — he reads the collection, a page per beat. Duplicate families are
	// what wears him down: the same font installed twice is loaded twice by
	// every application, for nothing.
	"fonts.sh": {
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	},

	// history — the scroll unrolls a stretch per beat, each stretch carrying one
	// of the commands you actually typed, and the round closes with the total.
	"history.sh": {
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	},

	// certs — the certificates as a wall. Each upright is one still standing, a
	// gap is one that has expired: the proportion of holes is readable without
	// counting anything.
	"certs.sh": {
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
		`    _
   / \_/\_
  ( o.o )
   > ^ <`,
	},
}

// ─── Progress marker parsing ───────────────────────────────

// appsPath is the hyperbola the app name flies along: nearly flat while it is
// far away, dropping onto the head as it arrives. Each entry is where the name
// starts, so a long name and a short one both land in the same place.
var appsPath = func() [][2]int {
	var p [][2]int
	for c := 34; c >= 7; c -= 2 {
		row := 0
		if c <= 14 {
			row = 1
		}
		p = append(p, [2]int{row, c})
	}
	return p
}()

// appNameVerbs are the phrases bin/apps.sh puts around an application's name.
// Trimming them is what is left of the label once the prefix is gone.
var appNameVerbs = []string{"downloading ", "updating ", "opening ", "Upgrading ", "upgrading "}
var appNameTails = []string{"...", " via brew cask", " for auto-update"}

// appName pulls the application being worked on out of the progress label, or
// "" when the label is about a phase rather than a particular app.
func appName(label string) string {
	if i := strings.Index(label, ": "); i >= 0 {
		label = label[i+2:]
	}
	for _, t := range appNameTails {
		label = strings.ReplaceAll(label, t, "")
	}
	for _, v := range appNameVerbs {
		if strings.HasPrefix(label, v) {
			return strings.TrimSpace(label[len(v):])
		}
	}
	return ""
}

// appsSky draws the two rows above the raccoon for `rcc apps`: the name of the
// app being updated arcs in from the right, then is eaten one letter at a time
// as it reaches the head, and the next name follows.
//
// The cycle length follows the name, so a long name is not cut short and a
// short one does not leave the sky empty.
func appsSky(tick int, name string) []string {
	if name == "" {
		name = "APP"
	}
	r := []rune(name)
	total := len(appsPath) + len(r) + 2
	i := ((tick % total) + total) % total
	rows := []string{"", ""}
	switch {
	case i < len(appsPath):
		p := appsPath[i]
		rows[p[0]] = strings.Repeat(" ", p[1]) + name
	case i < len(appsPath)+len(r):
		eaten := i - len(appsPath) + 1
		p := appsPath[len(appsPath)-1]
		rows[p[0]] = strings.Repeat(" ", p[1]+eaten) + string(r[eaten:])
	}
	return rows
}

// volume is one row of the "Space Usage" table bin/disk.sh prints.
type volume struct {
	mount string
	pct   int
}

// diskVolumes reads the Space Usage rows out of the output seen so far.
//
// It reads Percent rather than computing Used/(Used+Free) because APFS volumes
// share a container: on this Mac "/" and "/System/Volumes/Data" both report the
// same free space, and dividing per volume would claim the disk is 17% full
// when the pressure is really 86%.
func diskVolumes(lines []string) []volume {
	var vols []volume
	for _, l := range lines {
		f := strings.Split(stripANSI(l), "|")
		if len(f) < 5 {
			continue
		}
		pct := strings.TrimSpace(f[4])
		if !strings.HasSuffix(pct, "%") {
			continue
		}
		n, err := strconv.Atoi(strings.TrimSuffix(pct, "%"))
		if err != nil {
			continue // the header row says "Percent"
		}
		vols = append(vols, volume{strings.TrimSpace(f[1]), n})
	}
	return vols
}

// shortMount keeps the tail of a long mount path. "/System/Volumes/Data" is
// wider than the gauge beside it and would wrap on a narrow terminal.
func shortMount(m string) string {
	if len(m) <= 12 {
		return m
	}
	if i := strings.LastIndex(m, "/"); i > 0 && i < len(m)-1 {
		return m[i+1:]
	}
	return m
}

// diskGauge draws one bar. Ten cells, so each is ten percent.
func diskGauge(pct int) string {
	filled := (pct*10 + 50) / 100
	if filled > 10 {
		filled = 10
	}
	if filled < 0 {
		filled = 0
	}
	return "[" + strings.Repeat("#", filled) + strings.Repeat(".", 10-filled) + "]"
}

// diskFace is the raccoon's reaction to the fullest volume it has seen, not to
// the ones currently on screen: a disk about to run out must not go unnoticed
// because its row is on the next page.
func diskFace(vols []volume) string {
	worst := 0
	for _, v := range vols {
		if v.pct > worst {
			worst = v.pct
		}
	}
	switch {
	case worst >= 95:
		return "x.x"
	case worst >= 80:
		return ">.<"
	case worst >= 60:
		return "-.-"
	}
	return "o.o"
}

// diskPageTicks is how long a page of volumes stays up: 8 ticks is 2.4s, long
// enough to read four mount points before they turn over.
const diskPageTicks = 8

// diskRows returns what to hang beside each of the raccoon's four lines: one
// gauge per line. With more than four volumes the list pages round, so a fifth
// disk is shown in turn rather than dropped.
func diskRows(tick int, vols []volume) []string {
	rows := make([]string, 4)
	if len(vols) == 0 {
		return rows
	}
	pages := (len(vols) + 3) / 4
	page := (tick / diskPageTicks) % pages
	for i := 0; i < 4; i++ {
		if n := page*4 + i; n < len(vols) {
			v := vols[n]
			rows[i] = fmt.Sprintf("%s %3d%%  %s", diskGauge(v.pct), v.pct, shortMount(v.mount))
		}
	}
	return rows
}

// memMetric pulls one "| Name | 1234 MB |" row out of the memory table, in MB.
// Values arrive as "16 GB", "7709 MB" or "27965.56 MB", so the unit is read
// rather than assumed.
func memMetric(lines []string, name string) float64 {
	for _, l := range lines {
		f := strings.Split(stripANSI(l), "|")
		if len(f) < 3 || strings.TrimSpace(f[1]) != name {
			continue
		}
		v := strings.Fields(strings.TrimSpace(f[2]))
		if len(v) == 0 {
			return 0
		}
		n, err := strconv.ParseFloat(v[0], 64)
		if err != nil {
			return 0
		}
		if len(v) > 1 && strings.EqualFold(v[1], "GB") {
			n *= 1024
		}
		return n
	}
	return 0
}

// memPressure scores how hard the machine is squeezing, 0 to 100.
//
// The first term is what macOS itself calls memory pressure: wired plus
// compressed over total. Compressed alone understates it, because wired memory
// is what the kernel cannot reclaim at all.
//
// The second term is swap fill, and it is taken into account because it is a
// cliff rather than a slope: once swap cannot grow the system stalls. The worse
// of the two wins, so neither escape route goes unnoticed.
func memPressure(lines []string) int {
	worst := 0.0
	if total := memMetric(lines, "Total RAM"); total > 0 {
		worst = (memMetric(lines, "Wired") + memMetric(lines, "Compressed")) / total
	}
	if swapTotal := memMetric(lines, "Swap Total"); swapTotal > 0 {
		if s := memMetric(lines, "Swap Used") / swapTotal; s > worst {
			worst = s
		}
	}
	if worst < 0 {
		worst = 0
	}
	if worst > 1 {
		worst = 1
	}
	return int(worst*100 + 0.5)
}

// memState is the raccoon's condition. The load it carries and the repeated
// frames come from here.
type memState struct {
	eyes, muzzle, load string
	repeat             int // how many of the four frames are held still
}

// memStates run from calm to spent. Tiredness reads through repetition, not
// speed: the 300ms tick is fixed, so a tired raccoon holds the same frame for
// three beats out of four and only appears to slow down.
var memStates = []struct {
	upTo int
	st   memState
}{
	{50, memState{"", "^", "", 0}},             // calm: the frames' own eyes, roaming
	{70, memState{"*.*", "^", "[][]", 1}},      // busy: carrying things
	{90, memState{"-.-", "v", "[][][]", 2}},    // tired: mouth open, barely moving
	{101, memState{"x.x", "v", "[][][][]", 3}}, // spent
}

// memStateFor picks the state for a pressure score.
func memStateFor(pressure int) memState {
	for _, s := range memStates {
		if pressure < s.upTo {
			return s.st
		}
	}
	return memStates[len(memStates)-1].st
}

// port is one row of the table bin/ports.sh prints.
type port struct {
	number, process string
	listening       bool
}

// portsMax is how many ports the raccoon tries before showing the count. With
// thirty of them a full round would take ten seconds and the first door would
// not come back for the whole run.
const portsMax = 5

// listenPorts reads the port rows out of the output seen so far.
//
// LISTEN and ESTABLISHED are kept apart deliberately: an established connection
// is one already in progress, while a listening port is a door anyone can knock
// on. That distinction is the only security information this command carries.
func listenPorts(lines []string) []port {
	var ports []port
	for _, l := range lines {
		f := strings.Split(stripANSI(l), "|")
		if len(f) < 5 {
			continue
		}
		num := strings.TrimSpace(f[1])
		if _, err := strconv.Atoi(num); err != nil {
			continue // the header row says "PORT"
		}
		ports = append(ports, port{
			number:    num,
			process:   strings.TrimSpace(f[3]),
			listening: strings.TrimSpace(f[4]) == "LISTEN",
		})
	}
	return ports
}

// portsFace reacts to how many doors stand open, not to how many rows there are.
func portsFace(ports []port) string {
	n := 0
	for _, p := range ports {
		if p.listening {
			n++
		}
	}
	switch {
	case n >= 16:
		return ">.<"
	case n >= 6:
		return "-.-"
	}
	return "o.o"
}

// portsSlot is what to hang beside the raccoon on a given beat: the door being
// tried, then a count, then a blank beat so the round reads as having restarted.
func portsSlot(tick int, ports []port) string {
	if len(ports) == 0 {
		return ""
	}
	shown := len(ports)
	if shown > portsMax {
		shown = portsMax
	}
	listening := 0
	for _, p := range ports {
		if p.listening {
			listening++
		}
	}
	switch i := ((tick % (shown + 2)) + shown + 2) % (shown + 2); {
	case i < shown:
		p := ports[i]
		if p.listening {
			return fmt.Sprintf("[%s] %s <", p.number, p.process)
		}
		return fmt.Sprintf("[%s] %s", p.number, p.process)
	case i == shown:
		return fmt.Sprintf("... %d in ascolto", listening)
	}
	return ""
}

// batteryRow reads one "| Name | Value |" row from the battery table.
func batteryRow(lines []string, name string) string {
	for _, l := range lines {
		f := strings.Split(stripANSI(l), "|")
		if len(f) >= 3 && strings.TrimSpace(f[1]) == name {
			return strings.TrimSpace(f[2])
		}
	}
	return ""
}

// batteryPercent takes the leading number off a value like "85% (good)".
func batteryPercent(v string) int {
	v = strings.TrimSpace(v)
	i := strings.IndexFunc(v, func(r rune) bool { return r < '0' || r > '9' })
	if i <= 0 {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
		return 0
	}
	n, err := strconv.Atoi(v[:i])
	if err != nil {
		return 0
	}
	return n
}

// batteryGauge draws the cell as a battery with a terminal, so it cannot be
// mistaken for the disk gauge, which is a plain bar.
func batteryGauge(pct int) string {
	filled := (pct*8 + 50) / 100
	if filled > 8 {
		filled = 8
	}
	if filled < 0 {
		filled = 0
	}
	return "[" + strings.Repeat("#", filled) + strings.Repeat("-", 8-filled) + "]="
}

// batteryFace ages with the pack. Health below 80% or more than 700 cycles is
// where a battery starts being the reason the laptop feels worse, so both are
// read even though only the health is drawn.
func batteryFace(health, cycles int) string {
	switch {
	case health > 0 && health < 70, cycles >= 1000:
		return "x.x"
	case health > 0 && health < 80, cycles >= 700:
		return "-.-"
	}
	return "o.o"
}

// batteryBolt is the charge flowing in, shown only while actually charging.
func batteryBolt(tick int, charging bool) string {
	if !charging {
		return ""
	}
	switch ((tick % 4) + 4) % 4 {
	case 0:
		return " <"
	case 1:
		return "  <"
	case 2:
		return "   <"
	}
	return ""
}

// backupStep is the horizontal offset between raccoons in the row. Six rather
// than five: the extra column is left blank on purpose, so each head has a
// sliver of air around it instead of its neighbour's face touching it.
const backupStep = 6

// backupMax caps the row so it cannot run off a narrow terminal.
const backupMax = 4

// backupState is what bin/backup.sh managed to find out about Time Machine.
type backupState struct {
	configured bool
	hasBackup  bool
	overdue    bool
}

// readBackupState reads the Time Machine table.
//
// The script reports only the latest backup, not a list, so the row of copies
// cannot be a count of them. It stands for the act of copying instead, and what
// is read here decides whether copies appear at all and with what face.
func readBackupState(lines []string) backupState {
	var st backupState
	for _, l := range lines {
		f := strings.Split(stripANSI(l), "|")
		if len(f) < 3 {
			continue
		}
		key, val := strings.TrimSpace(f[1]), strings.TrimSpace(f[2])
		switch key {
		case "Destination":
			st.configured = val != "" && val != "Not configured"
		case "Backup":
			st.hasBackup = !strings.Contains(val, "No backup found")
			st.overdue = strings.Contains(val, "overdue")
		}
	}
	return st
}

// backupRow draws the raccoon and, behind it, the copies found so far.
//
// Drawing runs back to front and is opaque: a raccoon in front must cover the
// one behind even where its own drawing is blank, or the copies show through
// the gaps in its face.
func backupRow(eyes []string) []string {
	const width = 40
	grid := make([][]rune, 4)
	for i := range grid {
		grid[i] = []rune(strings.Repeat(" ", width))
	}
	for k := len(eyes) - 1; k >= 0; k-- {
		art := []string{"    _", `   / \_/\_`, "  ( " + eyes[k] + " )", "   > ^ <"}
		for i, l := range art {
			for c, ch := range l {
				if off := k*backupStep + c; off < width {
					grid[i][off] = ch
				}
			}
		}
	}
	out := make([]string, 4)
	for i, g := range grid {
		out[i] = strings.TrimRight(string(g), " ")
	}
	return out
}

// backupEyes builds the row for a beat: the front raccoon wears the verdict,
// and the copies pile up behind it while the copying is under way.
func backupEyes(tick int, st backupState) []string {
	switch {
	case !st.configured, !st.hasBackup:
		return []string{"x.x"} // alone, with nothing behind: the loudest frame here
	case st.overdue:
		return []string{"-.-", "-.-"}
	}
	n := ((tick % backupMax) + backupMax) % backupMax
	eyes := []string{"^.^"}
	for i := 0; i < n; i++ {
		eyes = append(eyes, "o.o")
	}
	return eyes
}

// sshKey is one key bin/ssh.sh reported on, with the worst thing found about it.
type sshKey struct {
	name  string
	issue string // "", "nopass", "perms", "orphan"
}

// sshGlyph draws the key so its shape carries the verdict. The words are
// already in the table underneath; a key that visibly cannot close says the
// same thing without being read.
func sshGlyph(issue string) string {
	switch issue {
	case "nopass":
		return "o--" // no teeth: it locks nothing
	case "perms":
		return "o=/" // bent tooth: the file is readable by others
	case "orphan":
		return "o=?" // a key with nothing to match it
	}
	return "o=="
}

// sshRank orders the problems so the worst one wins both the face and the key.
var sshRank = map[string]int{"": 0, "orphan": 1, "perms": 2, "nopass": 3}

// readSSHKeys walks the three tables ssh.sh prints, keeping the worst finding
// per key. Sections are tracked because the tables have different columns and a
// row means nothing without knowing which one it came from.
func readSSHKeys(lines []string) []sshKey {
	var section string
	order := []string{}
	worst := map[string]string{}
	for _, raw := range lines {
		l := stripANSI(raw)
		switch {
		case strings.Contains(l, "Unprotected Keys"):
			section = "nopass"
			continue
		case strings.Contains(l, "Orphan Keys"):
			section = "orphan"
			continue
		case strings.Contains(l, "Key Permissions"):
			section = "perms"
			continue
		}
		f := strings.Split(l, "|")
		if section == "" || len(f) < 3 {
			continue
		}
		name := strings.TrimSpace(f[1])
		status := strings.TrimSpace(f[len(f)-2])
		if name == "" || name == "Key" || name == "None" || strings.HasPrefix(name, "---") {
			continue
		}
		issue := section
		if status == "OK" {
			issue = ""
		}
		if _, seen := worst[name]; !seen {
			order = append(order, name)
		}
		if sshRank[issue] >= sshRank[worst[name]] {
			worst[name] = issue
		}
	}
	keys := make([]sshKey, 0, len(order))
	for _, n := range order {
		keys = append(keys, sshKey{n, worst[n]})
	}
	return keys
}

// sshFace follows the worst key anywhere, not the one currently on show: ten
// good keys must not hide the one left without a passphrase.
func sshFace(keys []sshKey) string {
	worst := ""
	for _, k := range keys {
		if sshRank[k.issue] > sshRank[worst] {
			worst = k.issue
		}
	}
	switch worst {
	case "nopass":
		return ">.<"
	case "perms", "orphan":
		return "-.-"
	}
	return "o.o"
}

// sshSlot is the key being tried on this beat, then a blank beat so a single
// key does not sit frozen and a long ring reads as having come round again.
func sshSlot(tick int, keys []sshKey) string {
	if len(keys) == 0 {
		return ""
	}
	i := ((tick % (len(keys) + 1)) + len(keys) + 1) % (len(keys) + 1)
	if i == len(keys) {
		return ""
	}
	k := keys[i]
	if k.issue == "" {
		return fmt.Sprintf("%s  %s", sshGlyph(k.issue), k.name)
	}
	return fmt.Sprintf("%s  %s  !", sshGlyph(k.issue), k.name)
}

// repoStatus is one row of the Git Repositories table.
type repoStatus struct {
	name                  string
	uncommitted, unpushed int
}

// gitMax caps how many repositories the row cycles through. Fifteen would take
// five seconds to come round, by which time the first is long forgotten.
const gitMax = 8

// gitCount pulls "416 uncommitted" or "2 unpushed" out of an issues cell.
func gitCount(issues, word string) int {
	i := strings.Index(issues, word)
	if i < 0 {
		return 0
	}
	fields := strings.Fields(issues[:i])
	if len(fields) == 0 {
		return 0
	}
	n, err := strconv.Atoi(strings.TrimSuffix(fields[len(fields)-1], ","))
	if err != nil {
		return 0
	}
	return n
}

// readRepos reads the Git Repositories table.
func readRepos(lines []string) []repoStatus {
	var repos []repoStatus
	for _, raw := range lines {
		f := strings.Split(stripANSI(raw), "|")
		if len(f) < 3 {
			continue
		}
		name, issues := strings.TrimSpace(f[1]), strings.TrimSpace(f[2])
		if name == "" || name == "Repository" || strings.HasPrefix(name, "---") {
			continue
		}
		repos = append(repos, repoStatus{
			name:        name,
			uncommitted: gitCount(issues, "uncommitted"),
			unpushed:    gitCount(issues, "unpushed"),
		})
		if len(repos) == gitMax {
			break
		}
	}
	return repos
}

// gitSymbols draws the gap between what is in hand and what is safe:
// "~" is an uncommitted change, "o" a commit that exists but has not left, and
// "|" is the remote. The distance never closes, because rcc git only looks —
// bin/git.sh cannot push, and showing a symbol crossing would be a lie.
func gitSymbols(r repoStatus) string {
	const cap = 4
	n := func(v int) int {
		if v > cap {
			return cap
		}
		return v
	}
	s := strings.Repeat("~", n(r.uncommitted)) + strings.Repeat("o", n(r.unpushed))
	if s == "" {
		return ""
	}
	return s + "  |"
}

// gitRise is the counterpart, and the only thing here that moves: on a repo
// with nothing pending the signal climbs the four rows and reaches the remote.
// It is shown only when nothing is in hand, so movement always means safety.
func gitRise(tick int) []string {
	rows := []string{"", "", "", ""}
	switch ((tick % 4) + 4) % 4 {
	case 0:
		rows[2] = "o      |"
	case 1:
		rows[1] = "  o    |"
		rows[2] = "       |"
	case 2:
		rows[0] = "    o  |"
		rows[1] = "       |"
		rows[2] = "       |"
	default:
		rows[2] = "       |"
	}
	return rows
}

// gitFace follows the worst repository anywhere in the list.
func gitFace(repos []repoStatus) string {
	worst := 0
	for _, r := range repos {
		if p := r.uncommitted + r.unpushed; p > worst {
			worst = p
		}
	}
	switch {
	case worst >= 100:
		return "x.x"
	case worst >= 10:
		return ">.<"
	case worst > 0:
		return "-.-"
	}
	return "o.o"
}

// dockerMax is how tall the stack can grow beside the raccoon: three boxes and
// then a count, because the art is only four lines high.
const dockerMax = 3

// dockerCounts reads the container table: how many are up, how many are not.
// "Up 2 hours" is running; anything else ("Exited (0) 3 days ago") is not.
func dockerCounts(lines []string) (running, stopped int) {
	for _, raw := range lines {
		l := stripANSI(raw)
		f := strings.Split(l, "|")
		if len(f) < 4 {
			continue
		}
		id, status := strings.TrimSpace(f[1]), strings.TrimSpace(f[3])
		if id == "" || id == "Container ID" || strings.HasPrefix(id, "---") || status == "" {
			continue
		}
		if strings.HasPrefix(status, "Up") {
			running++
		} else if status != "Status" && status != "-" {
			stopped++
		}
	}
	return running, stopped
}

// dockerMissing is true while Docker is not installed or not running, which is
// its own state rather than an error: the stack has nothing to be made of.
func dockerMissing(lines []string) bool {
	for _, l := range lines {
		if strings.Contains(stripANSI(l), "Docker is not installed") {
			return true
		}
	}
	return false
}

// dockerStack builds the pile beside the raccoon, one box added per beat.
//
// The raccoon is counting, not starting anything: rcc docker only looks, so the
// arrow marks the container being tallied on this beat rather than one being
// brought up. Running containers sit at the bottom, stopped ones on top, so the
// base of the pile is what is actually working and the cap is what was left on.
func dockerStack(tick, running, stopped int) []string {
	rows := []string{"", "", "", ""}
	total := running + stopped
	if total == 0 {
		return rows
	}
	shown := total
	if shown > dockerMax {
		shown = dockerMax
	}
	// One box per beat, then a beat holding the full pile before it starts over.
	n := ((tick % (shown + 1)) + shown + 1) % (shown + 1)
	if n == 0 {
		n = shown
	}
	for i := 0; i < n; i++ {
		box := "[o]"
		if i >= running {
			box = "[z]"
		}
		if i == n-1 && n < shown {
			box += "  <"
		}
		if i == shown-1 && total > dockerMax {
			box += fmt.Sprintf("  +%d", total-dockerMax)
		}
		rows[2-i] = box
	}
	return rows
}

// dockerFace: forgotten containers are the thing worth noticing here, since a
// stopped one still holds its disk. Docker being absent is a choice, not a fault.
func dockerFace(missing bool, running, stopped int) string {
	switch {
	case missing:
		return "-.-"
	case stopped >= 5:
		return ">.<"
	case stopped > 0:
		return "-.-"
	case running > 0:
		return "*.*"
	}
	return "o.o"
}

// derivedDataGB reads the DerivedData size, in gigabytes.
//
// The value comes from du, so it arrives as "0B", "450M" or "12G"; the suffix
// is read rather than assumed, since mistaking megabytes for gigabytes would
// bury a clean machine under a mountain of rubble.
func derivedDataGB(lines []string) float64 {
	for _, raw := range lines {
		f := strings.Split(stripANSI(raw), "|")
		if len(f) < 3 || strings.TrimSpace(f[1]) != "Size" {
			continue
		}
		v := strings.TrimSpace(f[2])
		if v == "" {
			return 0
		}
		unit := v[len(v)-1]
		n, err := strconv.ParseFloat(strings.TrimRight(v, "BKMGTi"), 64)
		if err != nil {
			return 0
		}
		switch unit {
		case 'T':
			return n * 1024
		case 'G':
			return n
		case 'M':
			return n / 1024
		case 'K':
			return n / (1024 * 1024)
		}
		return 0 // plain bytes: not worth a grain
	}
	return -1 // the table has not been printed yet
}

// xcodeHeap is the pile of build leftovers, as tall as the cache is big.
//
// DerivedData is a cache: it regenerates itself, so everything drawn here is
// space you could take back today. The ground line stays even at zero, so an
// empty patch reads as empty rather than as a missing drawing.
func xcodeHeap(gb float64) []string {
	switch {
	case gb <= 0:
		return []string{"", "", "", "___________"}
	case gb < 1:
		return []string{"", "", ".", "_._________"}
	case gb < 5:
		return []string{"", "", ".:.", "_.:._______"}
	case gb < 20:
		return []string{"", ".", ".:::.", "_.:::._____"}
	}
	return []string{"  .:.", ".:::.", ".:::::.", "_.:::::.___"}
}

// xcodeFace: a cache worth several gigabytes is the reason to run this at all.
func xcodeFace(gb float64) string {
	switch {
	case gb >= 20:
		return "x.x"
	case gb >= 5:
		return ">.<"
	case gb >= 1:
		return "-.-"
	}
	return "o.o"
}

// envWindow is how many PATH entries the trail shows at once. Twenty would run
// past the width of a terminal, so the trail pages instead of shrinking.
const envWindow = 12

// readPathEntries reads the PATH Entries table, keeping only whether each
// directory is there. Order is preserved because in a PATH order is the point:
// what matters is where the holes fall among the good stones.
func readPathEntries(lines []string) []bool {
	var ok []bool
	inTable := false
	for _, raw := range lines {
		l := stripANSI(raw)
		if strings.Contains(l, "PATH Entries") {
			inTable = true
			continue
		}
		if strings.Contains(l, "Broken Symlinks") || strings.Contains(l, "Duplicate PATH") {
			inTable = false
		}
		f := strings.Split(l, "|")
		if !inTable || len(f) < 3 {
			continue
		}
		path, status := strings.TrimSpace(f[1]), strings.TrimSpace(f[2])
		if !strings.HasPrefix(path, "/") {
			continue // header and rules
		}
		ok = append(ok, status == "OK")
	}
	return ok
}

// envTrail draws the trail and the raccoon walking it.
//
// "==" is a directory that exists; a gap is one the shell searches on every
// single command and never finds. He walks a page at a time, so a long PATH is
// seen whole rather than truncated.
func envTrail(tick int, entries []bool) []string {
	rows := []string{"", "", "", ""}
	if len(entries) == 0 {
		return rows
	}
	i := ((tick % len(entries)) + len(entries)) % len(entries)
	start := (i / envWindow) * envWindow
	end := start + envWindow
	if end > len(entries) {
		end = len(entries)
	}
	var trail strings.Builder
	for _, present := range entries[start:end] {
		if present {
			trail.WriteString("== ")
		} else {
			trail.WriteString("   ")
		}
	}
	rows[1] = strings.Repeat(" ", (i-start)*3) + "o"
	rows[2] = strings.TrimRight(trail.String(), " ")
	return rows
}

// envFace counts the holes: each one is a directory every command you type
// walks through for nothing.
func envFace(entries []bool) string {
	missing := 0
	for _, present := range entries {
		if !present {
			missing++
		}
	}
	switch {
	case missing >= 5:
		return ">.<"
	case missing > 0:
		return "-.-"
	}
	return "o.o"
}

// startupShown is how many followers fit before the rest become a count.
const startupShown = 8

// countStartupItems adds up what actually wakes with the Mac: the launch agents,
// the daemons and the login items.
//
// The "Running Services" step is deliberately skipped. Its 500-odd entries are
// everything running right now, most of it started long after boot by the system
// itself, and folding that in would drown the handful of things you chose.
func countStartupItems(lines []string) int {
	section, total := "", 0
	for _, raw := range lines {
		l := stripANSI(raw)
		for _, s := range []string{"User LaunchAgents", "System LaunchAgents",
			"LaunchDaemons", "Login Items", "Running Services", "System Uptime"} {
			if strings.Contains(l, s) {
				section = s
			}
		}
		f := strings.Split(l, "|")
		if len(f) < 3 {
			continue
		}
		switch section {
		case "User LaunchAgents", "Login Items":
			if strings.HasPrefix(strings.TrimSpace(f[1]), "✓") {
				total++
			}
		case "System LaunchAgents", "LaunchDaemons":
			if strings.HasPrefix(strings.TrimSpace(f[1]), "/") {
				if n, err := strconv.Atoi(strings.TrimSpace(f[2])); err == nil {
					total += n
				}
			}
		}
	}
	return total
}

// startupTrail is the procession behind him: one dot per thing that started
// with the Mac and has been following you around ever since.
//
// They arrive one per beat, which is the only motion, and stay — that staying
// is the point, since a login item is not an event at boot but a companion for
// the whole session.
func startupTrail(tick, items int) string {
	if items <= 0 {
		return ""
	}
	shown := items
	if shown > startupShown {
		shown = startupShown
	}
	n := ((tick % (shown + 1)) + shown + 1) % (shown + 1)
	if n == 0 {
		n = shown
	}
	trail := strings.TrimRight(strings.Repeat(". ", n), " ")
	if n == shown && items > startupShown {
		trail += fmt.Sprintf("  +%d", items-startupShown)
	}
	return trail
}

// startupFace: a handful of companions is normal, thirty is a slow login and a
// permanently busy machine.
func startupFace(items int) string {
	switch {
	case items >= 30:
		return ">.<"
	case items >= 15:
		return "-.-"
	}
	return "o.o"
}

// trashLevels are the bin's two inner rows as it fills, bottom row first. The
// level rises from the floor, so what reads is how full it is rather than a
// texture. It is a closed bin, unlike the heap xcode leaves on the ground: a
// build cache regenerates itself, whereas this is what you meant to throw away.
var trashLevels = [][2]string{
	{"   ", "   "},
	{" . ", "   "},
	{".:.", " . "},
	{":::", ".:."},
}

// trashGB reads the Trash size, in gigabytes. The value comes from du, so the
// unit travels with it.
func trashGB(lines []string) float64 {
	for _, raw := range lines {
		f := strings.Split(stripANSI(raw), "|")
		if len(f) < 3 || strings.TrimSpace(f[1]) != "Size" {
			continue
		}
		v := strings.TrimSpace(f[2])
		if v == "" {
			return 0
		}
		n, err := strconv.ParseFloat(strings.TrimRight(v, "BKMGTi"), 64)
		if err != nil {
			return 0
		}
		switch v[len(v)-1] {
		case 'T':
			return n * 1024
		case 'G':
			return n
		case 'M':
			return n / 1024
		}
		return 0
	}
	return -1
}

// trashItems reads the names under "Recent Items", which is what the raccoon
// fishes out. Six gigabytes in two files is a different problem from six
// gigabytes in ten thousand, and only the names tell you which you have.
func trashItems(lines []string) []string {
	var items []string
	in := false
	for _, raw := range lines {
		l := stripANSI(raw)
		if strings.Contains(l, "Recent Items") {
			in = true
			continue
		}
		f := strings.Split(l, "|")
		if !in || len(f) < 2 {
			continue
		}
		name := strings.TrimSpace(f[1])
		if name == "" || name == "Item" || strings.HasPrefix(name, "---") {
			continue
		}
		items = append(items, name)
	}
	return items
}

// trashLevel maps gigabytes onto the four fill levels.
func trashLevel(gb float64) int {
	switch {
	case gb >= 5:
		return 3
	case gb >= 1:
		return 2
	case gb > 0:
		return 1
	}
	return 0
}

// trashBin draws the bin and, on this beat, whatever he has pulled out of it.
func trashBin(tick int, gb float64, items []string) []string {
	lv := trashLevels[trashLevel(gb)]
	name := ""
	if len(items) > 0 {
		if i := ((tick % (len(items) + 1)) + len(items) + 1) % (len(items) + 1); i < len(items) {
			name = "  " + items[i]
		}
	}
	return []string{" .---.", "|" + lv[1] + "|", "|" + lv[0] + "|" + name, "'---'"}
}

// trashFace: a few gigabytes sitting in the bin is space you already decided
// you did not want.
func trashFace(gb float64) string {
	switch {
	case gb >= 20:
		return "x.x"
	case gb >= 5:
		return ">.<"
	case gb >= 1:
		return "-.-"
	}
	return "o.o"
}

// fontIssues reads the duplicate families and the corrupted files.
//
// Duplicates are what tires him: the same family installed twice is a font every
// application loads twice at launch for nothing. A corrupted file is worse than
// tiring, since it can take an app down with it.
func fontIssues(lines []string) (duplicates, corrupted int) {
	for _, raw := range lines {
		f := strings.Split(stripANSI(raw), "|")
		if len(f) < 3 {
			continue
		}
		key, val := strings.TrimSpace(f[1]), strings.TrimSpace(f[2])
		switch key {
		case "Duplicates":
			if fields := strings.Fields(val); len(fields) > 0 {
				if n, err := strconv.Atoi(fields[0]); err == nil {
					duplicates = n // "12 families"; "none found" parses as nothing
				}
			}
		case "Corrupted fonts":
			if n, err := strconv.Atoi(val); err == nil {
				corrupted = n
			}
		}
	}
	return duplicates, corrupted
}

// fontSamples are the pages he turns while reading.
var fontSamples = []string{"Aa", "Bb", "Cc", "Dd", "Ee", "Ff"}

// fontsPage is the page open on this beat. Past a certain number of duplicates
// he nods off on the last page of the round, which is the joke and also the
// point: he is reading the same families over and over.
func fontsPage(tick, duplicates int) string {
	n := len(fontSamples)
	i := ((tick % n) + n) % n
	if duplicates >= 10 && i == n-1 {
		return "zz"
	}
	return fontSamples[i]
}

// fontsFace tires with the duplicates, and gives up on a corrupted file.
func fontsFace(duplicates, corrupted int) string {
	switch {
	case corrupted > 0:
		return "x.x"
	case duplicates >= 10:
		return ">.<"
	case duplicates > 0:
		return "-.-"
	}
	return "o.o"
}

// fontsBook draws the open book with the page he is on.
func fontsBook(page string) []string {
	return []string{",---.---.", "|" + fmt.Sprintf("%-3s", page) + "|   |", "|   |   |", "'---'---'"}
}

// historyShown is how many commands one unrolling shows before it rolls back up.
const historyShown = 5

// recentCommands reads the Recent Commands table.
func recentCommands(lines []string) []string {
	var cmds []string
	in := false
	for _, raw := range lines {
		l := stripANSI(raw)
		if strings.Contains(l, "Recent Command") {
			in = true
			continue
		}
		f := strings.Split(l, "|")
		if !in || len(f) < 2 {
			continue
		}
		c := strings.TrimSpace(f[1])
		if c == "" || strings.HasPrefix(c, "---") {
			continue
		}
		cmds = append(cmds, c)
		if len(cmds) == historyShown {
			break
		}
	}
	return cmds
}

// historyTotal reads the Total row of the command counts.
func historyTotal(lines []string) int {
	for _, raw := range lines {
		f := strings.Split(stripANSI(raw), "|")
		if len(f) >= 3 && strings.TrimSpace(f[1]) == "Total" {
			if n, err := strconv.Atoi(strings.TrimSpace(f[2])); err == nil {
				return n
			}
		}
	}
	return 0
}

// historyScroll unrolls the scroll a stretch at a time, one command riding each
// stretch, then rolls back up and starts again.
//
// The length is time, not volume: the number of commands is already in the table
// and the scroll would have to be metres long to show two thousand of them. What
// the scroll carries that the table does not is the commands themselves, going
// past one at a time.
func historyScroll(tick int, cmds []string, total int) string {
	if len(cmds) == 0 {
		return ""
	}
	n := len(cmds) + 1
	i := ((tick % n) + n) % n
	if i == len(cmds) {
		if total > 0 {
			return fmt.Sprintf(")%s  %d in tutto", strings.Repeat("=", 3*len(cmds)), total)
		}
		return ""
	}
	return fmt.Sprintf(")%s %s", strings.Repeat("=", 3*(i+1)), cmds[i])
}

// certWallWidth is how wide the wall is drawn. The counts are scaled onto it,
// since forty-two uprights would not fit beside the raccoon.
const certWallWidth = 24

// certCounts reads the certificate summary. That step prints a plain aligned
// table rather than a piped one, so the header is found and the numbers are
// taken from the next line that has five of them.
func certCounts(lines []string) (total, valid, expiring, expired int) {
	seenHeader := false
	for _, raw := range lines {
		l := stripANSI(raw)
		if strings.Contains(l, "Total") && strings.Contains(l, "Expired") {
			seenHeader = true
			continue
		}
		if !seenHeader {
			continue
		}
		var nums []int
		for _, f := range strings.Fields(l) {
			if n, err := strconv.Atoi(f); err == nil {
				nums = append(nums, n)
			}
		}
		if len(nums) >= 4 {
			return nums[0], nums[1], nums[2], nums[3]
		}
	}
	return 0, 0, 0, 0
}

// certWall draws the certificates as a wall: an upright for each one still
// standing, a gap where one has expired, "!" for one about to.
//
// The gaps are spread through the wall rather than collected at one end,
// because a wall with holes across it reads as broken, while the same holes
// gathered in a corner read as a wall that is simply shorter.
func certWall(total, valid, expiring, expired int) string {
	if total <= 0 {
		return ""
	}
	wall := []rune(strings.Repeat("|", certWallWidth))
	scale := func(n int) int { return (n*certWallWidth + total/2) / total }
	gaps, warns := scale(expired), scale(expiring)
	// Spread the gaps evenly: position i of n lands at (i+0.5)/n of the width.
	for i := 0; i < gaps && i < certWallWidth; i++ {
		wall[(2*i+1)*certWallWidth/(2*gaps)] = ' '
	}
	placed := 0
	for i := range wall {
		if placed == warns {
			break
		}
		if wall[i] == '|' && i%3 == 2 {
			wall[i] = '!'
			placed++
		}
	}
	return strings.TrimRight(string(wall), " ")
}

// certFace: an expired certificate is one your Mac still carries around and no
// longer trusts, and fourteen of them is a keychain nobody has looked at.
func certFace(total, expired, expiring int) string {
	switch {
	case total > 0 && expired*3 >= total:
		return ">.<"
	case expired > 0:
		return "-.-"
	case expiring > 0:
		return "-.-"
	}
	return "o.o"
}

// wifiArcs is the wave field's repeating unit. Sparse rather than dense: a
// crowded field swallows the network name travelling through it.
const wifiArcs = ")  "

// wifiRows is how many rows of arcs there are — the raccoon's full height, so
// the field is a field rather than a stripe.
const wifiRows = 4

// readWifi reads the remembered networks and whichever one is joined now.
//
// The names are the point: a Mac keeps looking for every network it has ever
// joined, so a list full of airports and hotels is a list of places it keeps
// announcing it has been.
func readWifi(lines []string) (networks []string, active string) {
	section := ""
	for _, raw := range lines {
		l := stripANSI(raw)
		switch {
		case strings.Contains(l, "Active Connection"):
			section = "active"
			continue
		case strings.Contains(l, "Known Networks"):
			section = "known"
			continue
		}
		f := strings.Split(l, "|")
		if len(f) < 2 {
			continue
		}
		name := strings.TrimSpace(f[1])
		if name == "" || strings.HasPrefix(name, "---") {
			continue
		}
		switch section {
		case "active":
			if name != "Not connected" {
				active = name
			}
		case "known":
			networks = append(networks, name)
		}
	}
	return networks, active
}

// wifiField draws the wave field with one network name sailing through it.
//
// Every row is offset from the one above and the whole field shifts each beat,
// so the waves move while the name crosses from left to right. The name is set
// into the arcs rather than replacing the row: the field carries on either side
// of it.
func wifiField(tick, width int, networks []string, active string) []string {
	if width < 20 {
		width = 20
	}
	rows := make([]string, wifiRows)
	band := strings.Repeat(wifiArcs, width/len(wifiArcs)+2)
	for r := range rows {
		off := ((tick+r)%len(wifiArcs) + len(wifiArcs)) % len(wifiArcs)
		rows[r] = band[off : off+width]
	}
	if len(networks) == 0 {
		for r := range rows {
			rows[r] = strings.TrimRight(rows[r], " ")
		}
		return rows
	}
	// Each network gets a crossing of its own, then the next one enters.
	step := width / 8
	if step < 2 {
		step = 2
	}
	legs := width/step + 1
	i := ((tick/legs)%len(networks) + len(networks)) % len(networks)
	name := networks[i]
	if name == active {
		name = "[" + name + "]"
	}
	label := " " + name + " "
	pos := (tick % legs) * step
	if pos+len(label) > width {
		pos = width - len(label)
	}
	if pos < 0 {
		pos = 0
	}
	mid := []rune(rows[wifiRows/2])
	for k, ch := range label {
		if pos+k < len(mid) {
			mid[pos+k] = ch
		}
	}
	rows[wifiRows/2] = string(mid)
	for r := range rows {
		rows[r] = strings.TrimRight(rows[r], " ")
	}
	return rows
}

// clash is one command name that resolves through more than one manager.
type clash struct {
	name     string
	managers []string // in PATH order: the first one is the one that wins
}

// overlapMax caps how many clashes the animation walks through.
const overlapMax = 6

// readOverlaps groups the overlap map by command name and keeps the names that
// two different managers both provide.
//
// Same-manager duplicates are dropped on purpose: brew shipping a file twice
// changes nothing about what runs, while brew and the system both providing
// "python" is the case that costs an afternoon.
func readOverlaps(lines []string) []clash {
	order := []string{}
	seen := map[string][]string{}
	for _, raw := range lines {
		f := strings.Split(stripANSI(raw), "|")
		if len(f) < 5 {
			continue
		}
		name, manager := strings.TrimSpace(f[1]), strings.TrimSpace(f[4])
		if name == "" || name == "NAME" || strings.HasPrefix(name, "---") || manager == "" {
			continue
		}
		if _, ok := seen[name]; !ok {
			order = append(order, name)
		}
		if !slices.Contains(seen[name], manager) {
			seen[name] = append(seen[name], manager)
		}
	}
	var out []clash
	for _, n := range order {
		if len(seen[n]) > 1 {
			out = append(out, clash{n, seen[n]})
			if len(out) == overlapMax {
				break
			}
		}
	}
	return out
}

// overlapFork draws the fork: the command on top, the places it lives below,
// and "<" on the one that actually runs.
//
// It is the only drawing here that uses height rather than hanging things to
// the right, because a fork needs two lines under one to be a fork — and that
// makes the command recognisable from its shape before it is read.
func overlapFork(tick int, clashes []clash) []string {
	rows := []string{"", "", "", ""}
	if len(clashes) == 0 {
		return rows
	}
	i := ((tick/3)%len(clashes) + len(clashes)) % len(clashes)
	c := clashes[i]
	name := c.name
	if len(c.managers) > 2 {
		name = fmt.Sprintf("%s  +%d", name, len(c.managers)-2)
	}
	rows[1] = name
	rows[2] = "  \\_ " + c.managers[0] + "   <"
	rows[3] = "  \\_ " + c.managers[1]
	return rows
}

// overlapFace: a couple of clashes is life on a Mac with Homebrew; a dozen
// means you no longer know which binary you are running.
func overlapFace(clashes []clash) string {
	switch {
	case len(clashes) >= overlapMax:
		return ">.<"
	case len(clashes) > 0:
		return "-.-"
	}
	return "o.o"
}

// fleetHost is one machine bin/fleet.sh reached, or failed to.
type fleetHost struct {
	name   string
	status rune // 'o' clean, '!' reached with findings, 'x' unreachable
}

// fleetMax is how many machines fit in the row before the rest are counted.
const fleetMax = 6

// readFleetHosts reads the per-host lines of the fleet report.
//
// fleet does not print a table: each host is a line beginning with an icon, so
// the icon is what identifies a host line. ✓ and ⚠ both mean the machine
// answered — the difference is what it had to say — while ✗ means it never did.
func readFleetHosts(lines []string) []fleetHost {
	var hosts []fleetHost
	for _, raw := range lines {
		l := strings.TrimSpace(stripANSI(raw))
		var st rune
		switch {
		case strings.HasPrefix(l, "✓"):
			st = 'o'
		case strings.HasPrefix(l, "⚠"):
			st = '!'
		case strings.HasPrefix(l, "✗"):
			st = 'x'
		default:
			continue
		}
		fields := strings.Fields(l)
		if len(fields) < 2 {
			continue
		}
		hosts = append(hosts, fleetHost{fields[1], st})
	}
	return hosts
}

// fleetVision is the out-of-body cycle: he goes under, leaves, the machines
// appear around him as visions, and he comes back.
//
// The body stays behind with an empty face while he is away, which is what an
// SSH audit actually is — he is not sending a probe from here, he is inside
// those machines. Each vision wears that machine's own state, so the drawing
// carries the report rather than decorating it.
//
// Returns the eyes to wear and the row of visions to hang beside him.
func fleetVision(tick int, hosts []fleetHost) (eyes, row string) {
	if len(hosts) == 0 {
		return "", ""
	}
	shown := len(hosts)
	if shown > fleetMax {
		shown = fleetMax
	}
	// still, going under, one beat per machine, surfacing, back
	total := shown + 3
	i := ((tick % total) + total) % total
	switch {
	case i == 0:
		return "o.o", ""
	case i == 1:
		return "@.@", "~"
	case i == total-1:
		return "@.@", strings.TrimSpace(strings.Repeat("~ ", shown))
	}
	var b strings.Builder
	b.WriteString("~")
	for k := 0; k < i-1; k++ {
		face := "o.o"
		switch hosts[k].status {
		case '!':
			face = "-.-"
		case 'x':
			face = "x.x"
		}
		fmt.Fprintf(&b, " (%s) ~", face)
	}
	if i-1 == shown && len(hosts) > fleetMax {
		fmt.Fprintf(&b, "  +%d", len(hosts)-fleetMax)
	}
	// The body is empty while he is out in them.
	return " . ", b.String()
}

// fleetFace: one machine that cannot be reached is the finding here — an audit
// that skipped a host tells you nothing about it.
func fleetFace(hosts []fleetHost) string {
	unreachable, issues := 0, 0
	for _, h := range hosts {
		switch h.status {
		case 'x':
			unreachable++
		case '!':
			issues++
		}
	}
	switch {
	case unreachable > 0:
		return ">.<"
	case issues > 0:
		return "-.-"
	}
	return "o.o"
}

// boxRegexp matches the package box beside the raccoon in the upgrade frames.
// Always three characters, so swapping it can never shift the art.
var boxRegexp = regexp.MustCompile(`\[.\]`)

// phaseBox turns the phase a script declared into the box the raccoon holds.
// upgrade and apps both announce the same vocabulary — checking, fetching,
// downloading, installing, completed — so they share one reading of it.
//
// The box shows work in progress, never a verdict: these commands replace
// things rather than inspect them, and the report underneath owns the outcome.
func phaseBox(label string) (box, eyes string) {
	switch {
	case strings.Contains(label, "error"):
		return "[!]", ">.<" // the only phase that overrides the frame's own eyes
	case strings.Contains(label, "fetching"), strings.Contains(label, "downloading"):
		return "[.]", ""
	case strings.Contains(label, "installing"), strings.Contains(label, "updating"),
		strings.Contains(label, "upgrading"):
		return "[=]", ""
	case strings.Contains(label, "completed"), strings.Contains(label, "updated"):
		return "[#]", ""
	}
	return "[ ]", ""
}

// eyeRegexp matches the raccoon's eye field: the three characters between the
// parentheses. Only that field is ever rewritten, so the silhouette — ears,
// head and muzzle — is identical in every frame.
var eyeRegexp = regexp.MustCompile(`\( ... \)`)

// auditMood reads the results the audit has printed so far and returns the eyes
// that match them, or "" to leave the frame's own eyes alone.
//
// It exists so the animation reports rather than mimes. An audit produces PASS,
// WARN and FAIL in the same run, so a fixed final frame would announce an
// outcome the run has not reached; counting what actually streamed past cannot
// contradict the report printed underneath.
//
// Both icon sets are counted: common.sh falls back to OK/XX when the terminal
// cannot render the glyphs, and the mood must survive that fallback.
func auditMood(lines []string) string {
	fails, warns := 0, 0
	for _, l := range lines {
		s := stripANSI(l)
		switch {
		case strings.Contains(s, "✗") || strings.Contains(s, "XX"):
			fails++
		case strings.Contains(s, "⚠"):
			warns++
		}
	}
	switch {
	case fails > 0:
		return ">.<"
	case warns > 2:
		return "O.O"
	case warns > 0:
		return "-.-"
	}
	return ""
}

var ansiRegexp = regexp.MustCompile(`\x1b\[[0-9;]*[a-zA-Z]`)

const progressPrefix = "__RCC_PROGRESS__:"

func stripANSI(s string) string {
	return ansiRegexp.ReplaceAllString(s, "")
}

// isProgressLine checks if a line is a machine-parseable progress marker.
// Format: __RCC_PROGRESS__:current:total:label
func isProgressLine(line string) (ok bool, current, total int, label string) {
	if !strings.HasPrefix(line, progressPrefix) {
		return false, 0, 0, ""
	}
	rest := line[len(progressPrefix):]
	parts := strings.SplitN(rest, ":", 3)
	if len(parts) < 3 {
		return false, 0, 0, ""
	}
	current, err := strconv.Atoi(parts[0])
	if err != nil {
		return false, 0, 0, ""
	}
	total, err = strconv.Atoi(parts[1])
	if err != nil {
		return false, 0, 0, ""
	}
	return true, current, total, parts[2]
}

// ─── Warm/Cozy palette — Raccoon Den ───────────────────────
// All L* (OKLCH lightness) ≥ 55 for dark-terminal readability

var (
	styleTitle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#eac880")). // honey gold, L~78
			Bold(true)

	styleDesc = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#b09e88")) // warm tan, L~66

	styleSelected = lipgloss.NewStyle().
			Background(lipgloss.Color("#d4904b")). // amber/copper
			Foreground(lipgloss.Color("#1a1512")). // dark warm
			Padding(0, 1)

	styleItem = lipgloss.NewStyle().
			Padding(0, 1)

	styleFooter = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#9a8a7a")) // muted warm, L~58

	styleSearch = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#eac880")). // honey gold
			Bold(true)

	styleOutput = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#ddd0be")) // warm cream, L~84

	styleError = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#d46a5a")) // warm rose, L~55

	styleSuccess = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#a8c88e")) // soft sage, L~76

	styleWarning = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#d4a74b")) // warm gold, L~68

	styleMuted = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#8a7d6e")) // medium warm, L~53

	styleProgressEmpty = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#5a5045")) // bar track, L~38

	styleProgressFill = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#e0a050")) // amber fill, L~68

	styleProgressLabel = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#b0a090")) // progress info text

	styleStatusSuccess = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#a8c88e")) // soft sage, L~76

	styleStatusError = lipgloss.NewStyle().
				Foreground(lipgloss.Color("#d46a5a")) // warm rose, L~55
)

// ─── Item ──────────────────────────────────────────────────

type item struct {
	title       string
	script      string
	args        []string // extra argv passed to the script (e.g. fleet subcommand)
	description string
	needsSudo   bool // authenticate before starting: the script touches system paths
}

type modelState int

const (
	stateMenu modelState = iota
	stateSearch
	stateRunning
	stateOutput
)

type model struct {
	items    []item
	selected int
	state    modelState

	searchQuery string
	binPath     string
	width       int
	height      int

	// Streaming
	cmd           *exec.Cmd // stored from message for kill signal
	spinnerFrame  int
	currentScript string
	pendingArgs   []string // argv of the script started after sudo is primed
	outputTitle   string

	// Progress
	progressCurr  int
	progressTotal int
	progressLabel string

	// Output
	outputLines   []string
	outputScroll  int
	outputSuccess bool
}

// ─── Helpers ───────────────────────────────────────────────

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func resolveBinPath() string {
	// Development: ui/../bin relative to the binary's location
	exe, err := os.Executable()
	if err == nil {
		devPath := filepath.Clean(filepath.Join(filepath.Dir(exe), "..", "bin"))
		if info, err := os.Stat(devPath); err == nil && info.IsDir() {
			if entries, _ := os.ReadDir(devPath); len(entries) > 0 {
				return devPath
			}
		}
	}
	// Installed: ~/.raccoon/bin
	home, _ := os.UserHomeDir()
	installPath := filepath.Join(home, ".raccoon", "bin")
	if info, err := os.Stat(installPath); err == nil && info.IsDir() {
		return installPath
	}
	// Fallback
	return filepath.Join(home, ".raccoon", "bin")
}

func items() []item {
	return []item{
		{title: "upgrade", script: "upgrade.sh", description: "Update packages (brew, pip, npm, gem)", needsSudo: true},
		{title: "apps", script: "apps.sh", description: "Update GUI apps (App Store + casks)", needsSudo: true},
		{title: "audit", script: "audit.sh", description: "Security audit + fix", needsSudo: true},
		{title: "network", script: "network.sh", description: "Interfaces, Wi-Fi, DNS, routing"},
		{title: "fleet scan", script: "fleet.sh", args: []string{"scan"}, description: "Discover Macs on the LAN (Bonjour + ping)"},
		{title: "fleet audit", script: "fleet.sh", args: []string{"audit"}, description: "Security audit across Macs over SSH"},
		{title: "fleet status", script: "fleet.sh", args: []string{"status"}, description: "SSH reachability of configured hosts"},
		{title: "fleet list", script: "fleet.sh", args: []string{"list"}, description: "List configured fleet hosts"},
		{title: "fleet groups", script: "fleet.sh", args: []string{"group", "list"}, description: "List fleet host groups"},
		{title: "disk", script: "disk.sh", description: "Disk space, APFS, SMART status"},
		{title: "memory", script: "memory.sh", description: "Processes sorted by RAM usage"},
		{title: "ports", script: "ports.sh", description: "Open ports and listeners"},
		{title: "battery", script: "battery.sh", description: "Health, cycles, charging"},
		{title: "backup", script: "backup.sh", description: "Time Machine status"},
		{title: "ssh", script: "ssh.sh", description: "SSH key management"},
		{title: "git", script: "git.sh", description: "Repo scan, branches, stash"},
		{title: "docker", script: "docker.sh", description: "Images, containers, volumes"},
		{title: "xcode", script: "xcode.sh", description: "Simulators, derived data, SPM"},
		{title: "env", script: "env.sh", description: "PATH, symlinks, tool versions"},
		{title: "overlap", script: "overlap.sh", description: "Which manager is behind each PATH entry"},
		{title: "startup", script: "startup.sh", description: "Launch agents, login items"},
		{title: "trash", script: "trash.sh", description: "Trash size + contents"},
		{title: "fonts", script: "fonts.sh", description: "Dupes, corrupted, catalog"},
		{title: "history", script: "history.sh", description: "Shell history analysis"},
		{title: "certs", script: "certs.sh", description: "SSL certificate overview"},
	}
}

func (m *model) filtered() []item {
	if m.searchQuery == "" {
		return m.items
	}
	q := strings.ToLower(m.searchQuery)
	var f []item
	for _, it := range m.items {
		if strings.Contains(strings.ToLower(it.title), q) ||
			strings.Contains(strings.ToLower(it.description), q) {
			f = append(f, it)
		}
	}
	return f
}

func (m *model) clamp() {
	f := m.filtered()
	if m.selected >= len(f) {
		m.selected = 0
	}
	if m.selected < 0 {
		m.selected = 0
	}
}

// ─── Progress Bar rendering ────────────────────────────────

func renderProgressBar(curr, total, maxWidth int) string {
	if total <= 0 || maxWidth < 10 {
		return ""
	}
	pctVal := curr * 100 / total
	if pctVal > 100 {
		pctVal = 100
	}
	label := fmt.Sprintf(" %d/%d (%d%%)", curr, total, pctVal)

	barWidth := maxWidth - len(label) - 2
	if barWidth < 4 {
		barWidth = 4
	}
	pct := curr * barWidth / total
	if pct > barWidth {
		pct = barWidth
	}
	empty := barWidth - pct

	filled := styleProgressFill.Render(strings.Repeat("█", pct))
	emptys := styleProgressEmpty.Render(strings.Repeat("░", empty))

	return filled + emptys + label
}

// ─── Streaming commands ────────────────────────────────────

func tick() tea.Cmd {
	return tea.Tick(300*time.Millisecond, func(t time.Time) tea.Msg {
		return tickMsg{}
	})
}

// sudoCached reports whether a sudo timestamp is already valid, so an item that
// needs root can skip the prompt entirely.
func sudoCached() bool {
	return exec.Command("sudo", "-n", "true").Run() == nil
}

// primeSudo authenticates BEFORE the script starts. tea.ExecProcess releases
// the terminal first — cooked mode restored, TUI key reader stopped — so sudo
// (or the Touch ID dialog) gets the terminal to itself. Prompting from inside
// the running TUI instead is what made the password come back "Sorry, try
// again" on Macs without Touch ID: issue #23.
func primeSudo() tea.Cmd {
	return tea.ExecProcess(exec.Command("sudo", "-v"), func(err error) tea.Msg {
		return sudoPrimed{err: err}
	})
}

// primeSudoIfNeeded skips the whole dance when a timestamp is already valid.
// The check runs inside the command rather than in Update, because asking sudo
// anything can block — a Mac with a directory-service sudoers takes its time —
// and Update runs on the event loop, where blocking freezes the interface.
func primeSudoIfNeeded() tea.Cmd {
	return func() tea.Msg {
		if sudoCached() {
			return sudoPrimed{}
		}
		return primeSudo()()
	}
}

// startScript starts a bash script and returns the first line of output.
// It is a standalone function (not a model method) so scanner+cmd are
// captured by closure, not lost to value-copy semantics.
func startScript(binPath, script string, args []string) tea.Cmd {
	fullPath := filepath.Join(binPath, script)
	cmd := exec.Command("bash", append([]string{fullPath}, args...)...)

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return func() tea.Msg {
			return scriptDone{err: fmt.Errorf("stdout pipe: %w", err)}
		}
	}
	cmd.Stderr = cmd.Stdout
	cmd.Stdin = nil // ponytail: prevent child from receiving TTY in raw mode and corrupting TUI
	// The TUI owns the terminal — raw mode plus its own key reader — so a sudo
	// prompt raised by the child would have its password split between sudo and
	// the TUI input loop and rejected (issue #23). Scripts must never prompt;
	// root access is authenticated up front by primeSudo instead.
	cmd.Env = append(os.Environ(), "RCC_NO_PROMPT=1")

	if err := cmd.Start(); err != nil {
		return func() tea.Msg {
			return scriptDone{err: fmt.Errorf("start: %w", err)}
		}
	}

	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 64*1024), 512*1024)

	return func() tea.Msg {
		if scanner.Scan() {
			return scriptOutput{line: scanner.Text(), scanner: scanner, cmd: cmd}
		}
		err := cmd.Wait()
		// Scan() returning false can mean a read error (e.g. a line exceeding
		// the 512KB buffer), not just EOF — surface it so a truncated stream
		// isn't reported as success when the process happened to exit 0.
		if se := scanner.Err(); se != nil && err == nil {
			err = se
		}
		return scriptDone{err: err}
	}
}

// readLine reads the next line from an already-running script's scanner.
// Standalone function — scanner+cmd in closure, not on model.
func readLine(scanner *bufio.Scanner, cmd *exec.Cmd) tea.Cmd {
	return func() tea.Msg {
		if scanner.Scan() {
			return scriptOutput{line: scanner.Text(), scanner: scanner, cmd: cmd}
		}
		err := cmd.Wait()
		// Scan() returning false can mean a read error (e.g. a line exceeding
		// the 512KB buffer), not just EOF — surface it so a truncated stream
		// isn't reported as success when the process happened to exit 0.
		if se := scanner.Err(); se != nil && err == nil {
			err = se
		}
		return scriptDone{err: err}
	}
}

// ─── Bubbletea lifecycle ───────────────────────────────────

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tickMsg:
		if m.state == stateRunning {
			frames := raccoonFrames
			if sf, ok := scriptFrames[m.currentScript]; ok {
				frames = sf
			}
			m.spinnerFrame = (m.spinnerFrame + 1) % len(frames)
			return m, tick()
		}
		return m, nil

	case scriptOutput:
		// Store cmd from message for kill signal
		m.cmd = msg.cmd
		// Try to parse as progress marker
		if ok, curr, total, label := isProgressLine(msg.line); ok {
			m.progressCurr = curr
			m.progressTotal = total
			m.progressLabel = label
			return m, readLine(msg.scanner, msg.cmd)
		}
		// Regular output line — strip ANSI, add to buffer
		clean := stripANSI(msg.line)
		m.outputLines = append(m.outputLines, clean)
		return m, readLine(msg.scanner, msg.cmd)

	case sudoPrimed:
		// The user may have quit while the terminal was released.
		if m.state != stateRunning {
			return m, nil
		}
		if msg.err != nil {
			// Not fatal: ensure_sudo re-checks the cache and the scripts degrade
			// to "sudo unavailable" on their own.
			m.outputLines = append(m.outputLines, styleError.Render("  sudo not authenticated — steps needing root will be skipped"))
		}
		return m, tea.Batch(startScript(m.binPath, m.currentScript, m.pendingArgs), tick())

	case scriptDone:
		// Ignore a scriptDone that arrives after the user already killed the
		// script (state is back to stateMenu): the in-flight reader goroutine
		// still fires one final scriptDone, which would otherwise yank the user
		// into the output view of the script they just dismissed.
		if m.state != stateRunning {
			return m, nil
		}
		m.state = stateOutput
		m.outputLines = append(m.outputLines, "") // spacer
		if msg.err != nil {
			m.outputSuccess = false
			m.spinnerFrame = 4 // sad raccoon
			m.outputLines = append(m.outputLines, styleError.Render(fmt.Sprintf("  Exit code: %v", msg.err)))
		} else {
			m.outputSuccess = true
			m.spinnerFrame = 2 // happy raccoon
		}
		m.outputScroll = 0
		return m, nil

	case tea.KeyMsg:
		switch m.state {
		case stateMenu:
			return m.handleMenuKey(msg)
		case stateSearch:
			return m.handleSearchKey(msg)
		case stateRunning:
			if msg.String() == "q" || msg.String() == "ctrl+c" {
				if m.cmd != nil && m.cmd.Process != nil {
					m.cmd.Process.Kill()
				}
				m.state = stateMenu
				m.outputLines = nil
				m.progressCurr = 0
				m.progressTotal = 0
				m.progressLabel = ""
				return m, nil
			}
			return m, nil
		case stateOutput:
			return m.handleOutputKey(msg)
		}
	}

	return m, nil
}

func (m model) View() string {
	switch m.state {
	case stateRunning:
		return m.runningView()
	case stateOutput:
		return m.outputView()
	default:
		return m.menuView()
	}
}

// ─── Menu View ─────────────────────────────────────────────

// menuChromeLines is what menuView draws around the command list: a leading
// blank, four lines of raccoon, the blank under it, the blank above the footer,
// and the footer — eight rows — plus one held back, because the view ends in a
// newline and writing that on the last row of the window scrolls it. The search
// prompt adds one more.
const menuChromeLines = 9

// menuWindow is the slice of the list that fits on screen, positioned to keep
// the selection in view. Without it the menu drew all 29 commands into a 24-row
// terminal and the raccoon scrolled off the top — the running and output views
// have clamped to m.height all along, the menu was the one that did not.
// Height is 0 until the first WindowSizeMsg, and that means "no limit known".
func (m model) menuWindow(total int) (int, int) {
	if m.height <= 0 {
		return 0, total
	}
	chrome := menuChromeLines
	if m.searchQuery != "" {
		chrome++
	}
	visible := max(1, min(total, m.height-chrome))
	if visible >= total {
		return 0, total
	}
	start := max(0, min(m.selected-visible/2, total-visible))
	return start, start + visible
}

func (m model) menuView() string {
	var b strings.Builder

	b.WriteString("\n")
	b.WriteString(styleTitle.Render("    _") + "\n")
	b.WriteString(styleTitle.Render("   / \\_/\\_") + "  " + styleTitle.Render("Raccoon") + "\n")
	b.WriteString(styleTitle.Render("  ( o.o )") + "  " + styleDesc.Render("macOS companion toolkit") + "\n")
	b.WriteString(styleTitle.Render("   > ^ <") + "\n\n")

	f := m.filtered()
	if len(f) == 0 {
		b.WriteString(styleError.Render("  No matches found") + "\n\n")
	} else {
		start, end := m.menuWindow(len(f))
		for i := start; i < end; i++ {
			it := f[i]
			if i == m.selected {
				b.WriteString(styleSelected.Render(it.title) + "  " + styleDesc.Render(it.description) + "\n")
			} else {
				b.WriteString(styleDesc.Render(it.title) + "  " + styleMuted.Render(it.description) + "\n")
			}
		}
	}

	b.WriteString("\n")
	if m.searchQuery != "" {
		b.WriteString(styleSearch.Render(fmt.Sprintf("  [search: %s_]", m.searchQuery)))
		b.WriteString("\n" + styleFooter.Render("  ↑↓ Navigate · Enter Run · Esc Cancel"))
	} else {
		b.WriteString(styleFooter.Render("  ↑↓ j/k Navigate · Enter Run · / Search"))
	}
	b.WriteString("\n")

	return b.String()
}

// ─── Running View (live streaming) ─────────────────────────

// sepWidth is the width of the rules the running and output views draw. It is
// clamped at zero: a window narrower than the padding — or a model that has not
// received its first WindowSizeMsg yet, where width is 0 — otherwise asks
// strings.Repeat for a negative count, and that panics the whole TUI.
func (m model) sepWidth() int {
	return max(0, min(m.width-2, 60))
}

func (m model) runningView() string {
	var b strings.Builder
	sepLen := m.sepWidth()

	b.WriteString("  " + styleTitle.Render("» "+m.outputTitle) + "\n")

	frames := raccoonFrames
	if sf, ok := scriptFrames[m.currentScript]; ok {
		frames = sf
	}
	frameIdx := m.spinnerFrame % len(frames)
	artLines := strings.Split(frames[frameIdx], "\n")

	// The audit's face follows the findings, not the frame number.
	if m.currentScript == "audit.sh" {
		if eyes := auditMood(m.outputLines); eyes != "" {
			for i, l := range artLines {
				artLines[i] = eyeRegexp.ReplaceAllString(l, "( "+eyes+" )")
			}
		}
	}

	// fleet lines the remote machines up as they answer.
	if m.currentScript == "fleet.sh" {
		if hosts := readFleetHosts(m.outputLines); len(hosts) > 0 {
			eyes, row := fleetVision(m.spinnerFrame, hosts)
			// Once he is back, his own face carries the verdict on the fleet.
			if eyes == "o.o" {
				eyes = fleetFace(hosts)
			}
			for i, l := range artLines {
				l = eyeRegexp.ReplaceAllString(l, "( "+eyes+" )")
				if row != "" && strings.Contains(l, "(") && strings.Contains(l, ")") {
					l += "  " + row
				}
				artLines[i] = l
			}
		}
	}

	// overlap draws the fork for one clashing command at a time.
	if m.currentScript == "overlap.sh" {
		if clashes := readOverlaps(m.outputLines); len(clashes) > 0 {
			rows, face := overlapFork(m.spinnerFrame, clashes), overlapFace(clashes)
			for i, l := range artLines {
				l = eyeRegexp.ReplaceAllString(l, "( "+face+" )")
				if rows[i] != "" {
					l = fmt.Sprintf("%-11s %s", l, rows[i])
				}
				artLines[i] = strings.TrimRight(l, " ")
			}
		}
	}

	// wifi fills the width with waves and sails the network names through them.
	if m.currentScript == "wifi.sh" {
		networks, active := readWifi(m.outputLines)
		if len(networks) > 0 {
			rows := wifiField(m.spinnerFrame, m.width-18, networks, active)
			face := "-.-"
			if active != "" {
				face = "o.o"
			}
			for i, l := range artLines {
				l = eyeRegexp.ReplaceAllString(l, "( "+face+" )")
				artLines[i] = strings.TrimRight(fmt.Sprintf("%-11s %s", l, rows[i]), " ")
			}
		}
	}

	// certs: the wall, with a gap where each expired certificate used to stand.
	if m.currentScript == "certs.sh" {
		total, valid, expiring, expired := certCounts(m.outputLines)
		if wall := certWall(total, valid, expiring, expired); wall != "" {
			face := certFace(total, expired, expiring)
			for i, l := range artLines {
				l = eyeRegexp.ReplaceAllString(l, "( "+face+" )")
				if strings.Contains(l, "(") && strings.Contains(l, ")") {
					l += "  " + wall
				}
				artLines[i] = l
			}
		}
	}

	// history unrolls the scroll, a command per stretch.
	if m.currentScript == "history.sh" {
		cmds := recentCommands(m.outputLines)
		if slot := historyScroll(m.spinnerFrame, cmds, historyTotal(m.outputLines)); slot != "" {
			for i, l := range artLines {
				if strings.Contains(l, "(") && strings.Contains(l, ")") {
					artLines[i] = l + "  " + slot
				}
			}
		}
	}

	// fonts: the open book, and how tired the duplicates have made him.
	if m.currentScript == "fonts.sh" {
		dups, corrupted := fontIssues(m.outputLines)
		if len(m.outputLines) > 0 {
			rows := fontsBook(fontsPage(m.spinnerFrame, dups))
			face := fontsFace(dups, corrupted)
			for i, l := range artLines {
				l = eyeRegexp.ReplaceAllString(l, "( "+face+" )")
				artLines[i] = strings.TrimRight(fmt.Sprintf("%-11s %s", l, rows[i]), " ")
			}
		}
	}

	// trash: the bin beside him, and whatever he has just pulled out of it.
	if m.currentScript == "trash.sh" {
		if gb := trashGB(m.outputLines); gb >= 0 {
			rows := trashBin(m.spinnerFrame, gb, trashItems(m.outputLines))
			face := trashFace(gb)
			for i, l := range artLines {
				l = eyeRegexp.ReplaceAllString(l, "( "+face+" )")
				artLines[i] = strings.TrimRight(fmt.Sprintf("%-11s %s", l, rows[i]), " ")
			}
		}
	}

	// startup gathers its procession, one follower per beat.
	if m.currentScript == "startup.sh" {
		if items := countStartupItems(m.outputLines); items > 0 {
			trail, face := startupTrail(m.spinnerFrame, items), startupFace(items)
			for i, l := range artLines {
				l = eyeRegexp.ReplaceAllString(l, "( "+face+" )")
				if trail != "" && strings.Contains(l, "(") && strings.Contains(l, ")") {
					l += "  " + trail
				}
				artLines[i] = l
			}
		}
	}

	// env walks the PATH, one entry per beat.
	if m.currentScript == "env.sh" {
		if entries := readPathEntries(m.outputLines); len(entries) > 0 {
			rows, face := envTrail(m.spinnerFrame, entries), envFace(entries)
			for i, l := range artLines {
				l = eyeRegexp.ReplaceAllString(l, "( "+face+" )")
				if rows[i] != "" {
					l = fmt.Sprintf("%-11s %s", l, rows[i])
				}
				artLines[i] = strings.TrimRight(l, " ")
			}
		}
	}

	// xcode piles the build leftovers on the ground beside him.
	if m.currentScript == "xcode.sh" {
		if gb := derivedDataGB(m.outputLines); gb >= 0 {
			rows, face := xcodeHeap(gb), xcodeFace(gb)
			for i, l := range artLines {
				l = eyeRegexp.ReplaceAllString(l, "( "+face+" )")
				if rows[i] != "" {
					l = fmt.Sprintf("%-11s %s", l, rows[i])
				}
				artLines[i] = strings.TrimRight(l, " ")
			}
		}
	}

	// docker piles the containers up beside him as he counts them.
	if m.currentScript == "docker.sh" {
		missing := dockerMissing(m.outputLines)
		running, stopped := dockerCounts(m.outputLines)
		if missing || running+stopped > 0 {
			rows := dockerStack(m.spinnerFrame, running, stopped)
			face := dockerFace(missing, running, stopped)
			for i, l := range artLines {
				l = eyeRegexp.ReplaceAllString(l, "( "+face+" )")
				if rows[i] != "" {
					l = fmt.Sprintf("%-11s %s", l, rows[i])
				}
				artLines[i] = strings.TrimRight(l, " ")
			}
		}
	}

	// git shows one repository per beat: pending work sits still, a clean repo
	// sends its signal up.
	if m.currentScript == "git.sh" {
		if repos := readRepos(m.outputLines); len(repos) > 0 {
			face := gitFace(repos)
			i := ((m.spinnerFrame / 4 % (len(repos) + 1)) + len(repos) + 1) % (len(repos) + 1)
			var rows []string
			name := ""
			if i < len(repos) {
				r := repos[i]
				name = r.name
				if sym := gitSymbols(r); sym != "" {
					rows = []string{"", "", sym, ""}
				} else {
					rows = gitRise(m.spinnerFrame)
				}
			}
			for n, l := range artLines {
				l = eyeRegexp.ReplaceAllString(l, "( "+face+" )")
				if n < len(rows) && rows[n] != "" {
					l = fmt.Sprintf("%-11s %s", l, rows[n])
					if n == 2 && name != "" {
						l += "   " + name
					}
				}
				artLines[n] = strings.TrimRight(l, " ")
			}
		}
	}

	// ssh tries one key per beat, and wears the worst of them throughout.
	if m.currentScript == "ssh.sh" {
		if keys := readSSHKeys(m.outputLines); len(keys) > 0 {
			slot, face := sshSlot(m.spinnerFrame, keys), sshFace(keys)
			for i, l := range artLines {
				l = eyeRegexp.ReplaceAllString(l, "( "+face+" )")
				if slot != "" && strings.Contains(l, "(") && strings.Contains(l, ")") {
					l += " " + slot
				}
				artLines[i] = l
			}
		}
	}

	// backup shows the copies standing behind him — or the empty space where
	// they should be.
	if m.currentScript == "backup.sh" {
		if st := readBackupState(m.outputLines); st.configured || st.hasBackup || len(m.outputLines) > 0 {
			artLines = backupRow(backupEyes(m.spinnerFrame, st))
		}
	}

	// battery wears the pack's health, and shows the charge flowing in only when
	// it actually is.
	if m.currentScript == "battery.sh" {
		health := batteryPercent(batteryRow(m.outputLines, "Max Capacity"))
		cycles := batteryPercent(batteryRow(m.outputLines, "Cycle Count"))
		if health > 0 {
			charging := batteryRow(m.outputLines, "Charging") == "Yes"
			slot := fmt.Sprintf("%s %d%%%s", batteryGauge(health), health,
				batteryBolt(m.spinnerFrame, charging))
			face := batteryFace(health, cycles)
			for i, l := range artLines {
				l = eyeRegexp.ReplaceAllString(l, "( "+face+" )")
				if strings.Contains(l, "(") && strings.Contains(l, ")") {
					l += " " + slot
				}
				artLines[i] = l
			}
		}
	}

	// ports tries one door per beat, and reacts to how many stand open.
	if m.currentScript == "ports.sh" {
		if ports := listenPorts(m.outputLines); len(ports) > 0 {
			slot, face := portsSlot(m.spinnerFrame, ports), portsFace(ports)
			for i, l := range artLines {
				l = eyeRegexp.ReplaceAllString(l, "( "+face+" )")
				if slot != "" && strings.Contains(l, "(") && strings.Contains(l, ")") {
					l += " " + slot
				}
				artLines[i] = l
			}
		}
	}

	// memory wears the machine's condition, and holds frames still when tired.
	if m.currentScript == "memory.sh" {
		if p := memPressure(m.outputLines); p > 0 {
			st := memStateFor(p)
			if st.repeat > 0 {
				// Hold the same frame for st.repeat beats out of four.
				frameIdx = (frameIdx / (st.repeat + 1)) * (st.repeat + 1) % len(frames)
				artLines = strings.Split(frames[frameIdx], "\n")
			}
			for i, l := range artLines {
				if st.eyes != "" {
					l = eyeRegexp.ReplaceAllString(l, "( "+st.eyes+" )")
				}
				l = strings.Replace(l, "> ^ <", "> "+st.muzzle+" <", 1)
				if st.load != "" && strings.Contains(l, ")") && strings.Contains(l, "(") {
					l += " " + st.load
				}
				artLines[i] = l
			}
		}
	}

	// disk hangs a gauge beside each line, and reacts to the fullest volume.
	if m.currentScript == "disk.sh" {
		vols := diskVolumes(m.outputLines)
		rows := diskRows(m.spinnerFrame, vols)
		for i := range artLines {
			if i < len(rows) && rows[i] != "" {
				artLines[i] = fmt.Sprintf("%-11s %s", artLines[i], rows[i])
			}
		}
		if len(vols) > 0 {
			for i, l := range artLines {
				artLines[i] = eyeRegexp.ReplaceAllString(l, "( "+diskFace(vols)+" )")
			}
		}
	}

	// apps grows its own sky: the falling name is only known at run time.
	if m.currentScript == "apps.sh" {
		artLines = append(appsSky(m.spinnerFrame, appName(m.progressLabel)), artLines...)
	}

	// The upgrade box follows the phase the script declared, not the frame number.
	if m.currentScript == "upgrade.sh" || m.currentScript == "apps.sh" {
		box, eyes := phaseBox(m.progressLabel)
		for i, l := range artLines {
			l = boxRegexp.ReplaceAllString(l, box)
			if eyes != "" {
				l = eyeRegexp.ReplaceAllString(l, "( "+eyes+" )")
			}
			artLines[i] = l
		}
	}
	for _, l := range artLines {
		b.WriteString("  " + styleTitle.Render(l) + "\n")
	}

	// Separator
	b.WriteString(styleMuted.Render("  " + strings.Repeat("─", sepLen)))
	b.WriteString("\n")

	// Progress bar — compact, always on screen
	if m.progressTotal > 0 {
		bar := renderProgressBar(m.progressCurr, m.progressTotal, sepLen)
		b.WriteString("  " + bar)
		if m.progressLabel != "" {
			clean := stripANSI(m.progressLabel)
			if len(clean) > sepLen-20 {
				clean = clean[:max(0, sepLen-20)]
			}
			b.WriteString("  " + styleProgressLabel.Render(clean))
		}
		b.WriteString("\n")

		b.WriteString("\n")

		// Separator between bar and output
		label := "Output"
		if m.outputTitle != "" {
			label = m.outputTitle
		}
		sepLine := styleMuted.Render(strings.Repeat("─", max(0, sepLen-8-len(label))))
		b.WriteString(styleMuted.Render("  " + sepLine + " " + label + " " + strings.Repeat("─", 4)))
		b.WriteString("\n")
	}

	// Live streaming output (show last N lines)
	// 7 lines of chrome sit around the art (title, two separators, progress bar
	// and its gap, footer). Deriving from the art itself means an animation of a
	// different height cannot silently push the output off screen.
	maxLines := m.height - 7 - len(artLines)
	if maxLines < 2 {
		maxLines = 2
	}

	lines := m.outputLines
	start := 0
	if len(lines) > maxLines {
		start = len(lines) - maxLines
	}
	for _, l := range lines[start:] {
		clean := stripANSI(l)
		if len(clean) > m.width-4 {
			clean = clean[:max(0, m.width-4)]
		}
		if strings.TrimSpace(clean) == "" {
			continue
		}
		b.WriteString(styleMuted.Render("  │ "+clean) + "\n")
	}

	b.WriteString("\n")
	b.WriteString(styleFooter.Render("  Running · press q to quit"))
	b.WriteString("\n")

	return b.String()
}

// ─── Output View (after completion) ────────────────────────

func (m model) outputView() string {
	var b strings.Builder

	// Title row with raccoon face + status badge
	b.WriteString("\n")
	var raccoonFace string
	if m.outputSuccess {
		raccoonFace = "( ^.^ )"
	} else {
		raccoonFace = "( >.< )"
	}
	status := styleStatusSuccess.Render("✓ Completed")
	if !m.outputSuccess {
		status = styleStatusError.Render("✗ Failed")
	}
	b.WriteString(fmt.Sprintf("  %s  %s  %s",
		styleTitle.Render(raccoonFace),
		styleTitle.Render(m.outputTitle),
		status))
	b.WriteString("\n")

	sepLen := m.sepWidth()
	b.WriteString(styleMuted.Render("  " + strings.Repeat("─", sepLen)))
	b.WriteString("\n\n")

	// Visible lines based on scroll
	maxLines := m.height - 6
	if maxLines < 3 {
		maxLines = 3
	}
	end := m.outputScroll + maxLines
	if end > len(m.outputLines) {
		end = len(m.outputLines)
	}
	for _, l := range m.outputLines[m.outputScroll:end] {
		clean := stripANSI(l)
		if len(clean) > m.width-4 {
			clean = clean[:max(0, m.width-4)]
		}
		b.WriteString(styleOutput.Render("  "+clean) + "\n")
	}

	// Scroll indicator
	if len(m.outputLines) > maxLines {
		scrollInfo := fmt.Sprintf("  ↑↓ %d/%d", m.outputScroll+1, len(m.outputLines))
		// Only show percentage if there's meaningful content
		b.WriteString(styleFooter.Render(scrollInfo) + "\n")
	}

	b.WriteString("\n")
	b.WriteString(styleFooter.Render("  ↑↓ Scroll · Enter Return · q Quit"))
	b.WriteString("\n")

	return b.String()
}

// ─── Key handlers ──────────────────────────────────────────

// launch prepares the running view for it and returns the command that starts
// it. Items that touch system paths authenticate first, outside the TUI.
func (m *model) launch(it item) tea.Cmd {
	m.state = stateRunning
	m.outputLines = nil
	m.outputTitle = it.title
	m.currentScript = it.script
	m.pendingArgs = it.args
	m.progressCurr = 0
	m.progressTotal = 0
	m.progressLabel = ""
	m.spinnerFrame = 0
	if it.needsSudo {
		// No tick(): the terminal may be released while sudo runs, so there is
		// nothing to animate until sudoPrimed comes back.
		return primeSudoIfNeeded()
	}
	return tea.Batch(startScript(m.binPath, it.script, it.args), tick())
}

func (m *model) handleMenuKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	f := m.filtered()
	switch msg.String() {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "/":
		m.state = stateSearch
		m.searchQuery = ""
		return m, nil
	case "up", "k":
		if m.selected > 0 {
			m.selected--
		}
	case "down", "j":
		if m.selected < len(f)-1 {
			m.selected++
		}
	case "enter", " ":
		if m.selected < len(f) && f[m.selected].script != "" {
			return m, m.launch(f[m.selected])
		}
	case "g":
		m.selected = 0
	case "G":
		m.selected = len(f) - 1
	}
	return m, nil
}

func (m *model) handleSearchKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.Type {
	case tea.KeyEsc:
		m.state = stateMenu
		m.searchQuery = ""
		m.selected = 0
	case tea.KeyBackspace:
		if len(m.searchQuery) > 0 {
			m.searchQuery = m.searchQuery[:len(m.searchQuery)-1]
			m.clamp()
		} else {
			m.state = stateMenu
			m.selected = 0
		}
	case tea.KeyEnter:
		f := m.filtered()
		if m.selected < len(f) && f[m.selected].script != "" {
			return m, m.launch(f[m.selected])
		}
	case tea.KeyUp:
		if m.selected > 0 {
			m.selected--
		}
	case tea.KeyDown:
		f := m.filtered()
		if m.selected < len(f)-1 {
			m.selected++
		}
	case tea.KeyRunes:
		m.searchQuery += string(msg.Runes)
		m.selected = 0
	}
	return m, nil
}

func (m *model) handleOutputKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "q", "ctrl+c", "esc":
		return m, tea.Quit
	case "up", "k":
		if m.outputScroll > 0 {
			m.outputScroll--
		}
	case "down", "j":
		if m.outputScroll < len(m.outputLines)-1 {
			m.outputScroll++
		}
	case "enter", " ":
		m.state = stateMenu
		m.outputLines = nil
		m.progressCurr = 0
		m.progressTotal = 0
		m.progressLabel = ""
		return m, nil
	}
	return m, nil
}

// ─── Main ──────────────────────────────────────────────────

func main() {
	binPath := resolveBinPath()

	// No manual term.MakeRaw here: tea.NewProgram already puts the terminal in
	// raw mode, and tea.ExecProcess restores it to whatever state it found at
	// startup. Raw-mode-before-Run made that "restore" hand a raw terminal to
	// sudo, which is how the password prompt broke in the first place (#23).
	m := model{
		items:   items(),
		binPath: binPath,
	}

	p := tea.NewProgram(m, tea.WithAltScreen())
	finalModel, err := p.Run()
	// Don't orphan a running child: on SIGTERM (or any exit while a script is
	// mid-run, e.g. upgrade.sh) the program returns here with the child still
	// alive — kill it before we exit.
	// The key handlers return *model, so the final model is a pointer after any
	// keypress and the value-only assertion this used to do never matched — the
	// child outlived us, still holding a primed sudo. Accept both forms.
	var fm *model
	switch v := finalModel.(type) {
	case model:
		fm = &v
	case *model:
		fm = v
	}
	if fm != nil && fm.cmd != nil && fm.cmd.Process != nil {
		_ = fm.cmd.Process.Kill()
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
