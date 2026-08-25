package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// stubSudo puts a fake `sudo` first on PATH for the duration of the test.
// exitN is what it returns for `sudo -n true`, i.e. whether a timestamp is
// already cached. No real sudo is ever invoked.
func stubSudo(t *testing.T, exitN int) {
	t.Helper()
	dir := t.TempDir()
	script := fmt.Sprintf("#!/bin/bash\n[[ \"$1\" == \"-n\" ]] && exit %d\nexit 0\n", exitN)
	if err := os.WriteFile(filepath.Join(dir, "sudo"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+":"+os.Getenv("PATH"))
}

// Issue #23: a sudo prompt raised while the TUI holds the terminal has its
// password split between sudo and the TUI key reader, and comes back "Sorry,
// try again". Items that need root must authenticate first, with the terminal
// released — that is tea.ExecProcess, which surfaces as tea.execMsg.
func TestLaunchPrimesSudoBeforeARootScript(t *testing.T) {
	stubSudo(t, 1) // no cached timestamp
	m := model{binPath: t.TempDir()}

	msg := m.launch(item{title: "apps", script: "apps.sh", needsSudo: true})()

	if got := fmt.Sprintf("%T", msg); got != "tea.execMsg" {
		t.Fatalf("expected the sudo pre-auth to run first, got %s", got)
	}
	if m.state != stateRunning {
		t.Fatalf("state = %v, want stateRunning", m.state)
	}
	if m.currentScript != "apps.sh" {
		t.Fatalf("currentScript = %q, want apps.sh", m.currentScript)
	}
}

func TestLaunchSkipsThePromptWhenSudoIsCached(t *testing.T) {
	stubSudo(t, 0) // timestamp already valid
	m := model{binPath: t.TempDir()}

	msg := m.launch(item{title: "apps", script: "missing.sh", needsSudo: true})()

	if _, ok := msg.(sudoPrimed); !ok {
		t.Fatalf("a valid timestamp must skip the prompt entirely, got %T", msg)
	}
}

func TestLaunchNeverPrimesSudoForAPlainScript(t *testing.T) {
	stubSudo(t, 1)
	m := model{binPath: t.TempDir()}

	msg := m.launch(item{title: "disk", script: "missing.sh"})()

	if got := fmt.Sprintf("%T", msg); got != "tea.BatchMsg" {
		t.Fatalf("a script that needs no root must start without pre-auth, got %s", got)
	}
}

// The contract the scripts rely on: anything spawned by the TUI is told never
// to raise a password prompt, because the TUI owns the terminal.
func TestSpawnedScriptsAreToldNotToPrompt(t *testing.T) {
	dir := t.TempDir()
	probe := filepath.Join(dir, "probe.sh")
	body := "#!/bin/bash\necho \"RCC_NO_PROMPT=${RCC_NO_PROMPT:-unset}\"\n"
	if err := os.WriteFile(probe, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}

	msg := startScript(dir, "probe.sh", nil)()

	out, ok := msg.(scriptOutput)
	if !ok {
		t.Fatalf("expected script output, got %T: %v", msg, msg)
	}
	if out.line != "RCC_NO_PROMPT=1" {
		t.Fatalf("child environment: %q, want RCC_NO_PROMPT=1", out.line)
	}
	if out.cmd != nil && out.cmd.Process != nil {
		_ = out.cmd.Wait()
	}
}

// A pty with no size, or a window narrower than the padding, used to hand
// strings.Repeat a negative count and panic the whole TUI on the first frame.
func TestViewsSurviveAPathologicalTerminal(t *testing.T) {
	sizes := []struct{ w, h int }{{0, 0}, {1, 1}, {2, 3}, {5, 5}, {9, 2}, {80, 24}}
	states := []modelState{stateMenu, stateSearch, stateRunning, stateOutput}

	for _, sz := range sizes {
		for _, st := range states {
			m := model{
				items:         items(),
				width:         sz.w,
				height:        sz.h,
				state:         st,
				outputTitle:   "a title long enough to overrun any narrow separator",
				currentScript: "apps.sh",
				outputLines:   []string{"first", strings.Repeat("x", 500)},
				progressCurr:  3,
				progressTotal: 8,
				progressLabel: "casks: upgrading...",
				searchQuery:   "app",
			}
			func() {
				defer func() {
					if r := recover(); r != nil {
						t.Fatalf("View panicked at %dx%d state %d: %v", sz.w, sz.h, st, r)
					}
				}()
				_ = m.View()
			}()
		}
	}
}
