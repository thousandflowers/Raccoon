import { Color, Icon, List } from "@raycast/api";
import { RccList } from "./rcc-list";
import { parseTrash } from "./simple-json";

/** A trash worth emptying, one worth noting, or one that is already empty. */
function weight(count: number): Color {
	if (count === 0) return Color.SecondaryText;
	if (count < 50) return Color.Green;
	return Color.Orange;
}

export default function Command() {
	return (
		<RccList
			command="trash"
			parse={parseTrash}
			navigationTitle={(t) => (t ? `Trash — ${t.size}` : "Trash")}
			searchBarPlaceholder="Search trash details"
			emptyIcon={Icon.Trash}
			emptyTitle="Nothing in the trash"
		>
			{(t, actions) => [
				<List.Item
					key="size"
					icon={{ source: Icon.Trash, tintColor: weight(t.count) }}
					title="Size"
					accessories={[
						{ tag: { value: t.size, color: weight(t.count) } },
					]}
					actions={actions}
				/>,
				<List.Item
					key="count"
					icon={{ source: Icon.Document, tintColor: weight(t.count) }}
					title="Items"
					accessories={[
						{
							tag: {
								value: String(t.count),
								color: weight(t.count),
							},
						},
					]}
					actions={actions}
				/>,
				<List.Item
					key="path"
					icon={{
						source: Icon.Folder,
						tintColor: Color.SecondaryText,
					}}
					title="Location"
					subtitle={t.path}
					actions={actions}
				/>,
			]}
		</RccList>
	);
}
