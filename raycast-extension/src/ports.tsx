import {
	Action,
	ActionPanel,
	Color,
	Icon,
	Keyboard,
	List,
	openExtensionPreferences,
	useNavigation,
} from "@raycast/api";
import { useExec } from "@raycast/utils";
import { useMemo } from "react";
import { findCommand } from "./commands";
import { MissingRcc, REPO_URL } from "./missing-rcc";
import {
	type Exposure,
	type Port,
	byInterest,
	exposure,
	parsePorts,
} from "./ports-json";
import { RccDetail } from "./rcc-detail";
import { RccNotFoundError, resolveRcc, RUNTIME_PATH } from "./rcc";

const TINT: Record<Exposure, Color> = {
	exposed: Color.Orange,
	local: Color.Green,
	idle: Color.SecondaryText,
};

const ICON: Record<Exposure, Icon> = {
	exposed: Icon.Globe,
	local: Icon.House,
	idle: Icon.Circle,
};

const LABEL: Record<Exposure, string> = {
	exposed: "Reachable",
	local: "This Mac only",
	idle: "Not bound",
};

export default function Command() {
	const { push } = useNavigation();

	let rccPath: string | null = null;
	let resolveError: unknown;
	try {
		rccPath = resolveRcc();
	} catch (error) {
		resolveError = error;
	}

	const { isLoading, data, error, revalidate } = useExec(
		rccPath ?? "rcc",
		["ports", "--json"],
		{
			execute: rccPath !== null,
			env: { ...process.env, NO_COLOR: "1", PATH: RUNTIME_PATH },
			parseOutput: ({ stdout }) => parsePorts(stdout),
		},
	);

	// Reachable first: an open door matters more than a conversation in progress.
	const ports = useMemo(() => [...(data ?? [])].sort(byInterest), [data]);
	const reachable = ports.filter((p) => exposure(p) === "exposed").length;

	if (resolveError instanceof RccNotFoundError) return <MissingRcc />;

	const actions = (port: Port | null) => (
		<ActionPanel>
			{port ? (
				<>
					<Action.CopyToClipboard
						title="Copy Port"
						content={port.port}
						shortcut={Keyboard.Shortcut.Common.Copy}
					/>
					<Action.CopyToClipboard
						title="Copy Address"
						content={port.address}
					/>
					{port.pid !== null ? (
						<Action.CopyToClipboard
							title="Copy PID"
							content={String(port.pid)}
						/>
					) : null}
				</>
			) : null}
			<Action
				title="Run Again"
				icon={Icon.ArrowClockwise}
				shortcut={Keyboard.Shortcut.Common.Refresh}
				onAction={revalidate}
			/>
			<Action
				title="Show Raw Output"
				icon={Icon.Text}
				shortcut={{ modifiers: ["cmd"], key: "t" }}
				onAction={() =>
					push(<RccDetail command={findCommand("ports")} />)
				}
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
	);

	if (error) {
		return (
			<List>
				<List.EmptyView
					icon={{ source: Icon.XMarkCircle, tintColor: Color.Red }}
					title="The port list could not be read"
					description={error.message}
					actions={actions(null)}
				/>
			</List>
		);
	}

	return (
		<List
			isLoading={isLoading}
			navigationTitle={
				ports.length > 0
					? `Ports — ${ports.length} open, ${reachable} reachable`
					: "Ports"
			}
			searchBarPlaceholder="Search by port, process or address"
		>
			<List.EmptyView
				icon={{ source: Icon.Plug, tintColor: Color.SecondaryText }}
				title={isLoading ? "Reading open ports" : "No ports open"}
				actions={actions(null)}
			/>
			{ports.map((port, index) => {
				const e = exposure(port);
				return (
					<List.Item
						key={`${port.port}-${port.proto}-${port.pid}-${index}`}
						icon={{ source: ICON[e], tintColor: TINT[e] }}
						title={port.port === "*" ? "unbound" : port.port}
						subtitle={port.process}
						keywords={[
							port.address,
							port.proto,
							port.state,
							port.user,
						].filter(Boolean)}
						accessories={[
							port.state ? { text: port.state } : {},
							{ tag: { value: LABEL[e], color: TINT[e] } },
						]}
						actions={actions(port)}
					/>
				);
			})}
		</List>
	);
}
