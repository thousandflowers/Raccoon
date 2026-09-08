package main

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

// The picker must offer what the script accepts. Read from bin/audit.sh rather
// than from a copy of the list, the way fleetSubcommands reads bin/fleet.sh:
// a format added to one side and not the other is the drift this catches.
func TestExportFormatsAreTheOnesAuditAccepts(t *testing.T) {
	src, err := os.ReadFile("../bin/audit.sh")
	if err != nil {
		t.Fatalf("cannot read bin/audit.sh: %v", err)
	}
	m := regexp.MustCompile(`(?m)^\tmd \| html \| csv \| rtf \| json\)`).Find(src)
	if m == nil {
		t.Fatal("cannot find the --export format guard in bin/audit.sh")
	}
	accepted := map[string]bool{}
	for _, f := range strings.Split(strings.TrimSuffix(strings.TrimSpace(string(m)), ")"), "|") {
		accepted[strings.TrimSpace(f)] = true
	}

	for _, f := range exportFormats {
		if !accepted[f.id] {
			t.Errorf("the picker offers %q, which audit.sh --export refuses", f.id)
		}
		delete(accepted, f.id)
	}
	for id := range accepted {
		t.Errorf("audit.sh --export accepts %q, which the picker never offers", id)
	}
}

// Every row has to be readable: a format with no label or no description is a
// blank line in a list of five.
func TestExportViewShowsEveryFormat(t *testing.T) {
	out := (model{state: stateExport}).exportView()
	for _, f := range exportFormats {
		if f.label == "" || f.desc == "" {
			t.Errorf("format %q has an empty label or description", f.id)
		}
		if !strings.Contains(out, f.label) {
			t.Errorf("the picker does not draw %q", f.label)
		}
	}
	if !strings.Contains(out, "Esc Back") {
		t.Error("the picker does not say how to leave it")
	}
}

// The export key is offered only where it means something.
func TestExportIsOfferedOnlyAfterAnAudit(t *testing.T) {
	audit := model{state: stateOutput, currentScript: "audit.sh", outputLines: []string{"x"}}
	if !strings.Contains(audit.outputView(), "Export") {
		t.Error("a finished audit does not offer the export key")
	}
	disk := model{state: stateOutput, currentScript: "disk.sh", outputLines: []string{"x"}}
	if strings.Contains(disk.outputView(), "Export") {
		t.Error("a finished disk run offers an export it cannot do")
	}
}
