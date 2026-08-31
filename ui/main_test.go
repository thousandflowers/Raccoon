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

// The audit face must follow what the run actually found. A fixed happy ending
// would announce a verdict the report underneath can contradict.
func TestAuditMood(t *testing.T) {
	cases := []struct {
		name  string
		lines []string
		want  string
	}{
		{"nothing yet", nil, ""},
		{"all passing", []string{"✓ SIP: Enabled", "✓ Firewall: Enabled"}, ""},
		{"one warning", []string{"✓ SIP: Enabled", "⚠ FileVault: Unknown"}, "-.-"},
		{"many warnings", []string{"⚠ a", "⚠ b", "⚠ c"}, "O.O"},
		{"a failure outranks warnings", []string{"⚠ a", "⚠ b", "⚠ c", "✗ boom"}, ">.<"},
		{"ascii fallback icons", []string{"XX boom"}, ">.<"},
		{"colour codes do not hide the icon", []string{"\x1b[0;33m⚠\x1b[0m FileVault"}, "-.-"},
	}
	for _, c := range cases {
		if got := auditMood(c.lines); got != c.want {
			t.Errorf("%s: auditMood() = %q, want %q", c.name, got, c.want)
		}
	}
}

// Every audit frame must be 4 lines with the silhouette intact: the old frames
// varied between 3 and 4 lines, which made the raccoon jump while the script ran.
func TestAuditFramesAreWellFormed(t *testing.T) {
	for i, f := range scriptFrames["audit.sh"] {
		lines := strings.Split(f, "\n")
		if len(lines) != 4 {
			t.Errorf("frame %d has %d lines, want 4", i+1, len(lines))
			continue
		}
		if lines[0] != "" || lines[1] != "   n___n" || lines[3] != "   > ^ <" {
			t.Errorf("frame %d deforms the silhouette:\n%s", i+1, f)
		}
		if !eyeRegexp.MatchString(lines[2]) {
			t.Errorf("frame %d has no readable eye field: %q", i+1, lines[2])
		}
	}
}

// The box must follow the phase the script declared. upgrade replaces things;
// a box that idled on "nothing to do" would misreport a run that is working.
func TestPhaseBox(t *testing.T) {
	cases := []struct{ label, box, eyes string }{
		{"", "( )", ""},
		{"brew: checking...", "( )", ""},
		{"brew: up to date", "( )", ""},
		{"brew: fetching...", "(.)", ""},
		{"brew: downloading...", "(.)", ""},
		{"brew: installing...", "(=)", ""},
		{"npm: updating...", "(=)", ""},
		{"brew: upgrading...", "(=)", ""},
		{"brew: completed", "(#)", ""},
		{"gem: updated", "(#)", ""},
		{"gem: permission error, skipping", "(!)", ">.<"},
	}
	for _, c := range cases {
		box, eyes := phaseBox(c.label)
		if box != c.box || eyes != c.eyes {
			t.Errorf("phaseBox(%q) = (%q, %q), want (%q, %q)", c.label, box, eyes, c.box, c.eyes)
		}
	}
}

// Every upgrade frame is 6 lines with the silhouette intact and exactly one
// three-character box, so swapping the box can never shift the drawing.
func TestUpgradeFramesAreWellFormed(t *testing.T) {
	frames := scriptFrames["upgrade.sh"]
	if len(frames) == 0 {
		t.Fatal("upgrade.sh has no frames")
	}
	for i, f := range frames {
		lines := strings.Split(f, "\n")
		if len(lines) != 6 {
			t.Errorf("frame %d has %d lines, want 6", i+1, len(lines))
			continue
		}
		if lines[2] != "" || lines[3] != "   n___n" || lines[5] != "   > ^ <" {
			t.Errorf("frame %d deforms the silhouette:\n%s", i+1, f)
		}
		if got := len(boxRegexp.FindAllString(lines[4], -1)); got != 1 {
			t.Errorf("frame %d has %d boxes on the face line, want 1", i+1, got)
		}
		if !eyeRegexp.MatchString(lines[4]) {
			t.Errorf("frame %d has no readable eye field: %q", i+1, lines[4])
		}
	}
}

// The app name is the point of the apps sky: a label about a phase must not be
// mistaken for an application, or the sky would rain "checking".
func TestAppName(t *testing.T) {
	cases := []struct{ label, want string }{
		{"", ""},
		{"casks: checking...", ""},
		{"sparkle: scanning...", ""},
		{"apps: downloading Firefox...", "Firefox"},
		{"catalog: updating Dia via brew cask...", "Dia"},
		{"catalog: opening Keka for auto-update...", "Keka"},
		{"cask: Upgrading rectangle", "rectangle"},
	}
	for _, c := range cases {
		if got := appName(c.label); got != c.want {
			t.Errorf("appName(%q) = %q, want %q", c.label, got, c.want)
		}
	}
}

// The sky is always two rows, whatever the name and wherever the cycle is.
// A third row would push the output off screen; a missing one would jitter.
func TestAppsSkyIsAlwaysTwoRows(t *testing.T) {
	for _, name := range []string{"", "Dia", "Firefox", "Visual Studio Code"} {
		for tick := -3; tick < 60; tick++ {
			rows := appsSky(tick, name)
			if len(rows) != 2 {
				t.Fatalf("appsSky(%d, %q) returned %d rows, want 2", tick, name, len(rows))
			}
		}
	}
}

// The name must actually arrive and then be eaten away to nothing, otherwise it
// parks beside the head instead of landing on it.
func TestAppsSkyLandsAndIsEaten(t *testing.T) {
	const name = "Firefox"
	seen := map[string]bool{}
	total := len(appsPath) + len([]rune(name)) + 2
	for tick := 0; tick < total; tick++ {
		joined := strings.TrimSpace(strings.Join(appsSky(tick, name), ""))
		seen[joined] = true
	}
	for _, want := range []string{"Firefox", "irefox", "x", ""} {
		if !seen[want] {
			t.Errorf("the cycle never showed %q", want)
		}
	}
}

// Only the raccoon is stored for apps; the sky is composed at render time.
func TestAppsFramesAreJustTheRaccoon(t *testing.T) {
	for i, f := range scriptFrames["apps.sh"] {
		lines := strings.Split(f, "\n")
		if len(lines) != 4 {
			t.Errorf("frame %d has %d lines, want 4", i+1, len(lines))
			continue
		}
		if lines[0] != "" || lines[1] != "   n___n" || lines[3] != "   > ^ <" {
			t.Errorf("frame %d deforms the silhouette:\n%s", i+1, f)
		}
	}
}

