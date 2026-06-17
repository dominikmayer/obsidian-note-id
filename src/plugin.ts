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
			callback: async () => {
				await this.activateView();
			},
		});
		this.addCommand({
			id: "create-note-in-sequence",
			name: "Create new note in sequence",
			callback: async () => {
				await this.createNoteFromCommand(false);
			},
		});
		this.addCommand({
			id: "create-note-in-subsequence",
			name: "Create new note in subsequence",
			callback: async () => {
				await this.createNoteFromCommand(true);
			},
		});

		this.addCommand({
			id: "note-search",
			name: "Search notes by title, title of contents title or ID",
			callback: async () => {
				await this.ensurePanelAndElmApp((elmApp) => {
					if (elmApp.ports.receiveRequestSearch) {
						elmApp.ports.receiveRequestSearch.send(null);
					}
				});
			},
		});

		this.addCommand({
			id: "attach-note",
			name: "Set ID based on another note",
			callback: async () => {
				await this.ensureActiveNoteAndElmApp((elmApp, currentNote) => {
					if (elmApp.ports.receiveRequestAttach) {
						elmApp.ports.receiveRequestAttach.send(
							currentNote.path,
						);
					}
				});
			},
		});
	}

	private async createNoteFromCommand(subsequence: boolean): Promise<void> {
		await this.ensureActiveNoteAndElmApp((elmApp, currentNote) => {
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

	private async ensureActiveNoteAndElmApp(
		callback: (elmApp: ElmApp, file: TFile) => void,
	): Promise<void> {
		const currentNote = this.app.workspace.getActiveFile();
		if (!currentNote) {
			new Notice("No active note");
			return;
		}
		await this.ensurePanelAndElmApp((elmApp) => {
			callback(elmApp, currentNote);
		});
	}

	private async ensurePanelAndElmApp(
		callback: (elmApp: ElmApp) => void,
	): Promise<void> {
		const panelView = await this.getOrCreateActivePanelView();
		if (!panelView) {
			new Notice("Failed to open the side panel");
			return;
		}

		try {
			const elmApp = await this.waitForElmApp();
			callback(elmApp);
		} catch {
			new Notice("Please try again");
		}
	}

	private waitForElmApp(retries = 10, delay = 200): Promise<ElmApp> {
		return new Promise((resolve, reject) => {
			const checkElmApp = () => {
				const elmApp = this.getElmApp();
				if (elmApp) {
					resolve(elmApp);
				} else if (retries > 0) {
					window.setTimeout(() => checkElmApp(), delay);
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
		await this.app.workspace.revealLeaf(leaf);
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
