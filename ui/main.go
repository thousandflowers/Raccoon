package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("86")).
			MarginLeft(2)

	itemStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("245")).
			Padding(0, 1, 0, 1)

	selectedStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("86")).
			Background(lipgloss.Color("236")).
			Bold(true).
			Padding(0, 1, 0, 1)

	helpStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("240")).
			MarginTop(1)
)

const (
	cols    = 4
	colWidth = 18
)

type model struct {
	items        []item
	selectedIdx  int
	binPath      string
	quitting    bool
	width        int
	height       int
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
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

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
			row := m.selectedIdx / cols
			nextRow := row + 1
			nextIdx := nextRow*cols + (m.selectedIdx % cols)
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

	// Title
	out := titleStyle.Render("Raccoon") + "\n"
	out += "macOS companion toolkit\n\n"

	// Grid
	rows := (len(m.items) + cols - 1) / cols

	for row := 0; row < rows; row++ {
		for col := 0; col < cols; col++ {
			idx := row*cols + col
			if idx >= len(m.items) {
				break
			}

			itm := m.items[idx]
			if idx == m.selectedIdx {
				out += " " + selectedStyle.Render(itm.title) + " "
			} else {
				out += " " + itemStyle.Render(itm.title) + " "
			}
		}
		out += "\n"
	}

	// Help
	out += "\n" + helpStyle.Render("←→ Navigate · ↑↓ Rows · Enter Run · Q Quit")

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
