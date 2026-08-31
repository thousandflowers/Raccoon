import {
	Action,
	ActionPanel,
	Alert,
	confirmAlert,
	Detail,
	Icon,
	Keyboard,
	openExtensionPreferences,
} from "@raycast/api";
import { useState } from "react";
import type { RccCommand } from "./commands";
import { pendingFixCount, toMarkdown, withSudoHint } from "./markdown";
import { isFailure } from "./exit";
import { INSTALL_COMMAND, RccNotFoundError, streamInstall } from "./rcc";
import { useRccStream } from "./use-rcc-stream";

const REPO_URL = "https://github.com/thousandflowers/Raccoon";

/** First run without the CLI: install it from here rather than sending the user to a terminal. */
function MissingRcc() {
	const [log, setLog] = useState("");
	const [isInstalling, setIsInstalling] = useState(false);

	const install = async () => {
		setIsInstalling(true);
		setLog("");
		try {
			await streamInstall((chunk) =>
				setLog((previous) => previous + chunk.text),
			);
		} finally {
			setIsInstalling(false);
		}
	};

	const markdown = [
		"# Raccoon CLI not found",
		"",
		"This extension runs the `rcc` command-line tool.",
		"",
		"Press **Install with Homebrew** below, or set the path in preferences if it is already installed elsewhere.",
		"",
		log ? ["## Installing", "", "```", log, "```"].join("\n") : "",
	].join("\n");

	return (
		<Detail
			isLoading={isInstalling}
			markdown={markdown}
			actions={
				<ActionPanel>
					<Action
						title="Install with Homebrew"
						icon={Icon.Download}
						onAction={install}
					/>
					<Action
						title="Set Rcc Path"
						icon={Icon.Gear}
						onAction={openExtensionPreferences}
					/>
					<Action.CopyToClipboard
						title="Copy Install Command"
						content={INSTALL_COMMAND}
					/>
					<Action.OpenInBrowser
						title="Open Raccoon on GitHub"
						url={REPO_URL}
					/>
				</ActionPanel>
			}
		/>
	);
}

/** What to say about a run that ended badly, with whatever stderr explained. */
function failureNotice(
	args: string[],
	code: number,
	stderrOutput: string,
): string[] {
	const reason = stderrOutput.trim();
	return [
		`> **\`rcc ${args.join(" ")}\` exited with status ${code}.**`,
		"> The output above may be incomplete.",
		...(reason ? ["", "```", reason, "```"] : []),
	];
}

export function RccDetail({ command }: { command: RccCommand }) {
	const [args, setArgs] = useState(command.args);
	const {
		output,
		stdoutOutput,
		stderrOutput,
		exit,
		isLoading,
		error,
		reload,
		stop,
	} = useRccStream(args);

	if (error instanceof RccNotFoundError) return <MissingRcc />;

	// Three states, not two: a command that ends without printing anything used
	// to leave "Running" on the screen for good.
	let markdown: string;
	if (error) {
		markdown = [
			`## ${command.title} failed`,
			"",
			"```",
			error.message,
			"```",
		].join("\n");
	} else if (output) {
		markdown = withSudoHint(toMarkdown(output));
	} else if (isLoading) {
		markdown = `Running \`rcc ${args.join(" ")}\``;
	} else {
		markdown = `\`rcc ${args.join(" ")}\` finished without printing anything.`;
	}

	// rcc audit says what it found through its exit status, so a non-zero code is
	// not news by itself. Anything isFailure() does call a failure is reported
	// here, because the output alone can look like an ordinary short report.
	if (exit && isFailure(args, exit, stdoutOutput.trim() !== "")) {
		markdown += [
			"",
			"",
			"---",
			"",
			...failureNotice(args, exit.code, stderrOutput),
		].join("\n");
	}

	// rcc offers its fixes through a terminal prompt that Raycast cannot answer,
	// so the offer is re-made here as an explicit, confirmed action.
	const fixes = command.args[0] === "audit" ? pendingFixCount(output) : 0;
	const applyFixes = async () => {
		const confirmed = await confirmAlert({
			title: `Apply ${fixes} automatic ${fixes === 1 ? "fix" : "fixes"}?`,
			message:
				"Raccoon will change system security settings. Review the report first.",
			primaryAction: {
				title: "Apply Fixes",
				style: Alert.ActionStyle.Destructive,
			},
		});
		if (!confirmed) return;
		setArgs(["audit", "--fix", "--force"]);
	};

	return (
		<Detail
			isLoading={isLoading}
			navigationTitle={command.title}
			markdown={markdown}
			actions={
				<ActionPanel>
					{isLoading ? (
						<Action title="Stop" icon={Icon.Stop} onAction={stop} />
					) : (
						<Action
							title="Run Again"
							icon={Icon.ArrowClockwise}
							shortcut={Keyboard.Shortcut.Common.Refresh}
							onAction={reload}
						/>
					)}
					{fixes > 0 && !isLoading && (
						<Action
							title={`Fix ${fixes} Issues Automatically`}
							icon={Icon.Hammer}
							onAction={applyFixes}
						/>
					)}
					<Action.CopyToClipboard
						title="Copy Output"
						content={output}
						shortcut={{ modifiers: ["cmd"], key: "c" }}
					/>
					<Action
						title="Set Rcc Path"
						icon={Icon.Gear}
						onAction={openExtensionPreferences}
					/>
					<Action.OpenInBrowser
						title="Open Raccoon on GitHub"
						url={REPO_URL}
					/>
				</ActionPanel>
			}
		/>
	);
}
