import { IDSidePanelView } from "./view";
import { IDSidePanelSettingTab } from "./settings";
import { ElmApp } from "/.elm";
import { IDSidePanelSettings, DEFAULT_SETTINGS } from "./types";
import {
	VIEW_TYPE_ID_PANEL,
	ID_FIELD_DEFAULT,
	TOC_TITLE_FIELD_DEFAULT,
} from "./constants";
import { Plugin, Notice, TFile, WorkspaceLeaf } from "obsidian";

export default class IDSidePanelPlugin extends Plugin {
	settings: IDSidePanelSettings;

	private getElmApp() {
		const activePanelView = this.getActivePanelView();
		return activePanelView ? activePanelView.getElmApp() : null;
	}

	async onload() {
		this.settings = Object.assign(
			{},
			DEFAULT_SETTINGS,
			await this.loadData(),
		);

		this.addSettingTab(new IDSidePanelSettingTab(this.app, this));

		this.registerView(VIEW_TYPE_ID_PANEL, (leaf) => {
			const view = new IDSidePanelView(leaf, this);
			view.icon = "file-digit";
			return view;
		});

		this.addRibbonIcon("file-digit", "Open side panel", () =>
			this.activateView(),
		);

		this.addCommands();
	}

	private addCommands() {
		this.addCommand({
			id: "open-id-side-panel",
			name: "Open side panel",
			callback: () => this.activateView(),
		});
		this.addCommand({
			id: "create-note-in-sequence",
			name: "Create new note in sequence",
			callback: () => this.createNoteFromCommand(false),
		});
		this.addCommand({
			id: "create-note-in-subsequence",
			name: "Create new note in subsequence",
			callback: () => this.createNoteFromCommand(true),
		});

		this.addCommand({
			id: "note-search",
			name: "Search notes by title, title of contents title or ID",
			callback: () => {
				this.ensurePanelAndElmApp((elmApp) => {
					if (elmApp.ports.receiveRequestSearch) {
						elmApp.ports.receiveRequestSearch.send(null);
					}
				});
			},
		});

		this.addCommand({
			id: "attach-note",
			name: "Set note ID based on another note",
			callback: () => {
				this.ensureActiveNoteAndElmApp((elmApp, currentNote) => {
					if (elmApp.ports.receiveRequestAttach) {
						elmApp.ports.receiveRequestAttach.send(
							currentNote.path,
						);
					}
				});
			},
		});

		this.addCommand({
			id: "suggest-id",
			name: "Suggest new ID for current note",
			callback: async () => {
				this.ensureActiveNoteAndElmApp(async (elmApp, currentNote) => {
					if (elmApp.ports.receiveRequestSuggestId) {
						const noteContent =
							await this.app.vault.read(currentNote);
						elmApp.ports.receiveRequestSuggestId.send([
							currentNote.path,
							noteContent,
						]);
					}
				});
			},
		});
	}

	private createNoteFromCommand(subsequence: boolean) {
		this.ensureActiveNoteAndElmApp((elmApp, currentNote) => {
			if (elmApp.ports.receiveCreateNote) {
				elmApp.ports.receiveCreateNote.send([
					currentNote.path,
					subsequence,
				]);
			} else {
				new Notice("This shouldn't happen. Please file a bug report.");
			}
		});
	}

	private ensureActiveNoteAndElmApp(
		callback: (elmApp: ElmApp, file: TFile) => void | Promise<void>,
	) {
		const currentNote = this.app.workspace.getActiveFile();
		if (!currentNote) {
			new Notice("No active note");
			return;
		}
		this.ensurePanelAndElmApp((elmApp) => {
			callback(elmApp, currentNote);
		});
	}

	private ensurePanelAndElmApp(callback: (elmApp: ElmApp) => void) {
		this.getOrCreateActivePanelView().then((panelView) => {
			if (!panelView) {
				new Notice("Failed to open the side panel");
				return;
			}

			this.waitForElmApp()
				.then(callback)
				.catch(() => {
					new Notice("Please try again");
				});
		});
	}

	private waitForElmApp(retries = 10, delay = 200): Promise<ElmApp | null> {
		return new Promise((resolve, reject) => {
			const checkElmApp = () => {
				const elmApp = this.getElmApp();
				if (elmApp) {
					resolve(elmApp);
				} else if (retries > 0) {
					setTimeout(() => checkElmApp(), delay);
					retries--;
				} else {
					reject(new Error("Elm app failed to load"));
				}
			};
			checkElmApp();
		});
	}

	private async getOrCreateActivePanelView(): Promise<IDSidePanelView | null> {
		const leaf = await this.getOrCreateLeaf();
		return leaf.view as IDSidePanelView;
	}
	private getActivePanelView(): IDSidePanelView | null {
		const leaves = this.app.workspace.getLeavesOfType(VIEW_TYPE_ID_PANEL);
		if (leaves.length > 0) {
			const view = leaves[0].view;
			if (view instanceof IDSidePanelView) {
				return view;
			}
		}
		return null;
	}

	async activateView() {
		const leaf = await this.getOrCreateLeaf();
		this.app.workspace.revealLeaf(leaf);
	}

	async getOrCreateLeaf(): Promise<WorkspaceLeaf> {
		let leaf = this.app.workspace.getLeavesOfType(VIEW_TYPE_ID_PANEL)[0];

		if (!leaf) {
			leaf = await this.createLeaf();
		}

		return leaf;
	}

	async createLeaf(): Promise<WorkspaceLeaf> {
		const leaf =
			this.app.workspace.getRightLeaf(false) ??
			this.app.workspace.getLeaf(true);
		await leaf.setViewState({
			type: VIEW_TYPE_ID_PANEL,
			active: true,
		});
		return leaf;
	}

	async saveSettings() {
		await this.saveData(this.settings);
		this.sendSettingsToElm(this.getSettings());
	}

	getSettings(): IDSidePanelSettings {
		return {
			...this.settings,
			idField: this.settings.idField || ID_FIELD_DEFAULT,
			tocField: this.settings.tocField || TOC_TITLE_FIELD_DEFAULT,
		};
	}

	private sendSettingsToElm(settings: IDSidePanelSettings) {
		const elmApp = this.getElmApp();
		if (elmApp && elmApp.ports.receiveSettings) {
			elmApp.ports.receiveSettings.send(settings);
		}
	}
}
