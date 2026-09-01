import { Color, Icon, List } from "@raycast/api";
import { RccList } from "./rcc-list";
import {
	isNoise,
	parseNetwork,
	primaryAddress,
	type NetworkReport,
} from "./network-json";

function Rows({ n, actions }: { n: NetworkReport; actions: React.ReactNode }) {
	const real = n.interfaces.filter((i) => !isNoise(i));
	const loopback = n.interfaces.filter(isNoise);
	const firewallOn = n.firewall.application === "enabled";
	return (
		<>
			<List.Section title="Addresses" subtitle={`${real.length}`}>
				{real.map((i, index) => (
					<List.Item
						key={`${i.name}-${i.family}-${index}`}
						icon={{ source: Icon.Globe, tintColor: Color.Green }}
						title={i.address}
						subtitle={i.name}
						accessories={[
							{ tag: { value: i.kind } },
							{ text: i.family },
						]}
						actions={actions}
					/>
				))}
			</List.Section>

			{/* Something between you and the network, whether you meant it or not. */}
			{n.vpns.length > 0 || n.proxies.length > 0 ? (
				<List.Section title="In the way">
					{n.vpns.map((v) => (
						<List.Item
							key={`vpn-${v.name}`}
							icon={{
								source: Icon.Lock,
								tintColor:
									v.state === "connected"
										? Color.Orange
										: Color.SecondaryText,
							}}
							title={v.name}
							subtitle="VPN"
							accessories={[
								{
									tag: {
										value: v.state,
										color:
											v.state === "connected"
												? Color.Orange
												: Color.SecondaryText,
									},
								},
							]}
							actions={actions}
						/>
					))}
					{n.proxies.map((p) => (
						<List.Item
							key={`proxy-${p.name}`}
							icon={{
								source: Icon.Filter,
								tintColor: Color.Orange,
							}}
							title={p.name}
							subtitle={p.value}
							accessories={[
								{
									tag: {
										value: "proxy",
										color: Color.Orange,
									},
								},
							]}
							actions={actions}
						/>
					))}
				</List.Section>
			) : null}

			<List.Section title="Name resolution" subtitle={`${n.dns.length}`}>
				{n.dns.map((server) => (
					<List.Item
						key={server}
						icon={{
							source: Icon.Book,
							tintColor: Color.SecondaryText,
						}}
						title={server}
						actions={actions}
					/>
				))}
			</List.Section>

			<List.Section title="Status">
				<List.Item
					icon={{
						source: firewallOn ? Icon.Shield : Icon.ExclamationMark,
						tintColor: firewallOn ? Color.Green : Color.Red,
					}}
					title="Application firewall"
					accessories={[
						{
							tag: {
								value: n.firewall.application,
								color: firewallOn ? Color.Green : Color.Red,
							},
						},
					]}
					actions={actions}
				/>
				<List.Item
					icon={{
						source: Icon.Network,
						tintColor: Color.SecondaryText,
					}}
					title="Established connections"
					accessories={[{ text: String(n.connections) }]}
					actions={actions}
				/>
				{loopback.map((i, index) => (
					<List.Item
						key={`lo-${index}`}
						icon={{
							source: Icon.Circle,
							tintColor: Color.SecondaryText,
						}}
						title={i.address}
						subtitle={`${i.name} · ${i.kind}`}
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
			command="network"
			parse={parseNetwork}
			navigationTitle={(n) => {
				if (!n) return "Network";
				const primary = primaryAddress(n);
				return primary
					? `Network — ${primary.address} on ${primary.name}`
					: "Network — no routable address";
			}}
			searchBarPlaceholder="Search addresses, DNS, VPNs and proxies"
			emptyIcon={Icon.Globe}
			emptyTitle="Nothing on the network"
		>
			{(n, actions) => <Rows n={n} actions={actions} />}
		</RccList>
	);
}
