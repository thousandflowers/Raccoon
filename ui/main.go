package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"golang.org/x/term"
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

// ─── Raccoon animation frames ──────────────────────────────
// Each frame is exactly 4 lines. Title is rendered separately
// above the art, so all 4 lines are pure ASCII scene.

type raccoonAnimation []string

// Default fallback (5 basic frames)
var raccoonFrames = raccoonAnimation{
	`     _
   / \_/\_
  ( o.o )
   > ^ <`,
	`     _
   / \_/\_
  ( -.- )
   > ^ <`,
	`     _
   / \_/\_
  ( ^.^ )
   > ^ <`,
	`     _
   / \_/\_
  ( *.* )
   > ^ <`,
	`     _
   / \_/\_
  ( >.< )
   > ^ <`,
}

// Each script gets its own animation with a completely unique
// visual style — different body shapes, objects, and action
// sequences. All frames are exactly 4 lines.
var scriptFrames = map[string]raccoonAnimation{
	// upgrade — sysadmin raccoon, package install sequence
	"upgrade.sh": {
		`    _
  / \_/\_
 ( o.o ) [ ]
  > ^ <`,
		`  __\_/\_
 ( -.- )[ ]
  > ^ <`,
		` /=\_/\_
 ( *.* )[=]
  > ^ <`,
		`  __\_/\_
 ( >.< ) [█]
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
		`  __\_/\_
 ( o.o )[ ]
  > ^ <`,
		` /=\_/\_
 ( *.* )[=]
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
	},

	// apps — shopper raccoon, app boxes install
	"apps.sh": {
		`    _
  / \_/\_
 ( o.o )[A]
  > ^ <`,
		`  __\_/\_
 ( -.- )[A]
  > ^ <`,
		` /=\_/\_
 ( *.* )[▒]
  > ^ <`,
		`  __\_/\_
 ( >.< )[█]
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
		`  __\_/\_
 ( o.o )[A]
  > ^ <`,
		` /=\_/\_
 ( *.* )[▒]
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
	},

	// audit — detective raccoon, magnifying glass scans
	"audit.sh": {
		`    _
  / \_/\_
 ( o.o ) O
  > ^ <`,
		`  __\_/\_
 ( -.- )O─
  > ^ <`,
		` /=\_/\_
 ( *.* )O──
  > ^ <`,
		`  __\_/\_
 ( >.< ) O!
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ◄
  > ^ <`,
		`  __\_/\_
 ( ^.^ )✓
  > ^ <`,
		` /=\_/\_
 ( o.o )O
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
	},

	// network — antenna raccoon, signal bars grow
	"network.sh": {
		`    _
  / \_/\_
 ( o.o )▽
  > ^ <`,
		`  __\_/\_
 ( -.- )▽▽
  > ^ <`,
		` /=\_/\_
 ( *.* )▽▽▽
  > ^ <`,
		`  __\_/\_
 ( >.< )▽▽▽▽
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ )▽▽▽▽▽
  > ^ <`,
		`  __\_/\_
 ( o.o )▽▽
  > ^ <`,
		` /=\_/\_
 ( -.- )###
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
	},

	// disk — disk doctor, drive cleanup
	"disk.sh": {
		`    _
  / \_/\_
 ( o.o ) [=]
  > ^ <`,
		`  __\_/\_
 ( -.- )[=]
  > ^ <`,
		` /=\_/\_
 ( *.* )[=]
  > ^ <`,
		`  __\_/\_
 ( >.< )═>!
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
		`  __\_/\_
 ( o.o )[=]
  > ^ <`,
		` /=\_/\_
 ( -.- )[=]
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
	},

	// memory — RAM technician, memory chips multiply
	"memory.sh": {
		`    _
  / \_/\_
 ( o.o )##
  > ^ <`,
		`  __\_/\_
 ( -.- )###
  > ^ <`,
		` /=\_/\_
 ( *.* )####
  > ^ <`,
		`  __\_/\_
 ( >.< )!!!!
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ )###
  > ^ <`,
		`  __\_/\_
 ( o.o )##
  > ^ <`,
		` /=\_/\_
 ( -.- )###
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
	},

	// ports — cable wrangler, plugging jacks
	"ports.sh": {
		`    _
  / \_/\_
 ( o.o )=||=
  > ^ <`,
		`  __\_/\_
 ( -.- )┤├
  > ^ <`,
		` /=\_/\_
 ( *.* )─┤├
  > ^ <`,
		`  __\_/\_
 ( >.< )──┤┤
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ··
  > ^ <`,
		`  __\_/\_
 ( o.o )=||=
  > ^ <`,
		` /=\_/\_
 ( -.- )─┤├
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
	},

	// battery — charger raccoon, power fills up
	"battery.sh": {
		`    _
  / \_/\_
 ( o.o )
  > ^ <`,
		`  __\_/\_
 ( -.- )══
  > ^ <`,
		` /=\_/\_
 ( *.* )═══
  > ^ <`,
		`  __\_/\_
 ( >.< )════
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ )════
  > ^ <`,
		`  __\_/\_
 ( ^.^ )═════
  > ^ <`,
		` /=\_/\_
 ( ^.^ )═════✓
  > ^ <`,
		`    _
  / \_/\_
 ( -.- )═════
  > ^ <`,
	},

	// backup — time traveler, capsule spins
	"backup.sh": {
		`    _
  / \_/\_
 ( o.o )(())
  > ^ <`,
		`  __\_/\_
 ( -.- )⊂()
  > ^ <`,
		` /=\_/\_
 ( *.* )⊂( )⊃
  > ^ <`,
		`  __\_/\_
 ( >.< )◐
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ )◐
  > ^ <`,
		`  __\_/\_
 ( ^.^ )◑
  > ^ <`,
		` /=\_/\_
 ( o.o )(())
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
	},

	// ssh — locksmith raccoon, key turns
	"ssh.sh": {
		`    _
  / \_/\_
 ( o.o )>-
  > ^ <`,
		`  __\_/\_
 ( -.- )>σ
  > ^ <`,
		` /=\_/\_
 ( *.* )>≈
  > ^ <`,
		`  __\_/\_
 ( >.< )>≈≈
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ )↻
  > ^ <`,
		`  __\_/\_
 ( ^.^ )✓
  > ^ <`,
		` /=\_/\_
 ( o.o )>-
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
	},

	// git — branch weaver, splits and merges
	"git.sh": {
		`    _
  / \_/\_
 ( o.o )><
  > ^ <`,
		`  __\_/\_
 ( -.- )><<
  > ^ <`,
		` /=\_/\_
 ( *.* )<><
  > ^ <`,
		`  __\_/\_
 ( >.< )<><>
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ )══
  > ^ <`,
		`  __\_/\_
 ( ^.^ )═
  > ^ <`,
		` /=\_/\_
 ( o.o )><
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
	},

	// docker — container stacker, boxes pile up
	"docker.sh": {
		`    _
  / \_/\_
 ( o.o )┌#┐
  > ^ <`,
		`  __\_/\_
 ( -.- )│#│
  > ^ <`,
		` /=\_/\_
 ( *.* )┌##┐
  > ^ <`,
		`   _
 / \_/\_
( >.< )│##│
 > ^ <`,
		`    _
  / \_/\_
 ( ^.^ )┌───┐
  > ^ <`,
		`  __\_/\_
 ( ^.^ )│   │
  > ^ <`,
		` /=\_/\_
 ( o.o )└───┘
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
	},

	// xcode — builder raccoon, compile arrow
	"xcode.sh": {
		`    _
  / \_/\_
 ( o.o ) =>
  > ^ <`,
		`  __\_/\_
 ( -.- )=>
  > ^ <`,
		` /=\_/\_
 ( *.* )=>>>
  > ^ <`,
		`  __\_/\_
 ( >.< )==>>
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
		`  __\_/\_
 ( o.o )=>
  > ^ <`,
		` /=\_/\_
 ( *.* )=>>>
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
	},

	// env — pathfinder, shell maze
	"env.sh": {
		`    _
  / \_/\_
 ( o.o )$%
  > ^ <`,
		`  __\_/\_
 ( -.- )$%
  > ^ <`,
		` /=\_/\_
 ( *.* )$%$
  > ^ <`,
		`  __\_/\_
 ( >.< )$%$%!
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ )$%
  > ^ <`,
		`  __\_/\_
 ( ^.^ )$%
  > ^ <`,
		` /=\_/\_
 ( o.o )$%
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
	},

	// startup — wake-up sequence, curled to standing
	"startup.sh": {
		`  ( -.- )z
   > ^ <`,
		`    _
  / \_/\_
 ( -.- )z
  > ^ <`,
		`  __\_/\_
 ( o.o )>>
  > ^ <`,
		` /=\_/\_
 ( o.o )>>
  > ^ <`,
		`  __\_/\_
 ( *.* )=>>>
  > ^ <`,
		` /=\_/\_
 ( ^.^ )>>>
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ¬
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
	},

	// trash — trash panda, digs for treasure
	"trash.sh": {
		`    _
  / \_/\_
 ( o.o )
  > ^ <`,
		`  __\_/\_
 ( -.- )┌┐
  > ^ < └┘`,
		` /=\_/\_
 ( o.o )┌┐
  > ^ < └┘`,
		`  __
 / >.< \~~
  > ^ <`,
		`   _
  />\_/\<
 (>.<)~~
 > ^ <`,
		`    _
  / \_/\_
 ( ^.^ )♪
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ )♪♪
  > ^ <`,
		`    _
  / \_/\_
 ( -.- )z
  > ^ <`,
	},

	// fonts — typographer, letter compare
	"fonts.sh": {
		`    _
  / \_/\_
 ( o.o )A
  > ^ <`,
		`  __\_/\_
 ( -.- )Aa
  > ^ <`,
		` /=\_/\_
 ( *.* )Aa
  > ^ <`,
		`  __\_/\_
 ( >.< )Aa!
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ )Aa
  > ^ <`,
		`  __\_/\_
 ( ^.^ )Bb
  > ^ <`,
		` /=\_/\_
 ( o.o )Ab
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
	},

	// history — archivist, scrolls pile
	"history.sh": {
		`    _
  / \_/\_
 ( o.o )@@
  > ^ <`,
		`  __\_/\_
 ( -.- )@@
  > ^ <`,
		` /=\_/\_
 ( *.* )@@
  > ^ <`,
		`  __\_/\_
 ( >.< )@@@@
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ )@@
  > ^ <`,
		`  __\_/\_
 ( ^.^ )@@
  > ^ <`,
		` /=\_/\_
 ( o.o )@@
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
	},

	// certs — shield bearer, certificate verify
	"certs.sh": {
		`    _
  / \_/\_
 ( o.o )<
  > ^ <`,
		`  __\_/\_
 ( -.- )<>
  > ^ <`,
		` /=\_/\_
 ( *.* )<~>
  > ^ <`,
		`  __\_/\_
 ( >.< )<~>!
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ )◇
  > ^ <`,
		`  __\_/\_
 ( ^.^ )◇
  > ^ <`,
		` /=\_/\_
 ( o.o )<>
  > ^ <`,
		`    _
  / \_/\_
 ( ^.^ ) ✓
  > ^ <`,
	},
}