// network's cycle must include the silent frame: without it the jump from three
// arcs back to one reads as a flicker instead of a pulse.
func TestNetworkFramesPulse(t *testing.T) {
	frames := scriptFrames["network.sh"]
	if len(frames) != 4 {
		t.Fatalf("network.sh has %d frames, want 4", len(frames))
	}
	wantArcs := []int{1, 2, 3, 0}
	for i, f := range frames {
		lines := strings.Split(f, "\n")
		if len(lines) != 4 {
			t.Errorf("frame %d has %d lines, want 4", i+1, len(lines))
			continue
		}
		if !strings.HasPrefix(lines[1], "   n___n") || !strings.HasPrefix(lines[3], "   > ^ <") {
			t.Errorf("frame %d deforms the silhouette:\n%s", i+1, f)
		}
		// Count only past the face: the face ends on a bracket of its own.
		sky := lines[2][strings.Index(lines[2], "]")+1:]
		if got := strings.Count(sky, ")"); got != wantArcs[i] {
			t.Errorf("frame %d has %d arcs, want %d", i+1, got, wantArcs[i])
		}
	}
}

// The Percent column is read straight from the table. Computing it per volume
// would lie on APFS, where volumes in one container share the free space.
func TestDiskVolumes(t *testing.T) {
	lines := []string{
		"[4/5] Space Usage...",
		"| Mount                  | Used       | Free       | Percent    |",
		"| ---------------------- | ---------- | ---------- | ---------- |",
		"| /                      | 12Gi       | 59Gi       | 17%        |",
		"| /System/Volumes/Data   | 352Gi      | 59Gi       | 86%        |",
		"✓",
	}
	got := diskVolumes(lines)
	want := []volume{{"/", 17}, {"/System/Volumes/Data", 86}}
	if len(got) != len(want) {
		t.Fatalf("got %d volumes, want %d: %v", len(got), len(want), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("volume %d = %v, want %v", i, got[i], want[i])
		}
	}
}

// The face must follow the worst volume anywhere, not the worst one currently
// on screen: a full disk on page two still needs to be noticed.
func TestDiskFaceFollowsTheWorstVolume(t *testing.T) {
	cases := []struct {
		vols []volume
		want string
	}{
		{nil, "o.o"},
		{[]volume{{"/", 17}}, "o.o"},
		{[]volume{{"/", 17}, {"/d", 65}}, "-.-"},
		{[]volume{{"/", 17}, {"/d", 86}}, ">.<"},
		{[]volume{{"/", 17}, {"/d", 97}}, "x.x"},
	}
	for _, c := range cases {
		if got := diskFace(c.vols); got != c.want {
			t.Errorf("diskFace(%v) = %q, want %q", c.vols, got, c.want)
		}
	}
}

// Four gauges fit beside the raccoon. A fifth volume must page round rather
// than vanish, and every page must still be exactly four rows.
func TestDiskRowsPageThroughEveryVolume(t *testing.T) {
	var vols []volume
	for i := 0; i < 6; i++ {
		vols = append(vols, volume{fmt.Sprintf("/v%d", i), i * 10})
	}
	seen := map[string]bool{}
	for tick := 0; tick < diskPageTicks*4; tick++ {
		rows := diskRows(tick, vols)
		if len(rows) != 4 {
			t.Fatalf("tick %d: %d rows, want 4", tick, len(rows))
		}
		for _, r := range rows {
			if r != "" {
				seen[r] = true
			}
		}
	}
	if len(seen) != len(vols) {
		t.Errorf("showed %d distinct volumes over the cycle, want %d", len(seen), len(vols))
	}
	if got := diskRows(0, nil); len(got) != 4 || got[0] != "" {
		t.Errorf("with no volumes the rows must be four empty strings, got %q", got)
	}
}

// The gauge is ten cells wide whatever the percentage, including out-of-range
// values, so the art beside it can never shift.
func TestDiskGaugeIsAlwaysTenCells(t *testing.T) {
	for _, pct := range []int{-5, 0, 1, 17, 50, 86, 99, 100, 140} {
		g := diskGauge(pct)
		if len(g) != 12 {
			t.Errorf("diskGauge(%d) = %q, width %d, want 12", pct, g, len(g))
		}
	}
}

// Values arrive with their unit attached, and GB must not be read as MB or the
// total would be a thousand times too small and every machine would look spent.
func TestMemMetricReadsUnits(t *testing.T) {
	lines := []string{
		"| Total RAM                 | 16 GB           |",
		"| Wired                     | 2671 MB         |",
		"| Compressed                | 7709 MB         |",
		"| Swap Used                 | 27965.56 MB     |",
		"| Metric                    | Value           |",
	}
	for _, c := range []struct {
		name string
		want float64
	}{
		{"Total RAM", 16384},
		{"Wired", 2671},
		{"Compressed", 7709},
		{"Swap Used", 27965.56},
		{"Nothing", 0},
		{"Metric", 0}, // the header row is not a number
	} {
		if got := memMetric(lines, c.name); got != c.want {
			t.Errorf("memMetric(%q) = %v, want %v", c.name, got, c.want)
		}
	}
}

// Pressure is the worse of macOS's own definition and swap fill: compressed
// alone understates it, and a full swap is a cliff rather than a slope.
func TestMemPressureTakesTheWorseOfTheTwo(t *testing.T) {
	base := []string{
		"| Total RAM                 | 16 GB           |",
		"| Wired                     | 2671 MB         |",
		"| Compressed                | 7709 MB         |",
	}
	// (2671+7709)/16384 = 63%, with no swap information at all.
	if got := memPressure(base); got != 63 {
		t.Errorf("without swap: got %d, want 63", got)
	}
	// This Mac right now: swap at 97% is worse than the 63% and must win.
	withSwap := append(append([]string{}, base...),
		"| Swap Total                | 28672.00 MB     |",
		"| Swap Used                 | 27965.56 MB     |")
	if got := memPressure(withSwap); got != 98 {
		t.Errorf("with swap nearly full: got %d, want 98", got)
	}
	// A machine with swap disabled must not divide by zero.
	noSwap := append(append([]string{}, base...),
		"| Swap Total                | 0.00 MB         |")
	if got := memPressure(noSwap); got != 63 {
		t.Errorf("with swap disabled: got %d, want 63", got)
	}
	if got := memPressure(nil); got != 0 {
		t.Errorf("with no output yet: got %d, want 0", got)
	}
}

// Every band must be reachable and ordered, and the tiredest one must hold the
// most frames still — that repetition is what reads as slowing down.
func TestMemStateFor(t *testing.T) {
	for _, c := range []struct{ pressure, repeat int }{
		{0, 0}, {49, 0}, {50, 1}, {69, 1}, {70, 2}, {89, 2}, {90, 3}, {100, 3}, {150, 3},
	} {
		if got := memStateFor(c.pressure); got.repeat != c.repeat {
			t.Errorf("memStateFor(%d).repeat = %d, want %d", c.pressure, got.repeat, c.repeat)
		}
	}
	if memStateFor(0).load != "" {
		t.Error("a calm raccoon carries nothing")
	}
	if memStateFor(98).eyes != "x.x" || memStateFor(98).muzzle != "v" {
		t.Error("a spent raccoon has shut eyes and an open mouth")
	}
}

