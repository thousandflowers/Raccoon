package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("86")).
			MarginBottom(1)

	helpStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
)

type model struct {
	list     list.Model
	binPath  string
	quitting bool
}

type MenuItem struct {
	title string
	cmd   string
}

func (i MenuItem) Title() string       { return i.title }
func (i MenuItem) Description() string { return "" }
func (i MenuItem) FilterValue() string { return i.title }

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
		case "enter":
			selected := m.list.SelectedItem().(MenuItem)
			if selected.cmd != "" {
				scriptPath := filepath.Join(m.binPath, selected.cmd)
				cmd := exec.Command("bash", scriptPath)
				cmd.Stdout = os.Stdout
				cmd.Stderr = os.Stderr
				cmd.Run()
			}
		}
	}

	newList, cmd := m.list.Update(msg)
	m.list = newList
	return m, cmd
}

func (m model) View() string {
	if m.quitting {
		return ""
	}

	return titleStyle.Render("Raccoon") + "\n" +
		m.list.View() + "\n\n" +
		helpStyle.Render("↑↓ Navigate · Enter Run · Q Quit")
}

func main() {
	home, _ := os.UserHomeDir()
	repoPath := filepath.Join(home, ".raccoon")
	binPath := filepath.Join(repoPath, "bin")

	items := []list.Item{
		MenuItem{title: "upgrade", cmd: "upgrade.sh"},
		MenuItem{title: "audit", cmd: "audit.sh"},
		MenuItem{title: "audit deep", cmd: "audit.sh --deep"},
		MenuItem{title: "network", cmd: "network.sh"},
		MenuItem{title: "disk", cmd: "disk.sh"},
		MenuItem{title: "memory", cmd: "memory.sh"},
		MenuItem{title: "ssh", cmd: "ssh.sh"},
		MenuItem{title: "git", cmd: "git.sh"},
		MenuItem{title: "ports", cmd: "ports.sh"},
		MenuItem{title: "battery", cmd: "battery.sh"},
		MenuItem{title: "backup", cmd: "backup.sh"},
		MenuItem{title: "env", cmd: "env.sh"},
		MenuItem{title: "startup", cmd: "startup.sh"},
		MenuItem{title: "trash", cmd: "trash.sh"},
		MenuItem{title: "fonts", cmd: "fonts.sh"},
		MenuItem{title: "history", cmd: "history.sh"},
		MenuItem{title: "certs", cmd: "certs.sh"},
		MenuItem{title: "docker", cmd: "docker.sh"},
		MenuItem{title: "xcode", cmd: "xcode.sh"},
	}

	l := list.New(items, list.NewDefaultDelegate(), 0, 0)
	l.SetShowStatusBar(false)
	l.SetFilteringEnabled(false)
	l.SetShowHelp(false)
	l.Title = ""

	m := model{
		list:    l,
		binPath: binPath,
	}

	fmt.Print("\033[2J\033[H]")
	tea.NewProgram(m).Run()
}