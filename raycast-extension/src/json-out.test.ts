import { test } from "node:test";
import assert from "node:assert/strict";
import { expectArray, expectObject, extractJson } from "./json-out.ts";

test("clean JSON is read as it is", () => {
	assert.deepEqual(extractJson('{"a":1}', "x"), { a: 1 });
	assert.deepEqual(extractJson("[1,2]", "x"), [1, 2]);
});

test("a human report in front of the JSON is stepped over", () => {
	// What rcc 0.16.0 prints for memory and for audit.
	assert.deepEqual(extractJson('-- Memory Usage\n| a | b |\n{"a":1}', "x"), {
		a: 1,
	});
	assert.deepEqual(extractJson('+-----+\n| Core |\n[{"a":1}]', "x"), [
		{ a: 1 },
	]);
});

test("a brace inside the report is not the start of the document", () => {
	assert.deepEqual(extractJson('| note: {oops} |\n{"a":1}', "x"), { a: 1 });
});

test("output with no JSON says which rcc would have printed some", () => {
	assert.throws(
		() => extractJson("-- Memory Usage\n| a | b |", "memory"),
		/rcc memory did not print JSON.*brew upgrade rcc/s,
	);
});

test("malformed JSON is not recoverable, and says so the same way", () => {
	// rcc 0.16.0's ports: a process name with a backslash, unescaped.
	assert.throws(
		() => extractJson('[{"process": "back\\slash"}]', "ports"),
		/did not print JSON/,
	);
});

test("empty output is named before anything else", () => {
	assert.throws(() => extractJson("   ", "ports"), /printed nothing/);
});

test("the shape is checked, not assumed", () => {
	assert.throws(() => expectObject("[1]", "x"), /not a report object/);
	assert.throws(() => expectArray("{}", "x"), /not a list/);
});
