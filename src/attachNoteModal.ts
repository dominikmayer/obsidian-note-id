import { NoteSearchModal } from "./searchModal";
import { App, TFile } from "obsidian";
import { NoteMeta } from "./types";
import { ElmApp } from "/.elm";

export class AttachNoteModal extends NoteSearchModal {
	private elmApp: ElmApp;
	private currentNote: TFile;

	constructor(
		app: App,
		idProperty: string,
		tocProperty: string,
		noteCache: Map<string, NoteMeta>,
		currentNote: TFile,
		elmApp: ElmApp,
	) {
		const instructions = [
			{
				command: "↵",
				purpose: "set note ID in subsequence",
			},
			{
				command: "⌘ ↵",
				purpose: "set note ID in sequence",
			},
		];
		super(app, idProperty, tocProperty, noteCache, instructions);
		this.currentNote = currentNote;

		this.elmApp = elmApp;
	}

	onChooseItem(item: TFile, evt: MouseEvent | KeyboardEvent): void {
		const isMod = evt.metaKey || evt.ctrlKey; // Cmd (Mac) or Ctrl (Windows/Linux)
		const isAlt = evt.altKey;
		const isShift = evt.shiftKey;

		const sequence = isMod && !isAlt && !isShift;
		const subsequence = !isMod && !isAlt && !isShift;

		if (sequence) {
			this.updateId(item, false);
		} else if (subsequence) {
			this.updateId(item, true);
		}
	}

	private async updateId(from: TFile, subsequence: boolean) {
		if (this.elmApp && this.elmApp.ports.receiveGetNewIdForNoteFromNote) {
			this.elmApp.ports.receiveGetNewIdForNoteFromNote.send([
				this.currentNote.path,
				from.path,
				subsequence,
			]);
		}
	}
}
