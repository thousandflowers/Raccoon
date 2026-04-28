package main

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/muesli/termenv"
)

func main() {
	fmt.Println("Starting Raccoon...")
	
	m := model{}
	
	// Force dumb terminal mode
	termenv.ResetOutputColorProfile()
	
	p := tea.NewProgram(m)
	if err := p.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("Done")
}

type model struct{}

func (m model) Init() tea.Cmd { return nil }

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if key, ok := msg.(tea.KeyMsg); ok {
		switch key.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m model) View() string {
	return "\033[36mRaccoon\033[0m\nmacOS companion\nUse arrow keys to navigate, Enter to run, Q to quit"
}