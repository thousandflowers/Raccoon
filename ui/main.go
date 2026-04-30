package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

type model struct {
	items       []item
	selectedIdx int
	binPath     string
	quitting    bool
	searchMode  bool
	searchQuery string
}

type item struct {
	title       string
	cmd         string
	description string
}

type cmdFinishedMsg struct{}

func (m model) Init() tea.Cmd {
	return nil
}

func (m *model) filteredItems() []item {
	if m.searchQuery == "" {
		return m.items
	}
	query := strings.ToLower(m.searchQuery)
	var filtered []item
	for _, it := range m.items {
		if strings.Contains(strings.ToLower(it.title), query) ||
			strings.Contains(strings.ToLower(it.description), query) {
			filtered = append(filtered, it)
		}
	}
	return filtered
}

func (m *model) selectedItem() item {
	filtered := m.filteredItems()
	if m.selectedIdx >= 0 && m.selectedIdx < len(filtered) {
		return filtered[m.selectedIdx]
	}
	return item{}
}

func (m *model) dynamicCols() int {
	count := len(m.filteredItems())
	if count < 4 {
		return count
	}
	return 4
}

func (m *model) clampSelectedIdx() {
	filtered := m.filteredItems()
	if m.selectedIdx >= len(filtered) {
		if len(filtered) > 0 {
			m.selectedIdx = len(filtered) - 1
		} else {
			m.selectedIdx = 0
		}
	}
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case cmdFinishedMsg:
		return m, nil
	case tea.KeyMsg:
		if m.searchMode {
			switch msg.Type {
			case tea.KeyEsc:
				m.searchMode = false
				m.searchQuery = ""
				m.selectedIdx = 0
				return m, nil
			case tea.KeyBackspace:
				if len(m.searchQuery) > 0 {
					m.searchQuery = m.searchQuery[:len(m.searchQuery)-1]
					m.clampSelectedIdx()
				} else {
					m.searchMode = false
					m.selectedIdx = 0
				}
				return m, nil
			case tea.KeyUp:
				if m.selectedIdx > 0 {
					m.selectedIdx--
				}
				return m, nil
			case tea.KeyDown:
				filtered := m.filteredItems()
				if m.selectedIdx < len(filtered)-1 {
					m.selectedIdx++
				}
				return m, nil
			case tea.KeyLeft:
				return m, nil
			case tea.KeyRight:
				return m, nil
			case tea.KeyEnter:
				selected := m.selectedItem()
				if selected.cmd != "" {
					scriptPath := filepath.Join(m.binPath, selected.cmd)
					c := exec.Command("bash", scriptPath)
					return m, tea.ExecProcess(c, func(err error) tea.Msg {
						return cmdFinishedMsg{}
					})
				}
				return m, nil
			default:
				if msg.Type == tea.KeyRunes {
					m.searchQuery += string(msg.Runes)
					m.selectedIdx = 0
				}
				return m, nil
			}
		}

		switch msg.String() {
		case "q", "ctrl+c":
			m.quitting = true
			return m, tea.Quit

		case "/":
			m.searchMode = true
			m.searchQuery = ""
			m.selectedIdx = 0
			return m, nil

		case "left", "h":
			if m.selectedIdx%m.dynamicCols() > 0 {
				m.selectedIdx--
			}

		case "right", "l":
			filtered := m.filteredItems()
			if m.selectedIdx%m.dynamicCols() < m.dynamicCols()-1 && m.selectedIdx < len(filtered)-1 {
				m.selectedIdx++
			}

		case "up", "k":
			if m.selectedIdx >= m.dynamicCols() {
				m.selectedIdx -= m.dynamicCols()
			}

		case "down", "j":
			filtered := m.filteredItems()
			nextIdx := m.selectedIdx + m.dynamicCols()
			if nextIdx < len(filtered) {
				m.selectedIdx = nextIdx
			}

		case "enter":
			selected := m.selectedItem()
			if selected.cmd != "" {
				scriptPath := filepath.Join(m.binPath, selected.cmd)
				c := exec.Command("bash", scriptPath)
				return m, tea.ExecProcess(c, func(err error) tea.Msg {
					return cmdFinishedMsg{}
				})
			}
		}
	}

	return m, nil
}

func (m model) View() string {
	if m.quitting {
		return ""
	}

	out := "     _\n"
	out += `   / \_/\_   ` + "\x1b[36mRaccoon\x1b[0m\n"
	out += "  ( o.o )  \x1b[90mmacOS companion toolkit\x1b[0m\n"
	out += "   > ^ <\n\n"

	filtered := m.filteredItems()

	if len(filtered) == 0 {
		out += "\033[90mNo matches found\033[0m\n"
	} else {
		dynamicCols := m.dynamicCols()
		if m.searchMode {
			dynamicCols = 1
		}
		rows := (len(filtered) + dynamicCols - 1) / dynamicCols

		for row := 0; row < rows; row++ {
			for col := 0; col < dynamicCols; col++ {
				idx := row*dynamicCols + col
				if idx >= len(filtered) {
					break
				}

				itm := filtered[idx]

				if idx == m.selectedIdx {
					out += fmt.Sprintf(" \033[42m%-10s\033[0m ", itm.title)
				} else {
					out += fmt.Sprintf(" %-10s ", itm.title)
				}
			}
			out += "\n"
		}
	}

	if m.searchMode {
		out += fmt.Sprintf("\n\033[90m[search: %s_]\033[0m", m.searchQuery)
		out += "\n\033[90m↑↓ Navigate · Enter Run · Esc Cancel\033[0m"
	} else {
		out += "\n\033[90m←→ Navigate · ↑↓ Rows · Enter Run · / Search · Q Quit\033[0m"
	}

	return out
}

func main() {
	home, _ := os.UserHomeDir()
	binPath := filepath.Join(home, ".raccoon", "bin")

	items := []item{
		{title: "upgrade", cmd: "upgrade.sh", description: "Update packages"},
		{title: "audit", cmd: "audit.sh", description: "Security audit"},
		{title: "network", cmd: "network.sh", description: "Network status"},
		{title: "disk", cmd: "disk.sh", description: "Disk info"},
		{title: "memory", cmd: "memory.sh", description: "Memory usage"},
		{title: "ssh", cmd: "ssh.sh", description: "SSH keys"},
		{title: "git", cmd: "git.sh", description: "Git repos"},
		{title: "ports", cmd: "ports.sh", description: "Open ports"},
		{title: "battery", cmd: "battery.sh", description: "Battery status"},
		{title: "backup", cmd: "backup.sh", description: "Backup status"},
		{title: "env", cmd: "env.sh", description: "Environment"},
		{title: "startup", cmd: "startup.sh", description: "Startup items"},
		{title: "trash", cmd: "trash.sh", description: "Trash management"},
		{title: "fonts", cmd: "fonts.sh", description: "Font management"},
		{title: "history", cmd: "history.sh", description: "Shell history"},
		{title: "certs", cmd: "certs.sh", description: "SSL certificates"},
		{title: "docker", cmd: "docker.sh", description: "Docker status"},
		{title: "xcode", cmd: "xcode.sh", description: "Xcode tools"},
	}

	m := model{
		items:       items,
		selectedIdx: 0,
		binPath:     binPath,
	}

	program := tea.NewProgram(m)
	if err := program.Start(); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
	}
}