// An established connection is not a door anyone can knock on. Reading the two
// states as one would make a busy Mac look wide open.
func TestListenPortsSeparatesListenFromEstablished(t *testing.T) {
	lines := []string{
		"| PORT     | PROTO  | PROCESS              | STATE      |",
		"| -------- | ------ | -------------------- | ---------- |",
		"| 4        | TCP    | rapportd             | ESTABLISHED |",
		"| 7000     | TCP    | ControlCe            | LISTEN     |",
		"| 51542    | TCP    | rapportd             | LISTEN     |",
	}
	got := listenPorts(lines)
	if len(got) != 3 {
		t.Fatalf("got %d ports, want 3: %v", len(got), got)
	}
	if got[0].listening || !got[1].listening || !got[2].listening {
		t.Errorf("LISTEN/ESTABLISHED read wrong: %v", got)
	}
	if got[1].number != "7000" || got[1].process != "ControlCe" {
		t.Errorf("row parsed wrong: %v", got[1])
	}
	if portsFace(got) != "o.o" {
		t.Errorf("two open doors should not alarm the raccoon, got %q", portsFace(got))
	}
}

// The face counts open doors only, and must escalate as they pile up.
func TestPortsFaceCountsOnlyOpenDoors(t *testing.T) {
	mk := func(listening, established int) []port {
		var p []port
		for i := 0; i < listening; i++ {
			p = append(p, port{number: "1", listening: true})
		}
		for i := 0; i < established; i++ {
			p = append(p, port{number: "2"})
		}
		return p
	}
	for _, c := range []struct {
		l, e int
		want string
	}{
		{0, 40, "o.o"}, // forty established connections are not open doors
		{5, 0, "o.o"},
		{6, 0, "-.-"},
		{15, 0, "-.-"},
		{33, 0, ">.<"},
	} {
		if got := portsFace(mk(c.l, c.e)); got != c.want {
			t.Errorf("%d listening, %d established: got %q, want %q", c.l, c.e, got, c.want)
		}
	}
}

// With many ports the round shows the first few and then the count, so the
// cycle stays short enough that a door comes back around.
func TestPortsSlotCapsTheRound(t *testing.T) {
	var many []port
	for i := 0; i < 33; i++ {
		many = append(many, port{number: fmt.Sprint(9000 + i), process: "svc", listening: true})
	}
	cycle := portsMax + 2
	var slots []string
	for tick := 0; tick < cycle; tick++ {
		slots = append(slots, portsSlot(tick, many))
	}
	if len(slots) != cycle {
		t.Fatalf("cycle length %d, want %d", len(slots), cycle)
	}
	if slots[cycle-1] != "" {
		t.Errorf("the round must end on a blank beat, got %q", slots[cycle-1])
	}
	if !strings.Contains(slots[portsMax], "33 in ascolto") {
		t.Errorf("the count beat should report all 33, got %q", slots[portsMax])
	}
	if portsSlot(0, nil) != "" {
		t.Error("with no ports read yet the slot must be empty")
	}
	// Negative ticks must not panic or index out of range.
	_ = portsSlot(-7, many)
}

// "85% (good)" and "691" must both parse: the table mixes bare numbers with
// numbers that carry a verdict after them.
func TestBatteryPercent(t *testing.T) {
	for _, c := range []struct {
		in   string
		want int
	}{
		{"85% (good)", 85}, {"100%", 100}, {"691", 691}, {"", 0}, {"Normal", 0}, {"(good)", 0},
	} {
		if got := batteryPercent(c.in); got != c.want {
			t.Errorf("batteryPercent(%q) = %d, want %d", c.in, got, c.want)
		}
	}
}

// The gauge must show health, and a full charge on a worn pack must still look
// worn — that is the whole reason this command is worth opening.
func TestBatteryReadsHealthNotCharge(t *testing.T) {
	lines := []string{
		"| Cycle Count     | 691                  |",
		"| Max Capacity    | 85% (good)           |",
		"| Charge Level    | 100%                 |",
		"| Charging        | No                   |",
	}
	if got := batteryPercent(batteryRow(lines, "Max Capacity")); got != 85 {
		t.Errorf("health = %d, want 85", got)
	}
	if got := batteryPercent(batteryRow(lines, "Cycle Count")); got != 691 {
		t.Errorf("cycles = %d, want 691", got)
	}
	if got := batteryGauge(85); got != "[#######-]=" {
		t.Errorf("gauge = %q", got)
	}
}

// The face ages on either count: a healthy pack with a thousand cycles behind
// it is still a tired one.
func TestBatteryFaceAgesOnHealthOrCycles(t *testing.T) {
	for _, c := range []struct {
		health, cycles int
		want           string
	}{
		{98, 120, "o.o"},
		{85, 691, "o.o"}, // this Mac: just under both thresholds
		{85, 700, "-.-"}, // cycles alone are enough
		{76, 300, "-.-"}, // health alone is enough
		{62, 1240, "x.x"},
		{0, 0, "o.o"}, // nothing read yet
	} {
		if got := batteryFace(c.health, c.cycles); got != c.want {
			t.Errorf("batteryFace(%d, %d) = %q, want %q", c.health, c.cycles, got, c.want)
		}
	}
}

// The bolt only exists while charging, and never changes the gauge's width.
func TestBatteryBoltOnlyWhenCharging(t *testing.T) {
	for tick := -4; tick < 8; tick++ {
		if got := batteryBolt(tick, false); got != "" {
			t.Errorf("tick %d: not charging but drew %q", tick, got)
		}
	}
	seen := map[string]bool{}
	for tick := 0; tick < 4; tick++ {
		seen[batteryBolt(tick, true)] = true
	}
	if len(seen) != 4 {
		t.Errorf("the bolt cycle should have four distinct beats, got %v", seen)
	}
}

// Time Machine's state decides whether there is anything behind him at all.
func TestReadBackupState(t *testing.T) {
	none := []string{
		"| Destination          | Not configured                 |",
		"| Status               | Idle                           |",
		"| Backup               | No backup found                |",
	}
	if st := readBackupState(none); st.configured || st.hasBackup || st.overdue {
		t.Errorf("an unconfigured Mac read as %+v", st)
	}
	fresh := []string{
		"| Destination          | Time Capsule                   |",
		"| Backup               | 2026-08-28-1400 (3h ago)       |",
	}
	if st := readBackupState(fresh); !st.configured || !st.hasBackup || st.overdue {
		t.Errorf("a fresh backup read as %+v", st)
	}
	late := []string{
		"| Destination          | Time Capsule                   |",
		"| Backup               | 2026-08-01-0100 (72h overdue!) |",
	}
	if st := readBackupState(late); !st.overdue || !st.hasBackup {
		t.Errorf("an overdue backup read as %+v", st)
	}
}

// With no backup the raccoon must stand alone: the empty space behind him is
// the whole message, and a row of copies there would be a lie.
func TestBackupEyesStandAloneWithNoBackup(t *testing.T) {
	for _, st := range []backupState{
		{},
		{configured: true},
		{hasBackup: true},
	} {
		got := backupEyes(0, st)
		if len(got) != 1 || got[0] != "x.x" {
			t.Errorf("state %+v gave %v, want one x.x", st, got)
		}
	}
	// A healthy Mac accumulates copies, capped so the row cannot run off screen.
	for tick := -4; tick < 20; tick++ {
		got := backupEyes(tick, backupState{configured: true, hasBackup: true})
		if len(got) < 1 || len(got) > backupMax {
			t.Errorf("tick %d gave %d raccoons, want 1..%d", tick, len(got), backupMax)
		}
		if got[0] != "^.^" {
			t.Errorf("tick %d: the front raccoon should be pleased, got %q", tick, got[0])
		}
	}
}

