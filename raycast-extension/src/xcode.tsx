import { Color, Icon, List } from "@raycast/api";
import { RccList } from "./rcc-list";
import {
	derivedLevel,
	humanBytes,
	parseXcode,
	type XcodeReport,
} from "./xcode-json";

const DERIVED_TINT = {
	empty: Color.SecondaryText,
	ok: Color.Green,
	large: Color.Orange,
} as const;

function Rows({ x, actions }: { x: XcodeReport; actions: React.ReactNode }) {
	if (!x.installed) {
		return (
			<List.Item
				icon={{
					source: Icon.XMarkCircle,
					tintColor: Color.SecondaryText,
				}}
				title="Xcode is not installed"
				subtitle="Install it from the App Store to see simulators and build caches"
				actions={actions}
			/>
		);
	}
	const booted = x.simulators.filter((s) => s.booted);
	const level = derivedLevel(x.derived_data.bytes);
	return (
		<>
			{/* The only thing here anyone deletes. */}
			<List.Section title="Reclaimable">
				<List.Item
					icon={{
						source: Icon.Trash,
						tintColor: DERIVED_TINT[level],
					}}
					title="DerivedData"
					subtitle={
						x.derived_data.present
							? `${x.derived_data.projects} ${x.derived_data.projects === 1 ? "project" : "projects"}`
							: "not created yet"
					}
					accessories={[
						{
							tag: {
								value: humanBytes(x.derived_data.bytes),
								color: DERIVED_TINT[level],
							},
						},
					]}
					actions={actions}
				/>
			</List.Section>

			{/* A simulator left booted holds memory until someone shuts it down, so
			    the running ones are separated from the merely installed. */}
			{booted.length > 0 ? (
				<List.Section title="Running now" subtitle={`${booted.length}`}>
					{booted.map((s) => (
						<List.Item
							key={`booted-${s.name}`}
							icon={{
								source: Icon.Mobile,
								tintColor: Color.Orange,
							}}
							title={s.name}
							accessories={[
								{
									tag: {
										value: "booted",
										color: Color.Orange,
									},
								},
							]}
							actions={actions}
						/>
					))}
				</List.Section>
			) : null}

			<List.Section
				title="Simulators"
				subtitle={`${x.simulators.length} installed`}
			>
				{x.simulators
					.filter((s) => !s.booted)
					.map((s, i) => (
						<List.Item
							key={`sim-${s.name}-${i}`}
							icon={{
								source: Icon.Mobile,
								tintColor: Color.SecondaryText,
							}}
							title={s.name}
							actions={actions}
						/>
					))}
			</List.Section>

			<List.Section title="Installed">
				<List.Item
					icon={{
						source: Icon.Hammer,
						tintColor: Color.SecondaryText,
					}}
					title="Xcode"
					subtitle={x.build ? `build ${x.build}` : undefined}
					accessories={[{ text: x.version ?? "unknown version" }]}
					actions={actions}
				/>
				{x.platforms.map((p) => (
					<List.Item
						key={`plat-${p}`}
						icon={{
							source: Icon.Layers,
							tintColor: Color.SecondaryText,
						}}
						title={p}
						actions={actions}
					/>
				))}
			</List.Section>
		</>
	);
}

export default function Command() {
	return (
		<RccList
			command="xcode"
			parse={parseXcode}
			navigationTitle={(x) => {
				if (!x || !x.installed) return "Xcode";
				const size = humanBytes(x.derived_data.bytes);
				return `Xcode ${x.version ?? ""} — DerivedData ${size}`.replace(
					"  ",
					" ",
				);
			}}
			searchBarPlaceholder="Search simulators and platforms"
			emptyIcon={Icon.Hammer}
			emptyTitle="Nothing from Xcode"
		>
			{(x, actions) => <Rows x={x} actions={actions} />}
		</RccList>
	);
}
