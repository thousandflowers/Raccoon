import { execFile, spawn } from "node:child_process";
import { accessSync, constants } from "node:fs";
import { homedir } from "node:os";
import { promisify } from "node:util";
import { getPreferenceValues } from "@raycast/api";

const execFileAsync = promisify(execFile);

/** Where rcc itself may be installed. Raycast does not inherit a login shell PATH. */
const RCC_SEARCH_PATHS = [
	"/opt/homebrew/bin",
	"/usr/local/bin",
	`${homedir()}/.local/bin`,
];

/**
 * PATH handed to rcc. The system directories are not optional: rcc's checks call
 * system_profiler, diskutil, lsof, networksetup and ifconfig, which live in
 * /usr/sbin and /sbin. Without them rcc silently reports zeroes.
 */
const RUNTIME_PATH = [
	...RCC_SEARCH_PATHS,
	"/usr/bin",
	"/bin",
	"/usr/sbin",
	"/sbin",
].join(":");

export const INSTALL_COMMAND = "brew install thousandflowers/raccoon/rcc";

export class RccNotFoundError extends Error {
	constructor() {
		super("rcc not found");
		this.name = "RccNotFoundError";
	}
}

function isExecutable(path: string): boolean {
	try {
		accessSync(path, constants.X_OK);
		return true;
	} catch {
		return false;
	}
}

/** Resolve the rcc binary: user preference first, then the usual install dirs. */
export function resolveRcc(): string {
	const { rccPath } = getPreferenceValues<{ rccPath?: string }>();
	const candidates = [
		rccPath,
		...RCC_SEARCH_PATHS.map((dir) => `${dir}/rcc`),
	];
	for (const candidate of candidates) {
		if (candidate && isExecutable(candidate)) return candidate;
	}
	throw new RccNotFoundError();
}

/**
 * Stream a command's combined stdout/stderr, calling `onData` as it arrives.
 *
 * Streaming rather than buffering is what lets the privileged commands run
 * inside Raycast: `rcc upgrade` and `rcc audit --deep` take minutes and print
 * progress the whole way, and rcc raises its own Touch ID dialog for sudo
 * (pam_tid needs no controlling terminal), so nothing has to leave Raycast.
 *
 * Resolves with the exit code. A non-zero code is not an error here — `rcc
 * audit` exits non-zero when checks fail but still prints the full report.
 */
function stream(
	file: string,
	args: string[],
	onData: (chunk: string) => void,
	signal?: AbortSignal,
): Promise<number> {
	return new Promise((resolve, reject) => {
		const child = spawn(file, args, {
			env: { ...process.env, NO_COLOR: "1", PATH: RUNTIME_PATH },
			stdio: ["ignore", "pipe", "pipe"],
		});

		const abort = () => child.kill("SIGTERM");
		signal?.addEventListener("abort", abort, { once: true });

		child.stdout.on("data", (chunk: Buffer) => onData(chunk.toString()));
		child.stderr.on("data", (chunk: Buffer) => onData(chunk.toString()));
		child.on("error", (error) => {
			signal?.removeEventListener("abort", abort);
			reject(error);
		});
		child.on("close", (code) => {
			signal?.removeEventListener("abort", abort);
			resolve(code ?? 0);
		});
	});
}

/** Stream `rcc <args>`. */
export async function streamRcc(
	args: string[],
	onData: (chunk: string) => void,
	signal?: AbortSignal,
): Promise<number> {
	return stream(resolveRcc(), args, onData, signal);
}

/** Stream the Homebrew install of rcc, for the first-run setup screen. */
export async function streamInstall(
	onData: (chunk: string) => void,
	signal?: AbortSignal,
): Promise<number> {
	return stream("/bin/sh", ["-lc", INSTALL_COMMAND], onData, signal);
}

/** Run `rcc <args>` and return its stdout in one go (for short, scripted uses). */
export async function runRcc(args: string[]): Promise<string> {
	const { stdout } = await execFileAsync(resolveRcc(), args, {
		env: { ...process.env, NO_COLOR: "1", PATH: RUNTIME_PATH },
		maxBuffer: 10 * 1024 * 1024,
	});
	return stdout;
}
