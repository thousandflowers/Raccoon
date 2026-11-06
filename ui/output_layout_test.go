package main

import (
	"fmt"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
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
	for _, height := range []int{5, 8, 12, 13, 24, 30, 50, 90} {
		for _, count := range []int{0, 3, 20, 40, 85, 500} {
			for _, success := range []bool{true, false} {
				m := model{
					state: stateOutput, width: 80, height: height,
					currentScript: "audit.sh", outputTitle: "Security Audit",
					outputLines: numberedLines(count), outputSuccess: success,
				}
				label := fmt.Sprintf("height %d, %d lines, success %v", height, count, success)
				view := m.outputView()

				assertFits(t, label, view, height)
				want := "✗ Failed"
				if success {
					want = "✓ Completed"
				}
				if !strings.Contains(view, want) {
					t.Errorf("%s: %q is missing", label, want)
				}
				if !strings.Contains(view, "Quit") {
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

func TestRunningViewFitsWithLongOutput(t *testing.T) {
	for _, height := range []int{24, 30, 50, 90} {
		for script := range scriptFrames {
			for _, total := range []int{0, 8} {
				m := model{
					state: stateRunning, width: 80, height: height,
					currentScript: script, outputTitle: script,
					outputLines:   numberedLines(500),
					progressLabel: "working", progressCurr: 3, progressTotal: total,
				}
				view := m.runningView()
				assertFits(t, fmt.Sprintf("%s, height %d, bar total %d", script, height, total), view, height)
				if !strings.Contains(view, "n___n") {
					t.Errorf("%s, height %d: the raccoon is missing", script, height)
				}
			}
		}
	}
}

func TestExportViewFits(t *testing.T) {
	for _, height := range []int{24, 30, 50, 90} {
		m := model{state: stateExport, width: 80, height: height, exportResult: "/tmp/report.html"}
		assertFits(t, fmt.Sprintf("height %d", height), m.exportView(), height)
	}
}
