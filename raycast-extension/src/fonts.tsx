import { Color, Icon, List } from "@raycast/api";
import { RccList } from "./rcc-list";
import { parseFonts, sourceLabel, type FontsReport } from "./fonts-json";

function Rows({ f, actions }: { f: FontsReport; actions: React.ReactNode }) {
	// The only line anyone acts on, so it is the only one that can be red.
	const broken = f.corrupted > 0;
	return (
		<>
			<List.Section title="Installed" subtitle={`${f.installed}`}>
				{f.sources.map((s) => (
					<List.Item
						key={s.path}
						icon={{
							source: Icon.Text,
							tintColor: Color.SecondaryText,
						}}
						title={sourceLabel(s.path)}
						subtitle={s.path}
						accessories={[{ text: String(s.count) }]}
						actions={actions}
					/>
				))}
			</List.Section>
			<List.Section title="Health">
				<List.Item
					icon={{
						source: broken ? Icon.XMarkCircle : Icon.CheckCircle,
						tintColor: broken ? Color.Red : Color.Green,
					}}
					title="Corrupted fonts"
					subtitle={broken ? "fc-scan cannot read these" : undefined}
					accessories={[
						{
							tag: {
								value: String(f.corrupted),
								color: broken ? Color.Red : Color.Green,
							},
						},
					]}
					actions={actions}
				/>
				<List.Item
					icon={{
						source: Icon.Duplicate,
						tintColor:
							f.fontconfig.duplicate_families > 0
								? Color.Orange
								: Color.SecondaryText,
					}}
					title="Duplicate families"
					accessories={[
						{
							tag: {
								value: String(f.fontconfig.duplicate_families),
								color:
									f.fontconfig.duplicate_families > 0
										? Color.Orange
										: Color.SecondaryText,
							},
						},
					]}
					actions={actions}
				/>
			</List.Section>
			<List.Section title="Catalog">
				{f.fontconfig.available ? (
					<>
						<List.Item
							icon={{
								source: Icon.List,
								tintColor: Color.SecondaryText,
							}}
							title="Fonts known to fontconfig"
							accessories={[{ text: String(f.fontconfig.fonts) }]}
							actions={actions}
						/>
						<List.Item
							icon={{
								source: Icon.List,
								tintColor: Color.SecondaryText,
							}}
							title="Families"
							accessories={[
								{ text: String(f.fontconfig.families) },
							]}
							actions={actions}
						/>
					</>
				) : (
					<List.Item
						icon={{
							source: Icon.Minus,
							tintColor: Color.SecondaryText,
						}}
						title="fontconfig is not installed"
						subtitle="Duplicate and corruption checks need it"
						actions={actions}
					/>
				)}
			</List.Section>
		</>
	);
}

export default function Command() {
	return (
		<RccList
			command="fonts"
			parse={parseFonts}
			navigationTitle={(f) =>
				f
					? `Fonts — ${f.installed} installed${f.corrupted > 0 ? `, ${f.corrupted} broken` : ""}`
					: "Fonts"
			}
			searchBarPlaceholder="Search font sources and checks"
			emptyIcon={Icon.Text}
			emptyTitle="No fonts found"
		>
			{(f, actions) => <Rows f={f} actions={actions} />}
		</RccList>
	);
}