// Whoever stands in front must cover the one behind even through the blanks in
// its own face, or the copies show through and the row turns to mush.
func TestBackupRowIsOpaque(t *testing.T) {
	row := backupRow([]string{"o.o", "o.o", "x.x"})
	if len(row) != 4 {
		t.Fatalf("row has %d lines, want 4", len(row))
	}
	if !strings.HasPrefix(row[2], "  [ o.o ]") {
		t.Errorf("the front face is not intact: %q", row[2])
	}
	if strings.Contains(row[2], "[]") {
		t.Errorf("a copy showed through the front raccoon's face: %q", row[2])
	}
	if !strings.Contains(row[2], "x.x") {
		t.Errorf("the broken copy is missing: %q", row[2])
	}
}

// The three tables describe the same keys from different angles, and a key must
// end up wearing the worst thing said about it.
func TestReadSSHKeysKeepsTheWorstFinding(t *testing.T) {
	lines := []string{
		"-- Unprotected Keys",
		"| Key                            | Type            | Status          |",
		"| id_ed25519                     | (ED25519)       | NO PASSPHRASE   |",
		"-- Orphan Keys",
		"| Key                            | Status          |",
		"| None                           | OK              |",
		"-- Key Permissions",
		"| Key                            | Perms      | Status          |",
		"| id_ed25519                     | 600        | OK              |",
	}
	got := readSSHKeys(lines)
	if len(got) != 1 {
		t.Fatalf("got %d keys, want 1: %v", len(got), got)
	}
	// Permissions said OK, but the key still has no passphrase: the worse
	// finding must survive being seen second.
	if got[0].name != "id_ed25519" || got[0].issue != "nopass" {
		t.Errorf("got %v, want id_ed25519/nopass", got[0])
	}
	if sshGlyph(got[0].issue) != "o--" {
		t.Errorf("a key with no passphrase must have no teeth, got %q", sshGlyph(got[0].issue))
	}
	if sshFace(got) != ">.<" {
		t.Errorf("face = %q, want >.<", sshFace(got))
	}
}

// Headers, rules and the "None" placeholder are not keys.
func TestReadSSHKeysIgnoresFurniture(t *testing.T) {
	lines := []string{
		"-- Orphan Keys",
		"| Key                            | Status          |",
		"| ------------------------------ | --------------- |",
		"| None                           | OK              |",
	}
	if got := readSSHKeys(lines); len(got) != 0 {
		t.Errorf("got %v, want no keys", got)
	}
	if sshSlot(0, nil) != "" {
		t.Error("with no keys the slot must be empty")
	}
}

// One good key among many must not calm the face, and the ring must come round.
func TestSSHFaceAndSlotCycle(t *testing.T) {
	keys := []sshKey{{"a", ""}, {"b", ""}, {"c", "nopass"}}
	if got := sshFace(keys); got != ">.<" {
		t.Errorf("face = %q, want >.< while one key is unprotected", got)
	}
	cycle := len(keys) + 1
	var slots []string
	for tick := 0; tick < cycle; tick++ {
		slots = append(slots, sshSlot(tick, keys))
	}
	if slots[cycle-1] != "" {
		t.Errorf("the ring must end on a blank beat, got %q", slots[cycle-1])
	}
	if !strings.Contains(slots[2], "o--") || !strings.Contains(slots[2], "!") {
		t.Errorf("the unprotected key should be marked, got %q", slots[2])
	}
	if strings.Contains(slots[0], "!") {
		t.Errorf("a healthy key must not be marked, got %q", slots[0])
	}
	_ = sshSlot(-3, keys) // negative ticks must not panic
}

// The issues cell packs several counts into one string, and only the number in
// front of the word being asked about may be taken.
func TestGitCount(t *testing.T) {
	const issues = "416 uncommitted, 1 stashed, 4 no upstream"
	if got := gitCount(issues, "uncommitted"); got != 416 {
		t.Errorf("uncommitted = %d, want 416", got)
	}
	if got := gitCount(issues, "stashed"); got != 1 {
		t.Errorf("stashed = %d, want 1", got)
	}
	if got := gitCount(issues, "unpushed"); got != 0 {
		t.Errorf("unpushed = %d, want 0 when the word is absent", got)
	}
	if got := gitCount("detached HEAD, 1 no upstream", "uncommitted"); got != 0 {
		t.Errorf("a cell with no count must give 0, got %d", got)
	}
}

// Reading the real table, capped, skipping the header.
func TestReadRepos(t *testing.T) {
	lines := []string{
		"| Repository                               | Issues               |",
		"| ---------------------------------------- | -------------------- |",
		"| eugeniozamengopontrelli                  | 416 uncommitted, 1 stashed, 4 no upstream |",
		"| MenuSwipe                                | 2 unpushed,          |",
		"| canary                                   | 1 no upstream        |",
	}
	got := readRepos(lines)
	if len(got) != 3 {
		t.Fatalf("got %d repos, want 3: %v", len(got), got)
	}
	if got[0].uncommitted != 416 || got[1].unpushed != 2 {
		t.Errorf("counts read wrong: %v", got)
	}
	// canary has nothing in hand, so it is the one that gets to send a signal.
	if gitSymbols(got[2]) != "" {
		t.Errorf("a repo with nothing pending must draw no symbols, got %q", gitSymbols(got[2]))
	}
	if gitSymbols(got[1]) != "oo  |" {
		t.Errorf("two unpushed commits = %q", gitSymbols(got[1]))
	}
	if gitFace(got) != "x.x" {
		t.Errorf("face = %q, want x.x with 416 pending", gitFace(got))
	}
}

// Nothing may cross the bar: rcc git cannot push, and a symbol arriving would
// claim work was made safe when it was not.
func TestGitSymbolsAreCappedAndNeverCross(t *testing.T) {
	big := repoStatus{name: "home", uncommitted: 416, unpushed: 59}
	got := gitSymbols(big)
	if strings.Count(got, "~") != 4 || strings.Count(got, "o") != 4 {
		t.Errorf("symbols not capped at four each: %q", got)
	}
	if !strings.HasSuffix(got, "|") {
		t.Errorf("the remote bar must stay to the right of everything: %q", got)
	}
}

// The rise is the only motion, it spans the four rows, and it always ends clear.
func TestGitRiseClimbsAndLeaves(t *testing.T) {
	var topsReached, cleared int
	for tick := 0; tick < 4; tick++ {
		rows := gitRise(tick)
		if len(rows) != 4 {
			t.Fatalf("tick %d: %d rows, want 4", tick, len(rows))
		}
		if strings.Contains(rows[0], "o") {
			topsReached++
		}
		if !strings.Contains(strings.Join(rows, ""), "o") {
			cleared++
		}
	}
	if topsReached == 0 {
		t.Error("the signal never reaches the top row")
	}
	if cleared == 0 {
		t.Error("the signal never leaves")
	}
	_ = gitRise(-5) // negative ticks must not panic
}

