import { test } from "node:test";
import assert from "node:assert/strict";
import {
	parseOverlap,
	parseTrash,
	parseWifi,
	shadowed,
	type PathEntry,
} from "./simple-json.ts";

test("trash is read as path, size and count", () => {
	const t = parseTrash(
		'{"path":"/Users/alex/.Trash","size":"11M","count":6}',
	);
	assert.equal(t.count, 6);
	assert.equal(t.size, "11M");
});

test("an empty trash is a report, not a failure", () => {
	const t = parseTrash('{"path":"/Users/alex/.Trash","size":"0","count":0}');
	assert.equal(t.count, 0);
});

test("wifi keeps the networks and tolerates no active one", () => {
	const w = parseWifi(
		'{"interface":"en0","active_ssid":"","known_networks":["Home","Cafe"],"passwords":{}}',
	);
	assert.equal(w.active_ssid, "");
	assert.deepEqual(w.known_networks, ["Home", "Cafe"]);
});

test("a non-string in known_networks is dropped, not rendered", () => {
	const w = parseWifi(
		'{"interface":"en0","active_ssid":"Home","known_networks":["Home",null,7],"passwords":{}}',
	);
	assert.deepEqual(w.known_networks, ["Home"]);
});

test("overlap entries are checked, not cast", () => {
	const list = parseOverlap(
		'[{"name":"jq","path":"/opt/homebrew/bin/jq","resolved":"/opt/homebrew/bin/jq","manager":"brew"}]',
	);
	assert.equal(list[0].manager, "brew");
	assert.throws(
		() => parseOverlap('[{"name":"jq"}]'),
		/Entry 1 is not shaped/,
	);
});

test("a name from two managers is the one worth finding", () => {
	const e = (name: string, manager: string): PathEntry => ({
		name,
		path: `/x/${name}`,
		resolved: `/x/${name}`,
		manager,
	});
	const dupes = shadowed([
		e("jq", "brew"),
		e("jq", "system"),
		e("rg", "brew"),
	]);
	assert.ok(dupes.has("jq"));
	assert.ok(!dupes.has("rg"));
});

test("output that is not JSON says which command failed", () => {
	assert.throws(() => parseTrash("-- Trash"), /rcc trash did not print JSON/);
	assert.throws(() => parseWifi("-- Wi-Fi"), /rcc wifi did not print JSON/);
	assert.throws(() => parseOverlap("[["), /rcc overlap did not print JSON/);
});
