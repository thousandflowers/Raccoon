import { Color, Icon, List } from "@raycast/api";
import { RccList } from "./rcc-list";
import { parseEnv, problems, shortVersion, type EnvReport } from "./env-json";

function Rows({ e, actions }: { e: EnvReport; actions: React.ReactNode }) {
	const missing = e.path.filter((p) => !p.exists);
	const present = e.path.filter((p) => p.exists);
	return (
		<>
			{/* A command on the PATH that still fails: the most surprising of the
			    three, so it goes first even when the list is empty elsewhere. */}
			{e.broken_symlinks.length > 0 ? (
				<List.Section
					title="Broken symlinks"
					subtitle={`${e.broken_symlinks.length}`}
				>
					{e.broken_symlinks.map((b) => (
						<List.Item
							key={b.link}
							icon={{
								source: Icon.XMarkCircle,
								tintColor: Color.Red,
							}}
							title={b.name}
							subtitle={`→ ${b.target}`}
							accessories={[
								{
									tag: {
										value: "target gone",
										color: Color.Red,
									},
								},
							]}
							actions={actions}
						/>
					))}
				</List.Section>
			) : null}

			{missing.length > 0 ? (
				<List.Section
					title="Missing from disk"
					subtitle={`${missing.length}`}
				>
					{missing.map((p) => (
						<List.Item
							key={p.path}
							icon={{
								source: Icon.Folder,
								tintColor: Color.Orange,
							}}
							title={p.path}
							accessories={[
								{
									tag: {
										value: "does not exist",
										color: Color.Orange,
									},
								},
							]}
							actions={actions}
						/>
					))}
				</List.Section>
			) : null}

			{e.duplicates.length > 0 ? (
				<List.Section
					title="Listed twice"
					subtitle={`${e.duplicates.length}`}
				>
					{e.duplicates.map((d, i) => (
						<List.Item
							key={`${d}-${i}`}
							icon={{
								source: Icon.Duplicate,
								tintColor: Color.Orange,
							}}
							title={d}
							actions={actions}
						/>
					))}
				</List.Section>
			) : null}

			<List.Section title="Tools">
				{e.tools.map((t) => (
					<List.Item
						key={t.name}
						icon={{
							source: t.found ? Icon.CheckCircle : Icon.Minus,
							tintColor: t.found
								? Color.Green
								: Color.SecondaryText,
						}}
						title={t.name}
						subtitle={
							t.version
								? shortVersion(t.version)
								: "not installed"
						}
						actions={actions}
					/>
				))}
			</List.Section>

			<List.Section title="PATH" subtitle={`${present.length} entries`}>
				{present.map((p, i) => (
					<List.Item
						key={`${p.path}-${i}`}
						icon={{
							source: Icon.Folder,
							tintColor: Color.SecondaryText,
						}}
						title={p.path}
						// Position matters: the first match on the PATH is the one that runs.
						accessories={[{ text: `#${i + 1}` }]}
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
			command="env"
			parse={parseEnv}
			navigationTitle={(e) => {
				if (!e) return "Environment";
				const n = problems(e);
				return n === 0
					? `Environment — ${e.path.length} PATH entries, nothing wrong`
					: `Environment — ${n} ${n === 1 ? "problem" : "problems"}`;
			}}
			searchBarPlaceholder="Search PATH entries, symlinks and tools"
			emptyIcon={Icon.Terminal}
			emptyTitle="Nothing on the PATH"
		>
			{(e, actions) => <Rows e={e} actions={actions} />}
		</RccList>
	);
}
