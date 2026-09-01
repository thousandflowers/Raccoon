import {
	Action,
	ActionPanel,
	Alert,
	closeMainWindow,
	Color,
	confirmAlert,
	Icon,
	Keyboard,
	List,
	openExtensionPreferences,
	showToast,
	Toast,
	useNavigation,
} from "@raycast/api";
import { showFailureToast, useExec, usePromise } from "@raycast/utils";
import { useMemo } from "react";
import { AUDIT_CONF, readSkipList, skipCheck } from "./audit-conf";
import {
	type AuditCheck,
	type AuditStatus,
	countByStatus,
	fixableCount,
	readAuditRun,
} from "./audit-json";
import { findCommand } from "./commands";
import { MissingRcc, REPO_URL } from "./missing-rcc";
import { RccDetail } from "./rcc-detail";
import { RccNotFoundError, resolveRcc, RUNTIME_PATH } from "./rcc";
import { fixCommand, runInTerminal, supportsFixOnly } from "./terminal";

/**
 * How long to let the audit run.
 *
 * Not the 10s useExec defaults to, and not a number chosen just above the 7.4s
 * measured here either: the audit shells out to `softwareupdate -l`, and how
 * long that takes is a property of what the machine and Apple's servers are
 * doing rather than of the audit. Seven seconds on one Mac is minutes on
 * another. This is not a performance budget — it is the point past which the
 * command is assumed hung rather than slow, and it is deliberately far enough
 * out that a slow softwareupdate never reaches it.
 */
const AUDIT_TIMEOUT_MS = 5 * 60 * 1000;

const TINT: Record<AuditStatus, Color> = {
	pass: Color.Green,
	warn: Color.Orange,
	fail: Color.Red,
};

const ICON: Record<AuditStatus, Icon> = {
	pass: Icon.CheckCircle,
	warn: Icon.Warning,
	fail: Icon.XMarkCircle,
};

const LABEL: Record<AuditStatus, string> = {
	pass: "Pass",
	warn: "Warning",
	fail: "Fail",
};

function CheckDetail({
	check,
	skipped,
}: {
	check: AuditCheck;
	skipped: boolean;
}) {
	return (
		<List.Item.Detail
			metadata={
				<List.Item.Detail.Metadata>
					<List.Item.Detail.Metadata.TagList title="Status">
						<List.Item.Detail.Metadata.TagList.Item
							text={LABEL[check.status]}
							color={TINT[check.status]}
						/>
					</List.Item.Detail.Metadata.TagList>
					<List.Item.Detail.Metadata.Label
						title="Category"
						text={check.category}
					/>
					<List.Item.Detail.Metadata.Label
						title="Value"
						text={check.value}
					/>
					{check.cis ? (
						<List.Item.Detail.Metadata.Label
							title="CIS"
							text={check.cis}
						/>
					) : null}
					<List.Item.Detail.Metadata.Separator />
					<List.Item.Detail.Metadata.Label
						title="Verify with"
						text={check.command}
					/>
					<List.Item.Detail.Metadata.Label
						title="Fix available"
						text={
							!check.fix_available
								? "No"
								: skipped
									? "Yes, but skipped in audit.conf"
									: "Yes"
						}
						icon={{
							source: !check.fix_available
								? Icon.Minus
								: skipped
									? Icon.MinusCircle
									: Icon.Hammer,
							tintColor:
								check.fix_available && !skipped
									? Color.Orange
									: Color.SecondaryText,
						}}
					/>
				</List.Item.Detail.Metadata>
			}
		/>
	);
}

