import { appendFile, mkdir, readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

/**
 * The per-machine opt-out list `rcc audit` reads: one check name per line, `#`
 * for comments, matched whole-line and literally (`grep -Fxq`, bin/audit.sh).
 * The name in the report is the key, verified against every name that reaches
 * fix_issue.
 */
export const AUDIT_CONF = join(homedir(), ".raccoon", "audit.conf");

const HEADER = [
	"# Checks rcc audit will never offer to fix on this machine.",
	"# One name per line, exactly as the report spells it. # starts a comment.",
	"",
].join("\n");

export type SkipOutcome = "added" | "already-listed";

/**
 * Whether NAME is already opted out, read the way audit.sh reads it: comment and
 * blank lines are dropped, and what remains has to equal the name exactly —
 * `grep -Fxq` matches a whole line, so " Firewall" is not "Firewall".
 */
export function isListed(contents: string, name: string): boolean {
	return contents.split("\n").some((line) => {
		const trimmed = line.trim();
		if (trimmed === "" || trimmed.startsWith("#")) return false;
		return line === name;
	});
}

/**
 * Add NAME to the opt-out list.
 *
 * Appends; never rewrites. The file belongs to whoever wrote it, and rewriting
 * it to insert one line would cost them their comments and their order. A name
 * already there is reported back rather than written twice, because a duplicate
 * line changes nothing and looks like the action failed to take. A file that is
 * not there is created, with two lines saying what it is — a lone word in a
 * lone file explains nothing six months later. Anything else (a directory that
 * cannot be created, a file that cannot be written) is thrown with the reason
 * the filesystem gave, because "could not skip the check" on its own is useless.
 */
export async function skipCheck(
	name: string,
	path: string = AUDIT_CONF,
): Promise<SkipOutcome> {
	if (name === "" || name.includes("\n")) {
		throw new Error(`Not a check name: ${JSON.stringify(name)}`);
	}

	let contents: string | undefined;
	try {
		contents = await readFile(path, "utf8");
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
	}

	if (contents !== undefined && isListed(contents, name))
		return "already-listed";

	// A file that does not end in a newline would otherwise glue the new name to
	// whatever the last line was, and a whole-line match would never find either.
	const separator =
		contents !== undefined && contents !== "" && !contents.endsWith("\n")
			? "\n"
			: "";
	const preamble = contents === undefined ? HEADER : "";

	await mkdir(dirname(path), { recursive: true });
	await appendFile(path, `${separator}${preamble}${name}\n`, { mode: 0o644 });
	return "added";
}