// "Up 2 hours" is running; anything else is a container still holding its disk.
func TestDockerCounts(t *testing.T) {
	lines := []string{
		"| Container ID | Image        | Status                  |",
		"| ------------ | ------------ | ----------------------- |",
		"| a1b2c3       | postgres:16  | Up 2 hours              |",
		"| d4e5f6       | redis        | Exited (0) 3 days ago   |",
		"| 778899       | node:20      | Up 11 minutes           |",
	}
	running, stopped := dockerCounts(lines)
	if running != 2 || stopped != 1 {
		t.Errorf("got %d running / %d stopped, want 2 / 1", running, stopped)
	}
	if dockerMissing(lines) {
		t.Error("Docker is present in this output")
	}
	if got := dockerFace(false, running, stopped); got != "-.-" {
		t.Errorf("one forgotten container should be noticed, got %q", got)
	}
}

// Docker not being installed is a state of its own, and not a fault.
func TestDockerMissingIsNotAFault(t *testing.T) {
	lines := []string{"| Docker is not installed or not running   |"}
	if !dockerMissing(lines) {
		t.Error("the absence was not recognised")
	}
	if got := dockerFace(true, 0, 0); got != "-.-" {
		t.Errorf("face = %q, want -.- rather than an alarm", got)
	}
	rows := dockerStack(0, 0, 0)
	if strings.TrimSpace(strings.Join(rows, "")) != "" {
		t.Errorf("with nothing to count the pile must be empty, got %q", rows)
	}
}

// The pile grows a box per beat, never outgrows the four lines, and puts the
// running containers underneath the stopped ones.
func TestDockerStackGrowsAndIsCapped(t *testing.T) {
	for tick := -4; tick < 12; tick++ {
		rows := dockerStack(tick, 2, 6)
		if len(rows) != 4 {
			t.Fatalf("tick %d: %d rows, want 4", tick, len(rows))
		}
		if rows[3] != "" {
			t.Errorf("tick %d: the pile must not cover the muzzle line: %q", tick, rows[3])
		}
		boxes := strings.Count(strings.Join(rows, ""), "[")
		if boxes > dockerMax {
			t.Errorf("tick %d: %d boxes, more than the %d that fit", tick, boxes, dockerMax)
		}
	}
	// Full pile: bottom two running, the third one stopped, and the overflow counted.
	full := dockerStack(dockerMax, 2, 6)
	if full[2] != "[o]" || full[1] != "[o]" {
		t.Errorf("running containers should sit at the bottom: %q", full)
	}
	if !strings.HasPrefix(full[0], "[z]") || !strings.Contains(full[0], "+5") {
		t.Errorf("the cap should be a stopped container plus the overflow count: %q", full[0])
	}
}

// du writes the unit into the value. Reading 450M as 450G would bury a clean
// Mac under a mountain that is not there.
func TestDerivedDataGB(t *testing.T) {
	mk := func(v string) []string {
		return []string{
			"| Metric               | Value                |",
			"| Size                 | " + v + "                 |",
			"| Projects             | 1                    |",
		}
	}
	for _, c := range []struct {
		in   string
		want float64
	}{
		{"0B", 0},
		{"512K", 512.0 / 1024 / 1024},
		{"450M", 450.0 / 1024},
		{"12G", 12},
		{"1.5G", 1.5},
		{"2T", 2048},
	} {
		if got := derivedDataGB(mk(c.in)); got != c.want {
			t.Errorf("derivedDataGB(%q) = %v, want %v", c.in, got, c.want)
		}
	}
	// Before the table exists the heap must not be drawn at all.
	if got := derivedDataGB(nil); got != -1 {
		t.Errorf("with no output yet: got %v, want -1", got)
	}
}

// The heap is four rows whatever the size, keeps the ground line even at zero,
// and only grows upward with the cache.
func TestXcodeHeapGrowsFromTheGround(t *testing.T) {
	var lastHeight int
	for _, gb := range []float64{0, 0.4, 3, 12, 40} {
		rows := xcodeHeap(gb)
		if len(rows) != 4 {
			t.Fatalf("%vGB: %d rows, want 4", gb, len(rows))
		}
		if rows[3] == "" {
			t.Errorf("%vGB: the ground line must always be there", gb)
		}
		height := 0
		for _, r := range rows[:3] {
			if r != "" {
				height++
			}
		}
		if height < lastHeight {
			t.Errorf("%vGB: heap shrank from %d to %d", gb, lastHeight, height)
		}
		lastHeight = height
	}
	if xcodeHeap(0)[2] != "" {
		t.Error("an empty cache must leave bare ground")
	}
}

// The face only worries about a cache big enough to be worth clearing.
func TestXcodeFace(t *testing.T) {
	for _, c := range []struct {
		gb   float64
		want string
	}{{0, "o.o"}, {0.9, "o.o"}, {1, "-.-"}, {4.9, "-.-"}, {5, ">.<"}, {19, ">.<"}, {20, "x.x"}, {60, "x.x"}} {
		if got := xcodeFace(c.gb); got != c.want {
			t.Errorf("xcodeFace(%v) = %q, want %q", c.gb, got, c.want)
		}
	}
}

// Order matters in a PATH: what counts is where the holes fall among the good
// entries, so the reader must keep the rows in the order they were printed.
func TestReadPathEntriesKeepsOrder(t *testing.T) {
	lines := []string{
		"-- PATH Entries",
		"| Path                     | Status     |",
		"| ------------------------ | ---------- |",
		"| /opt/homebrew/bin        | OK         |",
		"| /pkg/env/global/bin      | MISSING    |",
		"| /usr/bin                 | OK         |",
		"-- Broken Symlinks",
		"| cagent                   | /Applications/Docker.app/x |",
	}
	got := readPathEntries(lines)
	want := []bool{true, false, true}
	if len(got) != len(want) {
		t.Fatalf("got %d entries, want %d: %v", len(got), len(want), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("entry %d = %v, want %v", i, got[i], want[i])
		}
	}
	// The symlink table that follows must not be mistaken for PATH entries.
	if len(got) != 3 {
		t.Errorf("rows from the next table leaked in: %v", got)
	}
	if envFace(got) != "-.-" {
		t.Errorf("one hole should be noticed, got %q", envFace(got))
	}
}

// A long PATH is paged rather than cut, so every entry is walked eventually,
// and the walker is always somewhere on the trail that is on screen.
func TestEnvTrailPagesThroughEveryEntry(t *testing.T) {
	entries := make([]bool, 20)
	for i := range entries {
		entries[i] = i%7 != 0 // a few holes
	}
	pagesSeen := map[string]bool{}
	for tick := 0; tick < len(entries); tick++ {
		rows := envTrail(tick, entries)
		if len(rows) != 4 {
			t.Fatalf("tick %d: %d rows, want 4", tick, len(rows))
		}
		if !strings.Contains(rows[1], "o") {
			t.Errorf("tick %d: the walker is missing", tick)
		}
		if len(rows[1]) > len(rows[2])+1 {
			t.Errorf("tick %d: the walker stepped off the trail: %q over %q", tick, rows[1], rows[2])
		}
		pagesSeen[rows[2]] = true
	}
	if len(pagesSeen) < 2 {
		t.Errorf("twenty entries should need more than one page, saw %d", len(pagesSeen))
	}
	if got := envTrail(0, nil); strings.TrimSpace(strings.Join(got, "")) != "" {
		t.Errorf("with no PATH read yet the trail must be empty, got %q", got)
	}
	_ = envTrail(-3, entries) // negative ticks must not panic
}