export default function Command() {
	const { push } = useNavigation();

	// resolveRcc throws when the binary is nowhere to be found, and a hook cannot
	// be skipped, so the miss is turned into a value and useExec is told not to
	// run rather than not called.
	let rccPath: string | null = null;
	let resolveError: unknown;
	try {
		rccPath = resolveRcc();
	} catch (error) {
		resolveError = error;
	}

	// audit.conf is the user's file, not a product of the audit, so it is read
	// from where it is written rather than waited for in the report: the JSON
	// cannot say which checks are skipped, because fix_available is recorded
	// before the opt-out is consulted.
	const { data: skipList, revalidate: revalidateSkipList } =
		usePromise(readSkipList);
	const skipped = useMemo(() => new Set(skipList ?? []), [skipList]);

	const { isLoading, data, error, revalidate } = useExec(
		rccPath ?? "rcc",
		["audit", "--json"],
		{
			execute: rccPath !== null,
			timeout: AUDIT_TIMEOUT_MS,
			env: { ...process.env, NO_COLOR: "1", PATH: RUNTIME_PATH },
			// The exit code is classified here, not by useExec: audit spends 1 on
			// "a check failed" and 2 on "warnings only", and both are reports.
			parseOutput: readAuditRun,
		},
	);

	if (resolveError instanceof RccNotFoundError) return <MissingRcc />;

	if (error) {
		return (
			<List>
				<List.EmptyView
					icon={{ source: Icon.XMarkCircle, tintColor: Color.Red }}
					title="The audit could not be read"
					description={error.message}
					actions={
						<ActionPanel>
							<Action
								title="Run Again"
								icon={Icon.ArrowClockwise}
								shortcut={Keyboard.Shortcut.Common.Refresh}
								onAction={revalidate}
							/>
							<Action
								title="Show Raw Output"
								icon={Icon.Text}
								onAction={() =>
									push(
										<RccDetail
											command={findCommand("audit")}
										/>,
									)
								}
							/>
							<Action
								title="Set Rcc Path"
								icon={Icon.Gear}
								onAction={openExtensionPreferences}
							/>
							<Action.OpenInBrowser
								title="Open Raccoon on GitHub"
								url={REPO_URL}
							/>
						</ActionPanel>
					}
				/>
			</List>
		);
	}

	const counts = data ? countByStatus(data) : undefined;
	const fixable = data ? fixableCount(data, skipped) : 0;

	const applyAllFixes = async () => {
		const confirmed = await confirmAlert({
			title: `Apply ${fixable} automatic ${fixable === 1 ? "fix" : "fixes"}?`,
			message:
				"Raccoon will change system security settings on this Mac. " +
				"Every check it touches is listed above with what it found.",
			icon: { source: Icon.Hammer, tintColor: Color.Red },
			primaryAction: {
				title: "Apply Fixes",
				style: Alert.ActionStyle.Destructive,
			},
		});
		if (!confirmed) return;
		// Pushed rather than run silently: the fix run prints as it goes, and
		// RccDetail already streams it.
		push(
			<RccDetail
				command={{
					id: "audit-fix",
					args: ["audit", "--fix", "--force"],
					title: "Applying Fixes",
					description: "Applying every automatic fix",
					needsRoot: true,
				}}
			/>,
		);
	};

	// Enter on a warning or a failure fixes that one check, in Terminal.
	//
	// A terminal and not a pane inside Raycast: a fix needs administrator
	// rights, and there is no tty behind a Raycast view for sudo to prompt on.
	// Touch ID and the password prompt only exist in a real terminal.
	const fixOne = async (check: AuditCheck) => {
		let rcc: string;
		try {
			rcc = resolveRcc();
		} catch {
			await showToast({
				style: Toast.Style.Failure,
				title: "rcc not found",
				message:
					"Set the Raccoon CLI path in the extension preferences.",
			});
			return;
		}

		// rcc 0.16.0 and earlier ignore --fix-only instead of refusing it, which
		// would turn one Enter into every fix on the machine. Measured: seven
		// instead of one. Refuse rather than narrow-by-hope.
		if (!(await supportsFixOnly(rcc))) {
			await showToast({
				style: Toast.Style.Failure,
				title: "This rcc cannot fix one check at a time",
				message:
					"--fix-only arrived in rcc 0.17.0. Older versions would apply every fix instead. Upgrade with `brew upgrade rcc`.",
			});
			return;
		}

		await runInTerminal(fixCommand(rcc, check.name));
		await showToast({
			style: Toast.Style.Success,
			title: `Fixing ${check.name}`,
			message: "Running in Terminal, where it can ask for admin rights.",
		});
		await closeMainWindow();
	};

	const skip = async (check: AuditCheck) => {
		try {
			const outcome = await skipCheck(check.name);
			await showToast({
				style: Toast.Style.Success,
				title:
					outcome === "added"
						? `${check.name} will not be offered again`
						: `${check.name} was already on the list`,
				message: AUDIT_CONF,
			});
			// Only the skip list changed. Re-running the audit would spend seven
			// seconds to be told the same thing: the JSON is identical either way.
			if (outcome === "added") revalidateSkipList();
		} catch (error) {
			await showFailureToast(error, {
				title: `Could not add ${check.name} to audit.conf`,
			});
		}
	};

	// Every screen-level action, repeated on each row so the panel is the same
	// wherever the cursor is. `fixable` is often zero — a Mac with nothing wrong
	// is the ordinary case — and the action is left out entirely rather than
	// offered as a button that would do nothing.
	const screenActions = (
		<>
			{fixable > 0 && (
				<Action
					title={`Fix ${fixable} ${fixable === 1 ? "Issue" : "Issues"} Automatically`}
					icon={{ source: Icon.Hammer, tintColor: Color.Red }}
					onAction={applyAllFixes}
				/>
			)}
			<Action
				title="Run Again"
				icon={Icon.ArrowClockwise}
				shortcut={Keyboard.Shortcut.Common.Refresh}
				onAction={revalidate}
			/>
			<Action
				title="Show Raw Output"
				icon={Icon.Text}
				onAction={() =>
					push(<RccDetail command={findCommand("audit")} />)
				}
			/>
			<Action
				title="Set Rcc Path"
				icon={Icon.Gear}
				onAction={openExtensionPreferences}
			/>
		</>
	);

	return (
		<List
			isLoading={isLoading}
			// Not gated on isLoading: data survives a revalidate, so gating on it
			// collapsed the panel being read for the seven seconds of a reload.
			isShowingDetail={(data?.results.length ?? 0) > 0}
			navigationTitle={
				counts
					? `Security Audit — ${counts.pass} pass, ${counts.warn} warn, ${counts.fail} fail`
					: "Security Audit"
			}
			searchBarPlaceholder="Search checks by name, category or finding"
		>
			<List.EmptyView
				icon={{
					source: Icon.MagnifyingGlass,
					tintColor: Color.SecondaryText,
				}}
				title={isLoading ? "Running the audit" : "No checks matched"}
				description={
					isLoading
						? "rcc audit reads about thirty things about this Mac. It takes a few seconds."
						: undefined
				}
			/>
			{(data?.results ?? []).map((check, index) => {
				const isSkipped = skipped.has(check.name);
				return (
					<List.Item
						key={`${check.category}/${check.name}/${index}`}
						// The icon keeps the status colour when a check is skipped.
						// Skipping fixes nothing — the check still found what it found —
						// and greying it out would say "handled", which is not what was
						// asked for. The extra grey tag is what says "skipped".
						icon={{
							source: ICON[check.status],
							tintColor: TINT[check.status],
						}}
						title={check.name}
						keywords={[
							check.category,
							check.value,
							...(isSkipped ? ["skipped"] : []),
						]}
						accessories={[
							...(isSkipped
								? [
										{
											tag: {
												value: "Skipped",
												color: Color.SecondaryText,
											},
										},
									]
								: []),
							{
								tag: {
									value: LABEL[check.status],
									color: TINT[check.status],
								},
							},
						]}
						detail={
							<CheckDetail check={check} skipped={isSkipped} />
						}
						actions={
							<ActionPanel>
								<ActionPanel.Section title={check.name}>
									{check.status !== "pass" &&
									check.fix_available &&
									!isSkipped ? (
										<Action
											title={`Fix ${check.name}`}
											icon={{
												source: Icon.Hammer,
												tintColor: Color.Red,
											}}
											onAction={() => fixOne(check)}
										/>
									) : null}
									<Action.CopyToClipboard
										title="Copy Verification Command"
										content={check.command}
										shortcut={{
											modifiers: ["cmd"],
											key: "c",
										}}
									/>
									{check.cis ? (
										<Action.CopyToClipboard
											title="Copy CIS Reference"
											content={check.cis}
											shortcut={
												Keyboard.Shortcut.Common.Copy
											}
										/>
									) : null}
									{check.fix_available && !isSkipped ? (
										<Action
											title="Never Offer to Fix This"
											icon={Icon.MinusCircle}
											onAction={() => skip(check)}
										/>
									) : null}
								</ActionPanel.Section>
								<ActionPanel.Section>
									{screenActions}
								</ActionPanel.Section>
							</ActionPanel>
						}
					/>
				);
			})}
		</List>
	);
}
