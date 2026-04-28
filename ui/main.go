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
			Foreground(lipgloss.Color("86"))

	helpStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("240")).
			MarginTop(1)
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
	case tea.WindowSizeMsg:
		m.list.SetSize(msg.Width-4, msg.Height-8)
		return m, nil

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
			return m, nil
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
		"macOS companion toolkit\n\n" +
		m.list.View() + "\n\n" +
		helpStyle.Render("↑↓ Navigate · Enter Run · Q Quit")
}

func main() {
	home, _ := os.UserHomeDir()
	binPath := filepath.Join(home, ".raccoon", "bin")

	items := []list.Item{
		MenuItem{title: "1. upgrade — Update packages", cmd: "upgrade.sh"},
		MenuItem{title: "2. audit — Security audit", cmd: "audit.sh"},
		MenuItem{title: "3. audit deep — Full audit", cmd: "audit.sh --deep"},
		MenuItem{title: "4. network — Network info", cmd: "network.sh"},
		MenuItem{title: "5. disk — Disk space", cmd: "disk.sh"},
		MenuItem{title: "6. memory — Memory usage", cmd: "memory.sh"},
		MenuItem{title: "7. ssh — SSH keys", cmd: "ssh.sh"},
		MenuItem{title: "8. git — Git repos", cmd: "git.sh"},
		MenuItem{title: "9. ports — Open ports", cmd: "ports.sh"},
		MenuItem{title: "10. battery — Battery health", cmd: "battery.sh"},
		MenuItem{title: "11. backup — Time Machine", cmd: "backup.sh"},
		MenuItem{title: "12. env — Shell environment", cmd: "env.sh"},
		MenuItem{title: "13. startup — Launch agents", cmd: "startup.sh"},
		MenuItem{title: "14. trash — Trash contents", cmd: "trash.sh"},
		MenuItem{title: "15. fonts — Font duplicates", cmd: "fonts.sh"},
		MenuItem{title: "16. history — Shell history", cmd: "history.sh"},
		MenuItem{title: "17. certs — SSL certificates", cmd: "certs.sh"},
		MenuItem{title: "18. docker — Docker images", cmd: "docker.sh"},
		MenuItem{title: "19. xcode — Xcode", cmd: "xcode.sh"},
	}

	l := list.New(items, list.NewDefaultDelegate(), 40, 20)
	l.SetShowStatusBar(false)
	l.SetFilteringEnabled(false)
	l.SetShowHelp(false)
	l.Title = ""

	m := model{
		list:    l,
		binPath: binPath,
	}

	fmt.Print("\033[2J\033[H]")

	program := tea.NewProgram(m)
	if _, err := program.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
	}
}