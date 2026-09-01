/**
 * Reading `--json` from whatever rcc the reader has installed.
 *
 * Two things go wrong with an older CLI, and they are not the same:
 *
 * - Before 0.17.0, `audit` and `memory` printed their human report first and
 *   glued the JSON to the end of the same stdout. That is recoverable: the
 *   document is there, with something in front of it.
 * - Before 0.17.0, `ports --json` emitted invalid JSON, because process names
 *   carrying a backslash were not escaped. That is not recoverable, and saying
 *   "upgrade" is the only honest answer.
 *
 * The extension is installed against whatever binary is on the machine, so it
 * reads what it can and names the version when it cannot.
 */

const UPGRADE =
	"An rcc older than 0.17.0 prints its report before the JSON, and its ports " +
	"output is not valid JSON at all. Upgrade with `brew upgrade rcc`, or point " +
	"the Raccoon CLI preference at a newer binary.";

/**
 * The JSON document in a stdout that may begin with something else.
 *
 * Only a brace or a bracket at the start of a line is considered, so one
 * inside the report's own text cannot be mistaken for the start of it.
 */
export function extractJson(stdout: string, command: string): unknown {
	const text = stdout.trim();
	if (text === "") {
		throw new Error(`rcc ${command} printed nothing to parse.`);
	}
	try {
		return JSON.parse(text);
	} catch (first) {
		const lines = text.split("\n");
		for (let i = 0; i < lines.length; i += 1) {
			const start = lines[i];
			if (!start.startsWith("{") && !start.startsWith("[")) continue;
			try {
				return JSON.parse(lines.slice(i).join("\n"));
			} catch {
				// Not the start of the document: keep looking further down.
			}
		}
		const reason = first instanceof Error ? first.message : String(first);
		throw new Error(
			`rcc ${command} did not print JSON: ${reason}. ${UPGRADE}`,
		);
	}
}

export function expectObject(
	stdout: string,
	command: string,
): Record<string, unknown> {
	const parsed = extractJson(stdout, command);
	if (
		typeof parsed !== "object" ||
		parsed === null ||
		Array.isArray(parsed)
	) {
		throw new Error(
			`rcc ${command} printed JSON, but not a report object.`,
		);
	}
	return parsed as Record<string, unknown>;
}

export function expectArray(stdout: string, command: string): unknown[] {
	const parsed = extractJson(stdout, command);
	if (!Array.isArray(parsed)) {
		throw new Error(`rcc ${command} printed JSON, but not a list.`);
	}
	return parsed;
}
