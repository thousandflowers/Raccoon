import { Color, Icon, List } from "@raycast/api";
import { openApp, openSettings, reveal, SETTINGS } from "./fixes";
import { RccList } from "./rcc-list";
import { RowActions } from "./resolve";
import { fillLevel, parseDisk, smartLevel, type DiskReport } from "./disk-json";

const FILL_TINT = {
	ok: Color.Green,
	tight: Color.Orange,
	full: Color.Red,
} as const;

const SMART_TINT = {
	ok: Color.Green,
	failing: Color.Red,
	unknown: Color.SecondaryText,
} as const;

function Rows({ d, actions }: { d: DiskReport; actions: React.ReactNode }) {
	// Nothing here deletes anything: which files go is a decision, and macOS
	// already has the one screen that shows what is taking the room. So Enter
	// opens the volume where the reader can look, and Cmd+Enter opens Storage
	// settings, which is the honest bulk answer to "the disk is full".
	const storage = {
		title: "Open Storage Settings",
		command: openSettings(SETTINGS.storage),
		detail: "Shows what is taking the room, by category.",
		count: 1,
	};
	return (
		<>
			{/* The only question anyone opens this for. */}
			<List.Section title="Volumes" subtitle={`${d.volumes.length}`}>
				{d.volumes.map((v) => {
					const level = fillLevel(v.percent);
					return (
						<List.Item
							key={v.mount}
							icon={{
								source: Icon.HardDrive,
								tintColor: FILL_TINT[level],
							}}
							title={v.name}
							subtitle={v.mount}
							accessories={[
								{ text: `${v.free} free` },
								{
									tag: {
										value: v.percent,
										color: FILL_TINT[level],
									},
								},
							]}
							actions={
								<RowActions
									one={{
										title: "Open This Volume",
										command: reveal(v.mount),
										detail: `${v.free} free of what is mounted at ${v.mount}.`,
									}}
									all={storage}
									shared={actions}
								/>
							}
						/>
					);
				})}
			</List.Section>

			<List.Section title="Disks" subtitle={`${d.disks.length}`}>
				{d.disks.map((disk) => {
					const level = smartLevel(disk.smart);
					return (
						<List.Item
							key={disk.id}
							icon={{
								source: Icon.Cd,
								tintColor: SMART_TINT[level],
							}}
							title={disk.id}
							subtitle={[disk.type, disk.size]
								.filter(Boolean)
								.join(" · ")}
							accessories={[
								...(disk.mount ? [{ text: disk.mount }] : []),
								{
									tag: {
										value: disk.smart,
										color: SMART_TINT[level],
									},
								},
							]}
							actions={
								<RowActions
									one={{
										title: "Open Disk Utility",
										command: openApp("Disk Utility"),
										detail: "SMART status and partitions are shown there.",
									}}
									all={storage}
									shared={actions}
								/>
							}
						/>
					);
				})}
			</List.Section>

			{d.apfs_container.reference ? (
				<List.Section title="APFS container">
					<List.Item
						icon={{
							source: Icon.Box,
							tintColor: Color.SecondaryText,
						}}
						title={d.apfs_container.reference}
						subtitle={
							// APFS volumes share the container's free space, which is why
							// two volumes both report the same number.
							"Volumes in this container share its free space"
						}
						accessories={[
							{ text: d.apfs_container.size },
							{ tag: { value: `${d.apfs_container.free} free` } },
						]}
						actions={<RowActions all={storage} shared={actions} />}
					/>
				</List.Section>
			) : null}

			{d.network_mounts.length > 0 ? (
				<List.Section
					title="Network mounts"
					subtitle={`${d.network_mounts.length}`}
				>
					{d.network_mounts.map((n) => (
						<List.Item
							key={n.mount}
							icon={{
								source: Icon.Globe,
								tintColor: Color.SecondaryText,
							}}
							title={n.mount}
							subtitle={n.source}
							actions={
								<RowActions
									one={{
										title: "Open This Mount",
										command: reveal(n.mount),
									}}
									all={storage}
									shared={actions}
								/>
							}
						/>
					))}
				</List.Section>
			) : null}
		</>
	);
}

export default function Command() {
	return (
		<RccList
			command="disk"
			parse={parseDisk}
			navigationTitle={(d) => {
				if (!d || d.volumes.length === 0) return "Disk";
				const worst = d.volumes.reduce((a, b) =>
					fillLevel(a.percent) === "full" ? a : b,
				);
				return `Disk — ${worst.name} at ${worst.percent}, ${worst.free} free`;
			}}
			searchBarPlaceholder="Search volumes, disks and mounts"
			emptyIcon={Icon.HardDrive}
			emptyTitle="No disks reported"
		>
			{(d, actions) => <Rows d={d} actions={actions} />}
		</RccList>
	);
}
