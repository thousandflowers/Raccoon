package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	tea "github.com/charmbracelet/bubbletea"
)

const (
	cols    = 4
	cellW   = 10
)

type model struct {
	items       []item
	selectedIdx int
	binPath     string
	quitting   bool
}

type item struct {
	title string
	cmd   string
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			m.quitting = true
			return m, tea.Quit

		case "left", "h":
			if m.selectedIdx > 0 {
				m.selectedIdx--
			}

		case "right", "l":
			if m.selectedIdx < len(m.items)-1 {
				m.selectedIdx++
			}

		case "up", "k":
			if m.selectedIdx >= cols {
				m.selectedIdx -= cols
			}

		case "down", "j":
			nextIdx := m.selectedIdx + cols
			if nextIdx < len(m.items) {
				m.selectedIdx = nextIdx
			}

		case "enter":
			selected := m.items[m.selectedIdx]
			if selected.cmd != "" {
				scriptPath := filepath.Join(m.binPath, selected.cmd)
				cmd := exec.Command("bash", scriptPath)
				cmd.Stdout = os.Stdout
				cmd.Stderr = os.Stderr
				cmd.Run()
			}
		}
	}
	return m, nil
}

func (m model) View() string {
	if m.quitting {
		return ""
	}

	out := "\033[36mRaccoon\033[0m\n"
	out += "macOS companion toolkit\n\n"

	rows := (len(m.items) + cols - 1) / cols

	for row := 0; row < rows; row++ {
		for col := 0; col < cols; col++ {
			idx := row*cols + col
			if idx >= len(m.items) {
				break
			}

			itm := m.items[idx]
			if idx == m.selectedIdx {
				out += fmt.Sprintf(" \033[42m%-10s\033[0m ", itm.title)
			} else {
				out += fmt.Sprintf(" %-10s ", itm.title)
			}
		}
		out += "\n"
	}

	out += "\n\033[90m←→ Navigate · ↑↓ Rows · Enter Run · Q Quit\033[0m"

	return out
}

func main() {
	home, _ := os.UserHomeDir()
	binPath := filepath.Join(home, ".raccoon", "bin")

	items := []item{
		{title: "upgrade", cmd: "upgrade.sh"},
		{title: "audit", cmd: "audit.sh"},
		{title: "network", cmd: "network.sh"},
		{title: "disk", cmd: "disk.sh"},
		{title: "memory", cmd: "memory.sh"},
		{title: "ssh", cmd: "ssh.sh"},
		{title: "git", cmd: "git.sh"},
		{title: "ports", cmd: "ports.sh"},
		{title: "battery", cmd: "battery.sh"},
		{title: "backup", cmd: "backup.sh"},
		{title: "env", cmd: "env.sh"},
		{title: "startup", cmd: "startup.sh"},
		{title: "trash", cmd: "trash.sh"},
		{title: "fonts", cmd: "fonts.sh"},
		{title: "history", cmd: "history.sh"},
		{title: "certs", cmd: "certs.sh"},
		{title: "docker", cmd: "docker.sh"},
		{title: "xcode", cmd: "xcode.sh"},
	}

	m := model{
		items:       items,
		selectedIdx: 0,
		binPath:     binPath,
	}

	fmt.Print("\033[2J\033[H]")

	program := tea.NewProgram(m)
	if _, err := program.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
	}
}
