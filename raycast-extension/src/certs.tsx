import { Color, Icon, List } from "@raycast/api";
import { useMemo } from "react";
import { RccList } from "./rcc-list";
import {
	byUrgency,
	parseCerts,
	type CertStatus,
	type CertsReport,
} from "./certs-json";

const TINT: Record<CertStatus, Color> = {
	expired: Color.Red,
	expiring: Color.Orange,
	valid: Color.Green,
};

const ICON: Record<CertStatus, Icon> = {
	expired: Icon.XMarkCircle,
	expiring: Icon.Clock,
	valid: Icon.CheckCircle,
};

function Rows({ c, actions }: { c: CertsReport; actions: React.ReactNode }) {
	// Expired first: a certificate that already stopped working is the reason
	// anyone opens this.
	const sorted = useMemo(
		() => [...c.certificates].sort(byUrgency),
		[c.certificates],
	);
	return (
		<>
			{sorted.map((cert, i) => (
				<List.Item
					key={`${cert.name}-${i}`}
					icon={{
						source: ICON[cert.status],
						tintColor: TINT[cert.status],
					}}
					title={cert.name}
					subtitle={cert.issuer}
					keywords={[cert.status, cert.expires]}
					accessories={[
						{ text: cert.expires },
						...(cert.self_signed
							? [{ tag: { value: "self-signed" } }]
							: []),
						{
							tag: {
								value: cert.status,
								color: TINT[cert.status],
							},
						},
					]}
					actions={actions}
				/>
			))}
		</>
	);
}

export default function Command() {
	return (
		<RccList
			command="certs"
			parse={parseCerts}
			navigationTitle={(c) =>
				c
					? `Certificates — ${c.counts.expired} expired, ${c.counts.expiring} expiring within ${c.expiring_window_days} days`
					: "Certificates"
			}
			searchBarPlaceholder="Search by name, issuer or status"
			emptyIcon={Icon.Lock}
			emptyTitle="No certificates in the keychain"
		>
			{(c, actions) => <Rows c={c} actions={actions} />}
		</RccList>
	);
}
