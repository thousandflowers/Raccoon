import { test } from "node:test";
import assert from "node:assert/strict";
import { parseFonts, sourceLabel } from "./fonts-json.ts";

test("sources, totals and the fontconfig block are read", () => {
	const f = parseFonts(
		'{"sources":[{"path":"/Library/Fonts","count":15}],"installed":812,"fontconfig":{"available":true,"fonts":940,"families":940,"duplicate_families":0},"corrupted":2}',
	);
	assert.equal(f.sources[0].count, 15);
	assert.equal(f.installed, 812);
	assert.equal(f.fontconfig.families, 940);
	assert.equal(f.corrupted, 2);
});

test("a Mac without fontconfig says so instead of reporting zero fonts", () => {
	const f = parseFonts(
		'{"sources":[],"installed":0,"fontconfig":{"available":false},"corrupted":0}',
	);
	assert.equal(f.fontconfig.available, false);
	assert.equal(f.fontconfig.fonts, 0);
});

test("the two font directories are told apart by where they live", () => {
	assert.equal(sourceLabel("/Library/Fonts"), "System");
	assert.equal(sourceLabel("/Users/alex/Library/Fonts"), "Yours");
});

test("output that is not JSON says so", () => {
	assert.throws(() => parseFonts("-- Fonts Status"), /did not print JSON/);
});
