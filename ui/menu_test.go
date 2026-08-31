package main

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// binCommands is every command that actually exists, read off disk. Both menus
// are checked against this rather than against each other: two hand-written
// lists compared to one another agree happily while both are missing wifi,
// which is exactly what happened.
func binCommands(t *testing.T) map[string]bool {
	t.Helper()
	paths, err := filepath.Glob("../bin/*.sh")
	if err != nil || len(paths) == 0 {
		t.Fatalf("no scripts found in ../bin: %v", err)
	}
	out := map[string]bool{}
	for _, p := range paths {
		out[strings.TrimSuffix(filepath.Base(p), ".sh")] = true
	}
	return out
}

// menuCommands is every runnable top-level row, headings and children excluded.
func menuCommands() map[string]item {
	out := map[string]item{}
	for _, it := range items() {
		if it.isHeading() {
			continue
		}
		out[it.title] = it
	}
	return out
}

func sortedKeys[V any](m map[string]V) []string {
	k := make([]string, 0, len(m))
	for s := range m {
		k = append(k, s)
	}
	sort.Strings(k)
	return k
}

func TestMenuHasEveryCommandThatExists(t *testing.T) {
	bin, menu := binCommands(t), menuCommands()
	for _, name := range sortedKeys(bin) {
		if _, ok := menu[name]; !ok {
			t.Errorf("bin/%s.sh has no row in the menu", name)
		}
	}
	for _, name := range sortedKeys(menu) {
		if !bin[name] {
			t.Errorf("the menu offers %q, but bin/%s.sh does not exist", name, name)
		}
	}
	if len(bin) != len(menu) {
		t.Errorf("%d scripts against %d menu rows", len(bin), len(menu))
	}
}

func TestEveryMenuRowRunsTheScriptItNames(t *testing.T) {
	for _, it := range items() {
		if it.isHeading() {
			continue
		}
		if len(it.children) > 0 {
			continue // a parent runs nothing; its children carry the script
		}
		if it.script != it.title+".sh" {
			t.Errorf("row %q runs %q", it.title, it.script)
		}
	}
}

// fleetSubcommands reads the dispatch out of bin/fleet.sh, so the menu is
// checked against what fleet answers to today rather than against a copy of it.
func fleetSubcommands(t *testing.T) map[string]bool {
	t.Helper()
	src, err := os.ReadFile("../bin/fleet.sh")
	if err != nil {
		t.Fatalf("cannot read bin/fleet.sh: %v", err)
	}
	block := regexp.MustCompile(`(?s)local sub="\$\{1:-help\}".*?\n\tesac`).Find(src)
	if block == nil {
		t.Fatal("cannot find fleet's dispatch — did main() change shape?")
	}
	out := map[string]bool{}
	for _, m := range regexp.MustCompile(`(?m)^\t\t([a-z]+)\)`).FindAllSubmatch(block, -1) {
		out[string(m[1])] = true
	}
	if len(out) == 0 {
		t.Fatal("read no subcommands out of fleet's dispatch")
	}
	return out
}

// The five in the menu are the ones a menu can run. The three left out are left
// out for one reason, written down here so that a sixth subcommand arriving
// without arguments fails this test instead of being silently forgotten.
var fleetNotInMenu = map[string]string{
	"add":    "takes a host to add",
	"remove": "takes a host to remove",
	"run":    "takes the command to run",
	"help":   "is the default, not a thing to pick",
	"group":  "the menu offers `groups`, which is `group list`; the rest of group takes arguments",
}

func TestFleetChildrenMatchWhatFleetAnswersTo(t *testing.T) {
	dispatch := fleetSubcommands(t)

	var parent *item
	for _, it := range items() {
		if len(it.children) > 0 {
			c := it
			parent = &c
		}
	}
	if parent == nil {
		t.Fatal("no menu row has children")
	}

	inMenu := map[string]bool{}
	for _, c := range parent.children {
		name := c.args[0]
		inMenu[name] = true
		if !dispatch[name] {
			t.Errorf("the menu offers `fleet %s`, which fleet does not answer to", c.title)
		}
	}
	for _, name := range sortedKeys(dispatch) {
		if inMenu[name] {
			continue
		}
		if _, known := fleetNotInMenu[name]; !known {
			t.Errorf("fleet answers to %q and the menu does not offer it; "+
				"add it to the menu, or to fleetNotInMenu with the reason", name)
		}
	}
}

func TestHeadingsAreNotSelectableAndNotRunnable(t *testing.T) {
	m := model{items: items(), width: 80, height: 24}
	f := m.filtered()

	headings := 0
	for _, it := range f {
		if it.isHeading() {
			headings++
			if it.script != "" || len(it.children) > 0 {
				t.Errorf("heading %q has something to run", it.title)
			}
		}
	}
	if headings != 4 {
		t.Errorf("%d headings, want 4", headings)
	}

	// g and G have to land on a command, not on a label.
	m.selected = 0
	m.skipHeadings(1)
	if f[m.selected].isHeading() {
		t.Errorf("g landed on the heading %q", f[m.selected].title)
	}
	m.selected = len(f) - 1
	m.skipHeadings(-1)
	if f[m.selected].isHeading() {
		t.Errorf("G landed on the heading %q", f[m.selected].title)
	}
}

func TestFleetOpensInPlaceWithoutMovingAnythingElse(t *testing.T) {
	closed := (&model{items: items()}).filtered()
	open := (&model{items: items(), fleetExpanded: true}).filtered()

	if len(open) != len(closed)+5 {
		t.Fatalf("open list is %d rows, closed is %d; want five more", len(open), len(closed))
	}
	// The rows before fleet are untouched, and the five children follow it.
	var at int
	for i, it := range closed {
		if len(it.children) > 0 {
			at = i
		}
	}
	for i := 0; i <= at; i++ {
		if open[i].title != closed[i].title {
			t.Errorf("row %d changed from %q to %q when fleet opened", i, closed[i].title, open[i].title)
		}
	}
	for i, want := range []string{"scan", "audit", "status", "list", "groups"} {
		if got := open[at+1+i].title; got != want {
			t.Errorf("child %d is %q, want %q", i, got, want)
		}
		if !open[at+1+i].indent {
			t.Errorf("child %q is not drawn as a child", want)
		}
	}
}

func TestSearchNeverReturnsAHeading(t *testing.T) {
	for _, q := range []string{"e", "a", "net", "MAIN", "system"} {
		m := model{items: items(), searchQuery: q}
		for _, it := range m.filtered() {
			if it.isHeading() {
				t.Errorf("searching %q returned the heading %q", q, it.title)
			}
		}
	}
}
