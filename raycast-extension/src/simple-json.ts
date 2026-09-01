/**
 * Small readers for the commands whose --json is a shape of its own.
 *
 * Each one checks rather than casts: a missing field must be named here, not
 * rendered as "undefined" three screens later.
 */

function object(stdout: string, command: string): Record<string, unknown> {
	const text = stdout.trim();
	if (text === "")
		throw new Error(`rcc ${command} printed nothing to parse.`);
	let parsed: unknown;
	try {
		parsed = JSON.parse(text);
	} catch (error) {
		const reason = error instanceof Error ? error.message : String(error);
		throw new Error(`rcc ${command} did not print JSON: ${reason}`);
	}
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

export type TrashReport = { path: string; size: string; count: number };

export function parseTrash(stdout: string): TrashReport {
	const r = object(stdout, "trash");
	return {
		path: typeof r.path === "string" ? r.path : "",
		size: typeof r.size === "string" ? r.size : "0",
		count: typeof r.count === "number" ? r.count : 0,
	};
}

export type WifiReport = {
	interface: string;
	active_ssid: string;
	known_networks: string[];
	passwords: Record<string, string>;
};

export function parseWifi(stdout: string): WifiReport {
	const r = object(stdout, "wifi");
	return {
		interface: typeof r.interface === "string" ? r.interface : "",
		active_ssid: typeof r.active_ssid === "string" ? r.active_ssid : "",
		known_networks: Array.isArray(r.known_networks)
			? r.known_networks.filter((n): n is string => typeof n === "string")
			: [],
		passwords:
			typeof r.passwords === "object" && r.passwords !== null
				? (r.passwords as Record<string, string>)
				: {},
	};
}

export type PathEntry = {
	name: string;
	path: string;
	resolved: string;
	manager: string;
};

export function parseOverlap(stdout: string): PathEntry[] {
	const text = stdout.trim();
	if (text === "") throw new Error("rcc overlap printed nothing to parse.");
	let parsed: unknown;
	try {
		parsed = JSON.parse(text);
	} catch (error) {
		const reason = error instanceof Error ? error.message : String(error);
		throw new Error(`rcc overlap did not print JSON: ${reason}`);
	}
	if (!Array.isArray(parsed)) {
		throw new Error("rcc overlap printed JSON, but not a list of entries.");
	}
	return parsed.map((value, index) => {
		const e = value as Record<string, unknown>;
		if (typeof e?.name !== "string" || typeof e?.manager !== "string") {
			throw new Error(
				`Entry ${index + 1} is not shaped like a PATH entry.`,
			);
		}
		return {
			name: e.name,
			path: typeof e.path === "string" ? e.path : "",
			resolved: typeof e.resolved === "string" ? e.resolved : "",
			manager: e.manager,
		};
	});
}

/**
 * A name provided by more than one manager: the reason this command exists.
 * Which copy wins is decided by PATH order, and the reader wants those first.
 */
export function shadowed(entries: PathEntry[]): Set<string> {
	const seen = new Map<string, number>();
	for (const entry of entries) {
		seen.set(entry.name, (seen.get(entry.name) ?? 0) + 1);
	}
	return new Set(
		[...seen.entries()].filter(([, n]) => n > 1).map(([name]) => name),
	);
}
