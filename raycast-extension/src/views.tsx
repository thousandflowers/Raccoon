import type { ReactElement } from "react";
import Audit from "./audit";
import Battery from "./battery";
import Memory from "./memory";
import Certs from "./certs";
import Docker from "./docker";
import History from "./history";
import Overlap from "./overlap";
import Ports from "./ports";
import Trash from "./trash";
import Wifi from "./wifi";
import type { RccCommand } from "./commands";
import { RccDetail } from "./rcc-detail";

/**
 * The purpose-built screen for a command, where one exists.
 *
 * Without this the launcher opened every command with RccDetail, so the four
 * rewritten views were reachable only as their own Raycast commands and
 * choosing Battery from the list still showed rcc's table. One index, so a new
 * view is wired in one place.
 */
const VIEWS: Record<string, () => ReactElement> = {
	audit: Audit,
	battery: Battery,
	memory: Memory,
	ports: Ports,
	trash: Trash,
	wifi: Wifi,
	overlap: Overlap,
	docker: Docker,
	history: History,
	certs: Certs,
};

/** Whether this command has a screen of its own rather than raw output. */
export function hasView(command: RccCommand): boolean {
	return command.args.length === 1 && command.args[0] in VIEWS;
}

export function viewFor(command: RccCommand): ReactElement {
	if (hasView(command)) {
		const View = VIEWS[command.args[0]];
		return <View />;
	}
	return <RccDetail command={command} />;
}
