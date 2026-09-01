import { Action, ActionPanel, Color, Icon, List, Keyboard } from "@raycast/api";
import { homedir } from "node:os";
import { RccList } from "./rcc-list";
import { runInTerminal, shellQuote } from "./terminal";
import {
	parseGit,
	repoLevel,
	shortPath,
	sortRepos,
	summarise,
	type GitReport,
	type GitRepo,
	type RepoLevel,
} from "./git-json";

const TINT: Record<RepoLevel, Color> = {
	unpushed: Color.Red,
	detached: Color.Red,
	uncommitted: Color.Orange,
	loose: Color.SecondaryText,
};

const ICON: Record<RepoLevel, Icon> = {
	unpushed: Icon.ArrowUpCircle,
	detached: Icon.Warning,
	uncommitted: Icon.Pencil,
	loose: Icon.Link,
};

const SECTION: Record<RepoLevel, string> = {
	unpushed: "Only on this Mac",
	detached: "Not on a branch",
	uncommitted: "Uncommitted work",
	loose: "No upstream, or stashed",
};

const ORDER: RepoLevel[] = ["unpushed", "detached", "uncommitted", "loose"];

/** Open Terminal in the repository, with its status already printed. */
function openRepo(repo: GitRepo) {
	return runInTerminal(`cd ${shellQuote(repo.path)} && git status`);
}

function repoActions(repo: GitRepo, shared: React.ReactNode) {
	return (
		<ActionPanel>
			{/* Nothing here can be fixed without a decision: what to commit, what
			    to push, which branch to attach. So Enter opens the repository with
			    its status in front of you rather than pretending to resolve it. */}
			<Action
				title="Open in Terminal"
				icon={Icon.Terminal}
				onAction={() => openRepo(repo)}
			/>
			<Action.ShowInFinder path={repo.path} />
			<Action.CopyToClipboard
				title="Copy Path"
				content={repo.path}
				shortcut={Keyboard.Shortcut.Common.Pin}
			/>
			{shared}
		</ActionPanel>
	);
}

function Rows({ g, actions }: { g: GitReport; actions: React.ReactNode }) {
	const home = homedir();
	const sorted = sortRepos(g.repos);
	const clean = g.repos_total - g.repos_with_issues;

	return (
		<>
			<List.Section title="Scanned">
				<List.Item
					icon={{
						source:
							g.repos_with_issues === 0
								? Icon.CheckCircle
								: Icon.Folder,
						tintColor:
							g.repos_with_issues === 0
								? Color.Green
								: Color.SecondaryText,
					}}
					title={
						g.repos_with_issues === 0
							? "Every repository is clean"
							: `${g.repos_with_issues} of ${g.repos_total} need attention`
					}
					subtitle={`${clean} clean`}
					actions={actions}
				/>
			</List.Section>

			{ORDER.map((level) => {
				const group = sorted.filter((r) => repoLevel(r) === level);
				if (group.length === 0) return null;
				return (
					<List.Section
						key={level}
						title={SECTION[level]}
						subtitle={`${group.length}`}
					>
						{group.map((repo) => (
							<List.Item
								key={repo.path}
								icon={{
									source: ICON[level],
									tintColor: TINT[level],
								}}
								title={repo.name}
								subtitle={shortPath(repo.path, home)}
								accessories={[
									{
										tag: {
											value: summarise(repo),
											color: TINT[level],
										},
									},
								]}
								actions={repoActions(repo, actions)}
							/>
						))}
					</List.Section>
				);
			})}
		</>
	);
}

export default function Command() {
	return (
		<RccList
			command="git"
			parse={parseGit}
			navigationTitle={(g) =>
				g
					? g.repos_with_issues === 0
						? "Git — all clean"
						: `Git — ${g.repos_with_issues} of ${g.repos_total} need attention`
					: "Git"
			}
			searchBarPlaceholder="Search repositories"
			emptyIcon={Icon.Folder}
			emptyTitle="No git repositories found"
		>
			{(g, actions) => <Rows g={g} actions={actions} />}
		</RccList>
	);
}
