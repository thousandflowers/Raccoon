import { Color, Icon, List } from "@raycast/api";
import { RccList } from "./rcc-list";
import { loadNow, parseStartup, type StartupReport } from "./startup-json";

/** Busy relative to nothing in particular, but 4 and 8 are where a Mac feels it. */
function loadTint(load: string): Color {
	const now = loadNow(load);
	if (now === null) return Color.SecondaryText;
	if (now < 4) return Color.Green;
	if (now < 8) return Color.Orange;
	return Color.Red;
}

function Rows({ s, actions }: { s: StartupReport; actions: React.ReactNode }) {
	return (
		<>
			{/* What a person installed, and can remove. */}
			<List.Section
				title="Login items"
				subtitle={`${s.login_items.length}`}
			>
				{s.login_items.map((item) => (
					<List.Item
						key={`login-${item}`}
						icon={{ source: Icon.Person, tintColor: Color.Green }}
						title={item}
						accessories={[{ tag: { value: "opens at login" } }]}
						actions={actions}
					/>
				))}
			</List.Section>
			<List.Section
				title="Your launch agents"
				subtitle={`${s.user_agents.length}`}
			>
				{s.user_agents.map((agent) => (
					<List.Item
						key={`agent-${agent}`}
						icon={{ source: Icon.Gear, tintColor: Color.Green }}
						title={agent}
						subtitle="~/Library/LaunchAgents"
						actions={actions}
					/>
				))}
			</List.Section>
			{/* What the system runs, which is context rather than a to-do list. */}
			<List.Section title="System">
				<List.Item
					icon={{ source: Icon.Gear, tintColor: Color.SecondaryText }}
					title="System launch agents"
					accessories={[{ text: String(s.counts.system_agents) }]}
					actions={actions}
				/>
				<List.Item
					icon={{ source: Icon.Gear, tintColor: Color.SecondaryText }}
					title="Launch daemons"
					accessories={[{ text: String(s.counts.daemons) }]}
					actions={actions}
				/>
				<List.Item
					icon={{ source: Icon.Bolt, tintColor: Color.SecondaryText }}
					title="Running services"
					accessories={[{ text: String(s.counts.running_services) }]}
					actions={actions}
				/>
				<List.Item
					icon={{
						source: Icon.Clock,
						tintColor: Color.SecondaryText,
					}}
					title="Uptime"
					accessories={[{ text: s.uptime || "Unknown" }]}
					actions={actions}
				/>
				<List.Item
					icon={{
						source: Icon.LineChart,
						tintColor: loadTint(s.load),
					}}
					title="Load average"
					accessories={[
						{
							tag: {
								value: s.load || "Unknown",
								color: loadTint(s.load),
							},
						},
					]}
					actions={actions}
				/>
			</List.Section>
		</>
	);
}

export default function Command() {
	return (
		<RccList
			command="startup"
			parse={parseStartup}
			navigationTitle={(s) =>
				s
					? `Startup — ${s.login_items.length + s.user_agents.length} things this Mac starts`
					: "Startup"
			}
			searchBarPlaceholder="Search login items and launch agents"
			emptyIcon={Icon.Power}
			emptyTitle="Nothing starts on its own"
		>
			{(s, actions) => <Rows s={s} actions={actions} />}
		</RccList>
	);
}