// The five hundred running services are not startup items: folding them in
// would drown the handful of things you actually chose to launch.
func TestCountStartupItemsIgnoresRunningServices(t *testing.T) {
	lines := []string{
		"[1/6] User LaunchAgents...",
		"| ✓ GC.Invoker-1.0                       |  |",
		"| ✓ ccxprocess                           |  |",
		"| Total: 2 items                           |  |",
		"[2/6] System LaunchAgents...",
		"| /Library/LaunchAgents/         | 7          |",
		"[3/6] LaunchDaemons...",
		"| /Library/LaunchDaemons/        | 14         |",
		"[4/6] Login Items...",
		"| ✓ Raycast                              |  |",
		"| ✓ Tailscale                            |  |",
		"[5/6] Running Services...",
		"| Total running services              | 529        |",
		"| com.apple.progressd                 | -          |",
	}
	if got := countStartupItems(lines); got != 25 {
		t.Errorf("got %d items, want 25 (2 + 7 + 14 + 2)", got)
	}
	if got := startupFace(25); got != "-.-" {
		t.Errorf("face = %q, want -.-", got)
	}
	if got := startupFace(31); got != ">.<" {
		t.Errorf("thirty companions should show, got %q", got)
	}
}

// Followers arrive one per beat, never more than fit, and the overflow is
// counted rather than dropped.
func TestStartupTrailGathersAndCounts(t *testing.T) {
	if got := startupTrail(0, 0); got != "" {
		t.Errorf("with nothing at startup the trail must be empty, got %q", got)
	}
	seen := map[int]bool{}
	for tick := -4; tick < 20; tick++ {
		trail := startupTrail(tick, 31)
		dots := strings.Count(trail, ".")
		if dots < 1 || dots > startupShown {
			t.Errorf("tick %d: %d followers, want 1..%d (%q)", tick, dots, startupShown, trail)
		}
		seen[dots] = true
		if dots == startupShown && !strings.Contains(trail, "+23") {
			t.Errorf("tick %d: the overflow was dropped: %q", tick, trail)
		}
	}
	if len(seen) < startupShown {
		t.Errorf("the procession never fills up: saw %v", seen)
	}
	// A small number needs no overflow marker.
	if strings.Contains(startupTrail(3, 4), "+") {
		t.Error("four items must not report an overflow")
	}
}

// The bin fills from the floor up, and is always four rows: a level that grew
// downward or a row that vanished would make the raccoon jump.
func TestTrashBinFillsFromTheFloor(t *testing.T) {
	var lastInk int
	for _, gb := range []float64{0, 0.5, 3, 6, 40} {
		rows := trashBin(0, gb, nil)
		if len(rows) != 4 {
			t.Fatalf("%vGB: %d rows, want 4", gb, len(rows))
		}
		if rows[0] != " .---." || rows[3] != "'---'" {
			t.Errorf("%vGB: the bin lost its rim or its floor: %q", gb, rows)
		}
		ink := strings.Count(strings.Join(rows, ""), ".") + strings.Count(strings.Join(rows, ""), ":")
		if ink < lastInk {
			t.Errorf("%vGB: the level fell from %d to %d", gb, lastInk, ink)
		}
		lastInk = ink
		// Whatever the level, the bottom row is never emptier than the top one.
		bottom := strings.TrimSpace(strings.Trim(rows[2], "|"))
		top := strings.TrimSpace(strings.Trim(rows[1], "|"))
		if len(top) > len(bottom) {
			t.Errorf("%vGB: the bin is filling from the top: top %q, bottom %q", gb, top, bottom)
		}
	}
}

// Six gigabytes in two files is a different problem from six in ten thousand,
// so the names have to come out of the bin.
func TestTrashItemsAndSize(t *testing.T) {
	lines := []string{
		"| Size                 | 6.0G                           |",
		"| Items                | 2 files/folders                |",
		"[3/3] Recent Items (Last 10)...",
		"| Item                                     |",
		"| ---------------------------------------- |",
		"| archivio-littlesnitch-20260828           |",
		"| BarBeR_Dataset.zip                       |",
	}
	if got := trashGB(lines); got != 6 {
		t.Errorf("size = %v, want 6", got)
	}
	items := trashItems(lines)
	if len(items) != 2 || items[1] != "BarBeR_Dataset.zip" {
		t.Errorf("items = %v", items)
	}
	if got := trashFace(6); got != ">.<" {
		t.Errorf("face = %q, want >.<", got)
	}
	// The cycle shows every name and then a beat with none.
	seen := map[string]bool{}
	for tick := 0; tick < len(items)+1; tick++ {
		seen[trashBin(tick, 6, items)[2]] = true
	}
	if len(seen) != len(items)+1 {
		t.Errorf("the cycle showed %d different rows, want %d", len(seen), len(items)+1)
	}
	if got := trashGB(nil); got != -1 {
		t.Errorf("with no output yet: got %v, want -1", got)
	}
}

// "none found" must read as zero, not as a parse failure that silently tires
// him on a clean machine.
func TestFontIssues(t *testing.T) {
	clean := []string{
		"| Duplicates                | none found           |",
		"| Corrupted fonts           | 0                    |",
		"| Total installed           | 812 fonts            |",
	}
	if d, c := fontIssues(clean); d != 0 || c != 0 {
		t.Errorf("clean Mac read as %d duplicates / %d corrupted", d, c)
	}
	if got := fontsFace(0, 0); got != "o.o" {
		t.Errorf("face on a clean collection = %q, want o.o", got)
	}
	messy := []string{
		"| Duplicates                | 12 families          |",
		"| Corrupted fonts           | 0                    |",
	}
	if d, _ := fontIssues(messy); d != 12 {
		t.Errorf("duplicates = %d, want 12", d)
	}
	if got := fontsFace(12, 0); got != ">.<" {
		t.Errorf("face with 12 duplicates = %q, want >.<", got)
	}
	// A corrupted font can take an application down, so it outranks any number
	// of duplicates.
	if got := fontsFace(0, 1); got != "x.x" {
		t.Errorf("face with a corrupted font = %q, want x.x", got)
	}
}

