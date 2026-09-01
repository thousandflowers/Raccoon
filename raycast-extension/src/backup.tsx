import { Color, Icon, List } from "@raycast/api";
import { RccList } from "./rcc-list";
import {
	health,
	humanAge,
	parseBackup,
	type BackupHealth,
	type BackupReport,
} from "./backup-json";

const TINT: Record<BackupHealth, Color> = {
	never: Color.Red,
	fresh: Color.Green,
	late: Color.Orange,
	overdue: Color.Red,
};

const HEADLINE: Record<BackupHealth, string> = {
	never: "This Mac has never been backed up",
	fresh: "Backed up",
	late: "Backup is a few days old",
	overdue: "Backup is more than a week old",
};

function Rows({ b, actions }: { b: BackupReport; actions: React.ReactNode }) {
	const state = health(b);
	return (
		<>
			{/* The answer, as one row, before any of the detail under it. */}
			<List.Section title="Backup">
				<List.Item
					icon={{
						source:
							state === "fresh"
								? Icon.CheckCircle
								: Icon.ExclamationMark,
						tintColor: TINT[state],
					}}
					title={HEADLINE[state]}
					subtitle={b.last_backup.date || undefined}
					accessories={[
						{
							tag: {
								value: humanAge(b.last_backup.hours_ago),
								color: TINT[state],
							},
						},
					]}
					actions={actions}
				/>
			</List.Section>

			<List.Section title="Destination">
				<List.Item
					icon={{
						source: b.destination.configured
							? Icon.HardDrive
							: Icon.XMarkCircle,
						tintColor: b.destination.configured
							? Color.Green
							: Color.Red,
					}}
					title={
						b.destination.configured
							? b.destination.name || "Configured"
							: "No destination configured"
					}
					subtitle={
						b.destination.configured
							? b.destination.kind || undefined
							: "Time Machine has nowhere to write"
					}
					actions={actions}
				/>
				<List.Item
					icon={{
						source: b.running ? Icon.CircleProgress50 : Icon.Pause,
						tintColor: b.running
							? Color.Orange
							: Color.SecondaryText,
					}}
					title="Status"
					accessories={[
						{
							tag: {
								value: b.running ? "backing up now" : "idle",
								color: b.running
									? Color.Orange
									: Color.SecondaryText,
							},
						},
					]}
					actions={actions}
				/>
			</List.Section>

			{b.exclusions.length > 0 ? (
				<List.Section
					title="Excluded from backup"
					subtitle={`${b.exclusions.length}`}
				>
					{b.exclusions.map((path) => (
						<List.Item
							key={path}
							icon={{
								source: Icon.Minus,
								tintColor: Color.SecondaryText,
							}}
							title={path}
							actions={actions}
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
			command="backup"
			parse={parseBackup}
			navigationTitle={(b) =>
				b
					? `Time Machine — ${HEADLINE[health(b)].toLowerCase()}`
					: "Time Machine"
			}
			searchBarPlaceholder="Search backup details"
			emptyIcon={Icon.HardDrive}
			emptyTitle="No Time Machine information"
		>
			{(b, actions) => <Rows b={b} actions={actions} />}
		</RccList>
	);
}
