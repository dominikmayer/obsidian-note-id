import { IDSidePanelView } from "./view";
import { IDSidePanelSettingTab } from "./settings";
import { OpenNoteModal } from "./openNoteModal";
import { ElmApp } from "/.elm";
import {
	IDSidePanelSettings,
	DEFAULT_SETTINGS,
	NoteMeta,
	FrontmatterValue,
} from "./types";
import {
	VIEW_TYPE_ID_PANEL,
	ID_FIELD_DEFAULT,
	TOC_TITLE_FIELD_DEFAULT,
} from "./constants";
import { Plugin, Notice, TAbstractFile, TFile, WorkspaceLeaf } from "obsidian";

export default class IDSidePanelPlugin extends Plugin {
	private scheduleRefreshTimeout: number | null = null;
	settings: IDSidePanelSettings;
	noteCache: Map<string, NoteMeta> = new Map();

	async extractNoteMeta(file: TFile): Promise<NoteMeta | null> {
		const {
			includeFolders,
			excludeFolders,
			showNotesWithoutId,
			idField,
			tocField,
		} = this.settings;
		const filePath = file.path.toLowerCase();

		// Normalize folder paths to remove trailing slashes and lower case them
		const normInclude = includeFolders.map((f) =>
			f.replace(/\/+$/, "").toLowerCase(),
		);
		const normExclude = excludeFolders.map((f) =>
			f.replace(/\/+$/, "").toLowerCase(),
		);

		const included =
			normInclude.length === 0 ||
			normInclude.some((folder) => filePath.startsWith(folder + "/"));
		const excluded = normExclude.some((folder) =>
			filePath.startsWith(folder + "/"),
		);

		if (!included || excluded) return null;

		const cache = this.app.metadataCache.getFileCache(file);
		let id = null;
		let tocTitle = null;
		if (cache?.frontmatter && typeof cache.frontmatter === "object") {
			const frontmatter: Record<string, FrontmatterValue> =
				cache?.frontmatter ?? {};
			const frontmatterKeys = Object.keys(frontmatter).reduce<
				Record<string, FrontmatterValue>
			>((acc, key) => {
				acc[key.toLowerCase()] = frontmatter[key];
				return acc;
			}, {});
			const normalizedIdField = idField.toLowerCase() || ID_FIELD_DEFAULT;
			id =
				frontmatterKeys[normalizedIdField] != null
					? String(frontmatterKeys[normalizedIdField])
					: null;

			const normalizedTocTitleField =
				tocField.toLowerCase() || TOC_TITLE_FIELD_DEFAULT;
			tocTitle =
				frontmatterKeys[normalizedTocTitleField] != null
					? String(frontmatterKeys[normalizedTocTitleField])
					: null;
		}

		if (id === null && !showNotesWithoutId) return null;

		return { title: file.basename, tocTitle, id, file };
	}

	async initializeCache() {
		this.noteCache.clear();
		const markdownFiles = this.app.vault.getMarkdownFiles();

		const metaPromises = markdownFiles.map((file) =>
			this.extractNoteMeta(file),
		);
		const metaResults = await Promise.all(metaPromises); // Parallel processing

		metaResults.forEach((meta, index) => {
			if (meta) this.noteCache.set(markdownFiles[index].path, meta);
		});
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
					if (this.noteCache.has(file.path)) {
						this.noteCache.delete(file.path);
						this.queueRefresh();
					}
				}
			}),
		);

		this.registerEvent(
			this.app.metadataCache.on("changed", async (file) => {
				await this.handleFileChange(file);
			}),
		);

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
	}

	private createNoteFromCommand(subsequence: boolean) {
		const currentNote = this.app.workspace.getActiveFile();
		if (!currentNote) {
			new Notice("No active file");
			return;
		}

		this.getOrCreateActivePanelView().then((panelView) => {
			if (!panelView) {
				new Notice("Failed to open the side panel");
				return;
			}

			// Wait for Elm app to load before proceeding
			this.waitForElmApp().then((elmApp) => {
				if (elmApp && elmApp.ports.receiveCreateNote) {
					elmApp.ports.receiveCreateNote.send([
						currentNote.path,
						subsequence,
					]);
				} else {
					new Notice("Please try again");
				}
			});
		});
	}

	async handleFileChange(file: TAbstractFile) {
		if (file instanceof TFile && file.extension === "md") {
			const newMeta = await this.extractNoteMeta(file);

			if (!newMeta) {
				// If the file is not relevant but was previously cached, remove it
				if (this.noteCache.has(file.path)) {
					this.noteCache.delete(file.path);
					this.queueRefresh();
				}
				return;
			}

			const oldMeta = this.noteCache.get(file.path);

			const metaChanged =
				!oldMeta ||
				newMeta.id !== oldMeta.id ||
				newMeta.title !== oldMeta.title ||
				newMeta.tocTitle !== oldMeta.tocTitle;

			if (metaChanged) {
				this.noteCache.set(file.path, newMeta);
				this.queueRefresh([file.path]);
			}
		}
	}

	private queueRefresh(changedFiles: string[] = []): void {
		if (this.scheduleRefreshTimeout) {
			clearTimeout(this.scheduleRefreshTimeout);
		}
		this.scheduleRefreshTimeout = window.setTimeout(() => {
			this.scheduleRefreshTimeout = null;
			const activePanelView = this.getActivePanelView();
			if (activePanelView) activePanelView.renderNotes(changedFiles);
		}, 50);
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
			activePanelView.renderNotes();
		}
	}

	async saveSettings() {
		await this.saveData(this.settings);
		this.sendSettingsToElm(this.settings);
		await this.initializeCache();
		await this.refreshView();
	}

	private sendSettingsToElm(settings: IDSidePanelSettings) {
		const elmApp = this.getElmApp();
		if (elmApp && elmApp.ports.receiveSettings) {
			elmApp.ports.receiveSettings.send(settings);
		}
	}
}
