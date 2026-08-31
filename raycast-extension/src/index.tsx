import { Action, ActionPanel, Icon, List } from "@raycast/api";
import { COMMANDS, type RccCommand } from "./commands";
import { RccDetail } from "./rcc-detail";

function accessories(command: RccCommand): List.Item.Accessory[] {
	const items: List.Item.Accessory[] = [];
	// Privileged commands still run inside Raycast: rcc raises its own Touch ID
	// dialog. Flag them so the prompt is not a surprise.
	if (command.needsRoot) {
		items.push({
			icon: Icon.Fingerprint,
			tooltip: "Asks for admin rights via Touch ID",
		});
	}
	items.push({ tag: `rcc ${command.args.join(" ")}` });
	return items;
}

export default function Command() {
	return (
		<List searchBarPlaceholder="Search Raccoon commands">
			{COMMANDS.map((command) => (
				<List.Item
					key={command.id}
					icon={Icon.Window}
					title={command.title}
					subtitle={command.description}
					accessories={accessories(command)}
					actions={
						<ActionPanel>
							<Action.Push
								title="Show Output"
								icon={Icon.Window}
								target={<RccDetail command={command} />}
							/>
							<Action.CopyToClipboard
								title="Copy Command"
								content={`rcc ${command.args.join(" ")}`}
							/>
						</ActionPanel>
					}
				/>
			))}
		</List>
	);
}
