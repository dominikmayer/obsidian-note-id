import { IDSidePanelView } from "./view";
import { IDSidePanelSettingTab } from "./settings";
import { OpenNoteModal } from "./openNoteModal";
import { AttachNoteModal } from "./attachNoteModal";
import { ElmApp } from "/.elm";
import { IDSidePanelSettings, DEFAULT_SETTINGS, NoteMeta } from "./types";
import {
	VIEW_TYPE_ID_PANEL,
	ID_FIELD_DEFAULT,
	TOC_TITLE_FIELD_DEFAULT,
} from "./constants";
import { Plugin, Notice, TAbstractFile, TFile, WorkspaceLeaf } from "obsidian";

export default class IDSidePanelPlugin extends Plugin {
	settings: IDSidePanelSettings;
	noteCache: Map<string, NoteMeta> = new Map();
	private rawMetadata: Array<{
		path: string;
		basename: string;
		frontmatter: Array<[string, string]> | null;
	}> = [];

	async extractRawFileMeta(file: TFile): Promise<{
		path: string;
		basename: string;
		frontmatter: Array<[string, string]> | null;
	}> {
		const cache = this.app.metadataCache.getFileCache(file);
		let frontmatter = null;

		if (cache?.frontmatter && typeof cache.frontmatter === "object") {
			// Convert frontmatter object to array of key/value pairs with string values for Elm
			frontmatter = Object.entries(cache.frontmatter).map(
				([key, value]) => {
					// Convert all values to strings for simplicity
					const stringValue =
						value === null
							? ""
							: typeof value === "object"
								? JSON.stringify(value)
								: String(value);
					return [key, stringValue] as [string, string];
				},
			);
		}

		return {
			path: file.path,
			basename: file.basename,
			frontmatter,
		};
	}

	async initializeCache() {
		this.noteCache.clear();
		const markdownFiles = this.app.vault.getMarkdownFiles();

		// Extract raw metadata from all files
		const metaPromises = markdownFiles.map((file) =>
			this.extractRawFileMeta(file),
		);
		this.rawMetadata = await Promise.all(metaPromises); // Parallel processing

		// The raw metadata will be sent to Elm when refreshView is called
	}

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

		this.app.workspace.onLayoutReady(async () => {
			await this.initializeCache();
			this.refreshView();
		});

		this.registerEvents();
		this.addCommands();
	}

	private registerEvents() {
		this.registerEvent(
			this.app.vault.on("modify", async (file) => {
				await this.handleFileChange(file);
			}),
		);

		this.registerEvent(
			this.app.vault.on("rename", async (file, oldPath) => {
				this.noteCache.delete(oldPath);
				await this.handleFileChange(file);
				// Sending this after the files are reloaded so scrolling works
				const elmApp = this.getElmApp();
				if (elmApp && elmApp.ports.receiveFileRenamed) {
					elmApp.ports.receiveFileRenamed.send([oldPath, file.path]);
				}
			}),
		);

		this.registerEvent(
			this.app.vault.on("delete", async (file) => {
				if (file instanceof TFile && file.extension === "md") {
					// Update our cached raw metadata
					this.rawMetadata = this.rawMetadata.filter(
						(item) => item.path !== file.path,
					);

					const elmApp = this.getElmApp();
					if (elmApp && elmApp.ports.receiveFileDeleted) {
						elmApp.ports.receiveFileDeleted.send(file.path);
					}
				}
			}),
		);

		this.registerEvent(
			this.app.metadataCache.on("changed", async (file) => {
				await this.handleFileChange(file);
			}),
		);
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
				new OpenNoteModal(
					this.app,
					this.settings.idField || ID_FIELD_DEFAULT,
					this.settings.tocField || TOC_TITLE_FIELD_DEFAULT,
					this.noteCache,
				).open();
			},
		});

		this.addCommand({
			id: "attach-note",
			name: "Set note ID based on another note",
			callback: () => {
				this.ensureActiveNoteAndElmApp((elmApp, currentNote) => {
					new AttachNoteModal(
						this.app,
						this.settings.idField || ID_FIELD_DEFAULT,
						this.settings.tocField || TOC_TITLE_FIELD_DEFAULT,
						this.noteCache,
						currentNote,
						elmApp,
					).open();
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
		callback: (elmApp: ElmApp, file: TFile) => void,
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

	async handleFileChange(file: TAbstractFile) {
		if (!(file instanceof TFile) || file.extension !== "md") {
			return;
		}

		// Extract raw metadata
		const rawMeta = await this.extractRawFileMeta(file);

		// Update our cached raw metadata
		const index = this.rawMetadata.findIndex(
			(item) => item.path === file.path,
		);
		if (index >= 0) {
			this.rawMetadata[index] = rawMeta;
		} else {
			this.rawMetadata.push(rawMeta);
		}

		// Send the changed file metadata to Elm for processing
		const elmApp = this.getElmApp();
		if (elmApp && elmApp.ports.receiveFileChange) {
			elmApp.ports.receiveFileChange.send(rawMeta);
		}
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
		await this.refreshView();
		return leaf;
	}

	async refreshView() {
		const activePanelView = this.getActivePanelView();
		if (activePanelView) {
			const elmApp = this.getElmApp();

			// Send raw metadata to Elm if it's available and we have metadata to send
			if (
				elmApp &&
				elmApp.ports.receiveRawFileMeta &&
				this.rawMetadata.length > 0
			) {
				elmApp.ports.receiveRawFileMeta.send(this.rawMetadata);
			}
		}
	}

	async saveSettings() {
		await this.saveData(this.settings);
		this.sendSettingsToElm(this.getSettings());
		await this.initializeCache();
		await this.refreshView();
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
			console.log("Sending settings to Elm:", settings);
			elmApp.ports.receiveSettings.send(settings);
		}
	}
}