// He only nods off once the duplicates pile up, and never on a clean machine.
func TestFontsPageOnlyDozesWhenDuplicated(t *testing.T) {
	for tick := -6; tick < 24; tick++ {
		if got := fontsPage(tick, 0); got == "zz" {
			t.Fatalf("tick %d: dozed off on a clean collection", tick)
		}
	}
	dozed := false
	seen := map[string]bool{}
	for tick := 0; tick < len(fontSamples); tick++ {
		p := fontsPage(tick, 12)
		seen[p] = true
		if p == "zz" {
			dozed = true
		}
	}
	if !dozed {
		t.Error("with a dozen duplicates he should nod off once a round")
	}
	if len(seen) != len(fontSamples) {
		t.Errorf("the round showed %d pages, want %d", len(seen), len(fontSamples))
	}
	// The book is a fixed size whatever is on the page.
	for _, p := range []string{"Aa", "zz"} {
		rows := fontsBook(p)
		if len(rows) != 4 || len(rows[1]) != len(rows[2]) {
			t.Errorf("the book changed shape on page %q: %q", p, rows)
		}
	}
}

// The scroll carries the commands you really typed; the counts table stays out
// of it, or "Total" would ride past as if it were a command.
func TestRecentCommandsAndTotal(t *testing.T) {
	lines := []string{
		"[1/2] Command Counts...",
		"| Shell      | Commands   |",
		"| zsh        | 1650       |",
		"| Total      | 2195       |",
		"[2/2] Recent Commands...",
		"| Recent Command                      |",
		"| ----------------------------------- |",
		"| claude                              |",
		"| cd                                  |",
		"| clear                               |",
	}
	cmds := recentCommands(lines)
	want := []string{"claude", "cd", "clear"}
	if len(cmds) != len(want) {
		t.Fatalf("got %v, want %v", cmds, want)
	}
	for i := range want {
		if cmds[i] != want[i] {
			t.Errorf("command %d = %q, want %q", i, cmds[i], want[i])
		}
	}
	if got := historyTotal(lines); got != 2195 {
		t.Errorf("total = %d, want 2195", got)
	}
}

// The scroll grows a stretch per beat, closes the round on the total, and never
// runs on forever.
func TestHistoryScrollUnrollsThenRollsUp(t *testing.T) {
	cmds := []string{"claude", "cd", "clear"}
	var lengths []int
	for tick := 0; tick < len(cmds); tick++ {
		s := historyScroll(tick, cmds, 2195)
		if !strings.Contains(s, cmds[tick]) {
			t.Errorf("beat %d should carry %q, got %q", tick, cmds[tick], s)
		}
		lengths = append(lengths, strings.Count(s, "="))
	}
	for i := 1; i < len(lengths); i++ {
		if lengths[i] <= lengths[i-1] {
			t.Errorf("the scroll stopped unrolling: %v", lengths)
		}
	}
	closing := historyScroll(len(cmds), cmds, 2195)
	if !strings.Contains(closing, "2195") {
		t.Errorf("the round should close on the total, got %q", closing)
	}
	if got := historyScroll(0, nil, 0); got != "" {
		t.Errorf("with no commands read yet the scroll must be empty, got %q", got)
	}
	_ = historyScroll(-4, cmds, 2195) // negative ticks must not panic
}

// That step prints an aligned table, not a piped one, so the numbers have to be
// found by shape rather than by column.
func TestCertCounts(t *testing.T) {
	lines := []string{
		"[1/3] User Keychain Certificates...",
		"Total               Valid     Expiring      Expired  Self-Signed",
		"────────────────────────────────────────────────────────────────",
		"42                     26            2           14            8",
	}
	total, valid, expiring, expired := certCounts(lines)
	if total != 42 || valid != 26 || expiring != 2 || expired != 14 {
		t.Errorf("got %d/%d/%d/%d, want 42/26/2/14", total, valid, expiring, expired)
	}
	if got := certFace(total, expired, expiring); got != ">.<" {
		t.Errorf("a third of the wall down should show, got %q", got)
	}
	if got, _, _, _ := certCounts(nil); got != 0 {
		t.Errorf("with no output yet: got %d, want 0", got)
	}
}

// A wall with its holes spread across reads as broken; the same holes gathered
// at one end read as a wall that is merely shorter.
func TestCertWallSpreadsItsGaps(t *testing.T) {
	wall := certWall(42, 26, 2, 14)
	if wall == "" {
		t.Fatal("no wall drawn")
	}
	if len(wall) > certWallWidth {
		t.Errorf("wall is %d wide, more than the %d it may use", len(wall), certWallWidth)
	}
	gaps := strings.Count(wall, " ")
	if gaps == 0 {
		t.Fatalf("fourteen expired certificates left no holes: %q", wall)
	}
	// The holes must not all sit in one half of the wall.
	half := len(wall) / 2
	left := strings.Count(wall[:half], " ")
	if left == 0 || left == gaps {
		t.Errorf("the gaps are all in one half: %q", wall)
	}
	// An intact keychain is an intact wall.
	if got := certWall(10, 10, 0, 0); strings.Contains(got, " ") {
		t.Errorf("nothing expired, yet the wall has holes: %q", got)
	}
	if got := certWall(0, 0, 0, 0); got != "" {
		t.Errorf("with no certificates there is no wall, got %q", got)
	}
}

// "Not connected" is not the name of a network, and the known list must not
// swallow the active one's row.
func TestReadWifi(t *testing.T) {
	lines := []string{
		"Interface: en0",
		"-- Active Connection",
		"| Not connected        |",
		"-- Known Networks",
		"| iPhone               |",
		"| Pontrelli            |",
		"| AIR CHINA            |",
	}
	nets, active := readWifi(lines)
	if active != "" {
		t.Errorf("active = %q, want empty when not connected", active)
	}
	if len(nets) != 3 || nets[2] != "AIR CHINA" {
		t.Errorf("networks = %v", nets)
	}
	joined := []string{
		"-- Active Connection",
		"| Pontrelli            |",
		"-- Known Networks",
		"| Pontrelli            |",
		"| iPhone               |",
	}
	if _, a := readWifi(joined); a != "Pontrelli" {
		t.Errorf("active = %q, want Pontrelli", a)
	}
}

// The field is always four rows, never wider than it was given, and the name is
// set into the waves rather than replacing the row it crosses.
func TestWifiFieldKeepsItsShape(t *testing.T) {
	nets := []string{"Pontrelli", "iPhone", "AIR CHINA"}
	const width = 38
	sawName, sawArcsBothSides := false, false
	for tick := -5; tick < 60; tick++ {
		rows := wifiField(tick, width, nets, "Pontrelli")
		if len(rows) != wifiRows {
			t.Fatalf("tick %d: %d rows, want %d", tick, len(rows), wifiRows)
		}
		for r, row := range rows {
			if len(row) > width {
				t.Errorf("tick %d row %d: %d wide, more than %d", tick, r, len(row), width)
			}
		}
		mid := rows[wifiRows/2]
		for _, n := range nets {
			if strings.Contains(mid, n) {
				sawName = true
				before := mid[:strings.Index(mid, n)]
				after := mid[strings.Index(mid, n)+len(n):]
				if strings.Contains(before, ")") && strings.Contains(after, ")") {
					sawArcsBothSides = true
				}
			}
		}
	}
	if !sawName {
		t.Error("no network name ever crossed the field")
	}
	if !sawArcsBothSides {
		t.Error("the name never had waves on both sides of it")
	}
	// The joined network is marked, and an empty list still gives a moving field.
	found := false
	for tick := 0; tick < 60 && !found; tick++ {
		if strings.Contains(wifiField(tick, width, nets, "Pontrelli")[wifiRows/2], "[Pontrelli]") {
			found = true
		}
	}
	if !found {
		t.Error("the network actually joined was never marked")
	}
	if got := wifiField(0, width, nil, ""); len(got) != wifiRows {
		t.Errorf("with no networks the field must still be %d rows, got %d", wifiRows, len(got))
	}
}

