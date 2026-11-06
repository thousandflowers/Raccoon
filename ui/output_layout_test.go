package main

import (
	"fmt"
	"strings"
	"testing"
	"unicode/utf8"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/mattn/go-runewidth"
)

// numberedLines is output in which every line can be told apart on screen.
func numberedLines(n int) []string {
	lines := make([]string, n)
	for i := range lines {
		lines[i] = fmt.Sprintf("line-%04d", i+1)
	}
	return lines
}

// assertFits uses the rule Bubble Tea itself applies: it splits the view on
// "\n", so a trailing newline is a row, and drops any excess from the TOP.
func assertFits(t *testing.T, label, view string, height int) {
	t.Helper()
	if rows := len(strings.Split(view, "\n")); rows > height {
		t.Errorf("%s: drew %d rows into %d, Bubble Tea drops the top %d",
			label, rows, height, rows-height)
	}
}

func TestOutputViewKeepsStatusAndFooterOnScreen(t *testing.T) {
	for height := 1; height <= 90; height++ {
		for _, count := range []int{0, 3, 20, 40, 85, 500} {
			for _, success := range []bool{true, false} {
				m := model{
					state: stateOutput, width: 80, height: height,
					currentScript: "audit.sh", outputTitle: "Security Audit",
					outputLines: numberedLines(count), outputSuccess: success,
				}
				label := fmt.Sprintf("height %d, %d lines, success %v", height, count, success)
				view := m.View()

				assertFits(t, label, view, height)
				want := "✗ Failed"
				if success {
					want = "✓ Completed"
				}
				if !strings.Contains(view, want) {
					t.Errorf("%s: %q is missing", label, want)
				}
				if height >= 3 && !strings.Contains(view, "Quit") {
					t.Errorf("%s: the footer is missing", label)
				}
			}
		}
	}
}

func TestOutputScrollStopsWithTheLastLineOnAFullScreen(t *testing.T) {
	for _, height := range []int{5, 12, 13, 24, 30, 50, 90} {
		for _, count := range []int{1, 3, 20, 40, 85, 500} {
			m := model{
				state: stateOutput, width: 80, height: height,
				outputTitle: "Security Audit", outputLines: numberedLines(count),
			}
			for i := 0; i < count+5; i++ {
				m.handleOutputKey(tea.KeyMsg{Type: tea.KeyDown})
			}
			view := m.outputView()
			label := fmt.Sprintf("height %d, %d lines", height, count)

			if !strings.Contains(view, m.outputLines[count-1]) {
				t.Errorf("%s: the last line never comes on screen", label)
			}
			// Scrolling must stop at a full screen, not run on until one line is left.
			visible := min(count, m.outputVisibleLines())
			if !strings.Contains(view, m.outputLines[count-visible]) {
				t.Errorf("%s: scrolled past a full screen of output", label)
			}
			if count > visible && !strings.Contains(view, fmt.Sprintf("%d/%d", count, count)) {
				t.Errorf("%s: the indicator does not say the end was reached:\n%s", label, view)
			}
		}
	}
}

// Making the window taller while scrolled to the end must not strand the
// reader on a part-empty screen, where the next few Up presses do nothing.
func TestOutputResizeKeepsScrollInRange(t *testing.T) {
	m := model{
		state: stateOutput, width: 80, height: 24,
		outputLines: numberedLines(100), outputScroll: 86,
	}
	updated, _ := m.Update(tea.WindowSizeMsg{Width: 80, Height: 90})
	got := updated.(model)
	if want := 100 - got.outputVisibleLines(); got.outputScroll != want {
		t.Errorf("scroll is %d after the resize, want %d", got.outputScroll, want)
	}
}

func TestRunningViewFitsAtAnyHeight(t *testing.T) {
	for height := 1; height <= 90; height++ {
		for script := range scriptFrames {
			for _, total := range []int{0, 8} {
				m := model{
					state: stateRunning, width: 80, height: height,
					currentScript: script, outputTitle: script,
					outputLines:   numberedLines(500),
					progressLabel: "working", progressCurr: 3, progressTotal: total,
				}
				label := fmt.Sprintf("%s, height %d, bar total %d", script, height, total)
				view := m.View()
				assertFits(t, label, view, height)
				if !strings.Contains(view, "» "+script) {
					t.Errorf("%s: the title is missing", label)
				}
				if height >= 5 && !strings.Contains(view, "Running") {
					t.Errorf("%s: the footer is missing", label)
				}
				if height >= 24 && !strings.Contains(view, "n___n") {
					t.Errorf("%s: the raccoon is missing", label)
				}
			}
		}
	}
}

func TestExportViewFitsAndKeepsTheSelection(t *testing.T) {
	for height := 1; height <= 90; height++ {
		for sel := range exportFormats {
			m := model{state: stateExport, width: 80, height: height, exportSel: sel, exportResult: "/tmp/report.html"}
			label := fmt.Sprintf("height %d, selection %d", height, sel)
			view := m.View()
			assertFits(t, label, view, height)
			if !strings.Contains(view, "Save the audit") {
				t.Errorf("%s: the title is missing", label)
			}
			if height >= 5 {
				if !strings.Contains(view, exportFormats[sel].label) {
					t.Errorf("%s: the selected format is off screen", label)
				}
				if !strings.Contains(view, "Esc Back") {
					t.Errorf("%s: the footer is missing", label)
				}
			}
		}
	}
}

func TestStatusSurvivesANarrowTerminal(t *testing.T) {
	for width := 15; width <= 80; width++ {
		for _, success := range []bool{true, false} {
			m := model{
				state: stateOutput, width: width, height: 24, outputSuccess: success,
				outputTitle: "A very long title that cannot fit a narrow terminal",
			}
			want := "✗ Failed"
			if success {
				want = "✓ Completed"
			}
			found := false
			for _, row := range strings.Split(stripANSI(m.View()), "\n") {
				if strings.Contains(row, want) {
					found = true
					if w := runewidth.StringWidth(row); w > width {
						t.Errorf("width %d: status row is %d columns:\n%q", width, w, row)
					}
				}
			}
			if !found {
				t.Errorf("width %d: %q is missing", width, want)
			}
		}
	}
}

// Bytes are not columns: "⚠" is three bytes and one column.
func TestOutputLinesAreCutByColumns(t *testing.T) {
	box := "| ⚠ FileVault: Unknown                  |" // 41 columns, 43 bytes
	m := model{state: stateOutput, width: 45, height: 24, outputLines: []string{box}}
	if !strings.Contains(stripANSI(m.View()), box) {
		t.Errorf("a line that fits lost its right border:\n%s", stripANSI(m.View()))
	}

	long := strings.Repeat("─", 200)
	views := map[string]model{
		"output":  {state: stateOutput, width: 45, height: 24, outputLines: []string{long}},
		"running": {state: stateRunning, width: 45, height: 24, currentScript: "memory.sh", outputLines: []string{long}},
		"label":   {state: stateRunning, width: 80, height: 24, currentScript: "memory.sh", progressTotal: 8, progressCurr: 1, progressLabel: long},
	}
	for name, v := range views {
		view := stripANSI(v.View())
		if !utf8.ValidString(view) {
			t.Errorf("%s: a character was cut in half", name)
		}
		if name == "output" || name == "running" {
			for _, row := range strings.Split(view, "\n") {
				if w := runewidth.StringWidth(row); w > v.width {
					t.Errorf("%s: row is %d columns in %d:\n%q", name, w, v.width, row)
				}
			}
		}
	}
}
