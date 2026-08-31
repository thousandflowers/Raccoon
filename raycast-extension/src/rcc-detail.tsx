import {
	Action,
	ActionPanel,
	Alert,
	confirmAlert,
	Detail,
	Icon,
	openExtensionPreferences,
} from "@raycast/api";
import { useState } from "react";
import type { RccCommand } from "./commands";
import { pendingFixCount, toMarkdown, withSudoHint } from "./markdown";
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
				setLog((previous) => previous + chunk),
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

export function RccDetail({ command }: { command: RccCommand }) {
	const [args, setArgs] = useState(command.args);
	const { output, isLoading, error, reload, stop } = useRccStream(args);

	if (error instanceof RccNotFoundError) return <MissingRcc />;

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
	} else {
		markdown = `Running \`rcc ${args.join(" ")}\``;
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
