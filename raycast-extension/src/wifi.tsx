import { Color, Icon, List } from "@raycast/api";
import { RccList } from "./rcc-list";
import { parseWifi } from "./simple-json";

export default function Command() {
	return (
		<RccList
			command="wifi"
			parse={parseWifi}
			navigationTitle={(w) =>
				w?.active_ssid ? `Wi-Fi — ${w.active_ssid}` : "Wi-Fi"
			}
			searchBarPlaceholder="Search saved networks"
			emptyIcon={Icon.Wifi}
			emptyTitle="No saved networks"
		>
			{(w, actions) =>
				w.known_networks.map((ssid) => {
					// The one you are on is the one you are looking for.
					const active = ssid === w.active_ssid;
					return (
						<List.Item
							key={ssid}
							icon={{
								source: active ? Icon.Wifi : Icon.WifiDisabled,
								tintColor: active
									? Color.Green
									: Color.SecondaryText,
							}}
							title={ssid}
							subtitle={active ? w.interface : undefined}
							accessories={
								active
									? [
											{
												tag: {
													value: "Connected",
													color: Color.Green,
												},
											},
										]
									: []
							}
							actions={actions}
						/>
					);
				})
			}
		</RccList>
	);
}
