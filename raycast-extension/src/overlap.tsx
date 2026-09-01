import { Color, Icon, List } from "@raycast/api";
import { useMemo } from "react";
import { RccList } from "./rcc-list";
import { parseOverlap, shadowed, type PathEntry } from "./simple-json";

/** One colour per manager would be decorative. Only the clash is coloured. */
function tint(entry: PathEntry, clashing: boolean): Color {
	if (clashing) return Color.Orange;
	return entry.manager === "system" ? Color.SecondaryText : Color.Green;
}

function Rows({
	entries,
	actions,
}: {
	entries: PathEntry[];
	actions: React.ReactNode;
}) {
	// Names provided by two managers first: which copy wins is decided by PATH
	// order, and that is the question this command exists to answer.
	const clashes = useMemo(() => shadowed(entries), [entries]);
	const sorted = useMemo(
		() =>
			[...entries].sort((a, b) => {
				const rank = (e: PathEntry) => (clashes.has(e.name) ? 0 : 1);
				return rank(a) - rank(b) || a.name.localeCompare(b.name);
			}),
		[entries, clashes],
	);
	return (
		<>
			{sorted.map((entry, index) => {
				const clashing = clashes.has(entry.name);
				return (
					<List.Item
						key={`${entry.name}-${entry.path}-${index}`}
						icon={{
							source: clashing ? Icon.Duplicate : Icon.Terminal,
							tintColor: tint(entry, clashing),
						}}
						title={entry.name}
						subtitle={entry.path}
						keywords={[entry.manager, entry.resolved]}
						accessories={[
							{
								tag: {
									value: entry.manager,
									color: tint(entry, clashing),
								},
							},
						]}
						actions={actions}
					/>
				);
			})}
		</>
	);
}

export default function Command() {
	return (
		<RccList
			command="overlap"
			parse={parseOverlap}
			navigationTitle={(e) =>
				e
					? `PATH — ${e.length} entries, ${shadowed(e).size} shadowed`
					: "PATH"
			}
			searchBarPlaceholder="Search by name, manager or path"
			emptyIcon={Icon.Terminal}
			emptyTitle="Nothing on the PATH"
		>
			{(entries, actions) => <Rows entries={entries} actions={actions} />}
		</RccList>
	);
}
