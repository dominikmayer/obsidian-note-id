import { NoteSearchModal } from "./searchModal";
import { App, TFile } from "obsidian";
import { NoteMeta } from "./types";

export class OpenNoteModal extends NoteSearchModal {
	constructor(
		app: App,
		idProperty: string,
		tocProperty: string,
		noteCache: Map<string, NoteMeta>,
	) {
		const instructions = [
			{
				command: "↵",
				purpose: "open",
			},
			{
				command: "⌘ ↵",
				purpose: "to open in a new tab",
			},
			{
				command: "⌘ ⌥ ↵",
				purpose: "to open on the right",
			},
		];
		super(app, idProperty, tocProperty, noteCache, instructions);
	}

	onChooseItem(item: TFile, evt: MouseEvent | KeyboardEvent): void {
		const isMod = evt.metaKey || evt.ctrlKey; // Cmd (Mac) or Ctrl (Windows/Linux)
		const isAlt = evt.altKey;
		const isShift = evt.shiftKey;
		const newLeaf = isMod && !isShift;
		const splitRight = isMod && isAlt && !isShift;
		const open = !isMod && !isAlt && !isShift;

		if (splitRight) {
			this.app.workspace.getLeaf("split").openFile(item);
		} else if (newLeaf) {
			this.app.workspace.openLinkText(item.path, "", newLeaf);
		} else if (open) {
			this.app.workspace.openLinkText(item.path, "", newLeaf);
		}
	}
}