// ─── Progress marker parsing ───────────────────────────────

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
		{title: "upgrade", script: "upgrade.sh", description: "Update packages (brew, pip, npm, gem)"},
		{title: "apps", script: "apps.sh", description: "Update GUI apps (App Store + casks)"},
		{title: "audit", script: "audit.sh", description: "Security audit + fix"},
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

func (m model) menuView() string {
	var b strings.Builder

	b.WriteString("\n")
	b.WriteString(styleTitle.Render("     _") + "\n")
	b.WriteString(styleTitle.Render("   / \\_/\\_") + "  " + styleTitle.Render("Raccoon") + "\n")
	b.WriteString(styleTitle.Render("  ( o.o )") + "  " + styleDesc.Render("macOS companion toolkit") + "\n")
	b.WriteString(styleTitle.Render("   > ^ <") + "\n\n")

	f := m.filtered()
	if len(f) == 0 {
		b.WriteString(styleError.Render("  No matches found") + "\n\n")
	} else {
		for i, it := range f {
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

func (m model) runningView() string {
	var b strings.Builder
	sepLen := min(m.width-2, 60)

	b.WriteString("  " + styleTitle.Render("» "+m.outputTitle) + "\n")

	frames := raccoonFrames
	if sf, ok := scriptFrames[m.currentScript]; ok {
		frames = sf
	}
	frameIdx := m.spinnerFrame % len(frames)
	artLines := strings.Split(frames[frameIdx], "\n")
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
		sepLine := styleMuted.Render(strings.Repeat("─", sepLen-8-len(label)))
		b.WriteString(styleMuted.Render("  " + sepLine + " " + label + " " + strings.Repeat("─", 4)))
		b.WriteString("\n")
	}

	// Live streaming output (show last N lines)
	maxLines := m.height - 11
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

	sepLen := min(m.width-2, 60)
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
			m.state = stateRunning
			m.outputLines = nil
			m.outputTitle = f[m.selected].title
			m.currentScript = f[m.selected].script
			m.progressCurr = 0
			m.progressTotal = 0
			m.progressLabel = ""
			m.spinnerFrame = 0
			return m, tea.Batch(startScript(m.binPath, f[m.selected].script, f[m.selected].args), tick())
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
			m.state = stateRunning
			m.outputLines = nil
			m.outputTitle = f[m.selected].title
			m.currentScript = f[m.selected].script
			m.progressCurr = 0
			m.progressTotal = 0
			m.progressLabel = ""
			m.spinnerFrame = 0
			return m, tea.Batch(startScript(m.binPath, f[m.selected].script, f[m.selected].args), tick())
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

	oldState, err := term.MakeRaw(int(os.Stdin.Fd()))
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error setting raw terminal: %v\n", err)
		os.Exit(1)
	}
	defer term.Restore(int(os.Stdin.Fd()), oldState)

	m := model{
		items:   items(),
		binPath: binPath,
	}

	p := tea.NewProgram(m, tea.WithAltScreen())
	finalModel, err := p.Run()
	// Don't orphan a running child: on SIGTERM (or any exit while a script is
	// mid-run, e.g. upgrade.sh) the program returns here with the child still
	// alive — kill it before we exit.
	if fm, ok := finalModel.(model); ok && fm.cmd != nil && fm.cmd.Process != nil {
		_ = fm.cmd.Process.Kill()
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
