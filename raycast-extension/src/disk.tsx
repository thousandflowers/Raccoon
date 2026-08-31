import { findCommand } from "./commands";
import { RccDetail } from "./rcc-detail";

export default function Command() {
	return <RccDetail command={findCommand("disk")} />;
}