// brew shipping the same file twice changes nothing about what runs; brew and
// the system both providing "openssl" is the case worth drawing.
func TestReadOverlapsKeepsOnlyRealClashes(t *testing.T) {
	lines := []string{
		"| NAME    | PATH                  | RESOLVED           | MANAGER   |",
		"| ------- | --------------------- | ------------------ | --------- |",
		"| jq      | /opt/homebrew/bin/jq  | .../jq-1.7/bin/jq  | brew      |",
		"| jq      | /usr/bin/jq           | /usr/bin/jq        | system    |",
		"| twice   | /opt/homebrew/bin/a   | .../a              | brew      |",
		"| twice   | /opt/homebrew/sbin/a  | .../a              | brew      |",
		"| alone   | /usr/bin/alone        | /usr/bin/alone     | system    |",
		"| pip3    | /opt/homebrew/bin/p   | .../p              | brew      |",
		"| pip3    | /somewhere/p          | /somewhere/p       | orphan    |",
		"| pip3    | /usr/bin/pip3         | /usr/bin/pip3      | system    |",
	}
	got := readOverlaps(lines)
	if len(got) != 2 {
		t.Fatalf("got %d clashes, want 2 (jq, pip3): %v", len(got), got)
	}
	if got[0].name != "jq" || len(got[0].managers) != 2 {
		t.Errorf("jq read as %v", got[0])
	}
	// PATH order decides the winner, so the first manager seen must stay first.
	if got[0].managers[0] != "brew" {
		t.Errorf("the winner should be the first one on the PATH, got %q", got[0].managers[0])
	}
	if got[1].name != "pip3" || len(got[1].managers) != 3 {
		t.Errorf("pip3 read as %v", got[1])
	}
}

// The fork is four rows, marks exactly one winner, and says when a command has
// more places than the two it can show.
func TestOverlapForkMarksOneWinner(t *testing.T) {
	clashes := []clash{
		{"jq", []string{"brew", "system"}},
		{"pip3", []string{"brew", "orphan", "system"}},
	}
	seenExtra := false
	for tick := -6; tick < 24; tick++ {
		rows := overlapFork(tick, clashes)
		if len(rows) != 4 {
			t.Fatalf("tick %d: %d rows, want 4", tick, len(rows))
		}
		if rows[1] == "" || rows[2] == "" || rows[3] == "" {
			t.Errorf("tick %d: the fork is missing a limb: %q", tick, rows)
		}
		if n := strings.Count(strings.Join(rows, ""), "<"); n != 1 {
			t.Errorf("tick %d: %d winners marked, want exactly 1", tick, n)
		}
		if strings.Contains(rows[1], "+1") {
			seenExtra = true
		}
	}
	if !seenExtra {
		t.Error("pip3 has three homes and never said so")
	}
	if got := overlapFork(0, nil); strings.TrimSpace(strings.Join(got, "")) != "" {
		t.Errorf("with no clashes there is no fork, got %q", got)
	}
}

// fleet prints no table: each host is a line starting with an icon, and a
// machine that answered with findings is not the same as one that never did.
func TestReadFleetHosts(t *testing.T) {
	lines := []string{
		"┌────────────────────────────┐",
		"│ Fleet Audit — 2026-08-29   │",
		"  ✓ lampone                          12 pass   2 warn   0 fail",
		"  ⚠ quetzalcoatl-2                    5 pass   3 warn   1 fail",
		"  ✗ oldmini                          UNREACHABLE (TIMEOUT)",
		"  Total: 2/3 hosts reached",
	}
	hosts := readFleetHosts(lines)
	if len(hosts) != 3 {
		t.Fatalf("got %d hosts, want 3: %v", len(hosts), hosts)
	}
	if hosts[0].name != "lampone" || hosts[0].status != 'o' {
		t.Errorf("host 0 = %v", hosts[0])
	}
	if hosts[1].status != '!' {
		t.Errorf("a host that answered with findings must not read as unreachable: %v", hosts[1])
	}
	if hosts[2].status != 'x' {
		t.Errorf("host 2 = %v", hosts[2])
	}
	// An unreachable machine is the finding: it proves nothing about itself.
	if got := fleetFace(hosts); got != ">.<" {
		t.Errorf("face = %q, want >.<", got)
	}
	if got := fleetFace([]fleetHost{{"a", 'o'}, {"b", '!'}}); got != "-.-" {
		t.Errorf("face with findings but all reached = %q, want -.-", got)
	}
	if got := fleetFace([]fleetHost{{"a", 'o'}}); got != "o.o" {
		t.Errorf("face with a clean fleet = %q, want o.o", got)
	}
}

// While he is away his body must be left empty, and every machine — including
// the one that never answered — has to appear as a vision, or the audit would
// look complete when it is not.
func TestFleetVisionLeavesTheBodyEmpty(t *testing.T) {
	hosts := []fleetHost{{"lampone", 'o'}, {"quetzal", '!'}, {"oldmini", 'x'}}
	sawEmpty, sawTrance, sawDead := false, false, false
	faces := map[string]bool{}
	for tick := -6; tick < 24; tick++ {
		eyes, row := fleetVision(tick, hosts)
		switch eyes {
		case " . ":
			sawEmpty = true
			if row == "" {
				t.Errorf("tick %d: he is out of his body but nothing is out there", tick)
			}
		case "@.@":
			sawTrance = true
		}
		if strings.Contains(row, "(x.x)") {
			sawDead = true
		}
		for _, f := range []string{"(o.o)", "(-.-)", "(x.x)"} {
			if strings.Contains(row, f) {
				faces[f] = true
			}
		}
	}
	if !sawEmpty {
		t.Error("his body never emptied: the whole point is that he leaves it")
	}
	if !sawTrance {
		t.Error("he never passes through the trance on the way out or back")
	}
	if !sawDead {
		t.Error("the machine that never answered was left out of the visions")
	}
	if len(faces) != 3 {
		t.Errorf("the visions showed %d different states, want 3", len(faces))
	}
	if e, r := fleetVision(0, nil); e != "" || r != "" {
		t.Errorf("with no hosts read yet there is nothing to show, got %q / %q", e, r)
	}
}

// More machines than fit are counted rather than dropped.
func TestFleetVisionCountsTheOverflow(t *testing.T) {
	var many []fleetHost
	for i := 0; i < 9; i++ {
		many = append(many, fleetHost{fmt.Sprintf("host%d", i), 'o'})
	}
	sawOverflow := false
	for tick := 0; tick < 40; tick++ {
		if _, row := fleetVision(tick, many); strings.Contains(row, "+3") {
			sawOverflow = true
		}
	}
	if !sawOverflow {
		t.Error("nine machines never reported the three that did not fit")
	}
}
