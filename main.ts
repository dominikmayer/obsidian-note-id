import {
	App,
	ItemView,
	Plugin,
	Notice,
	TAbstractFile,
	TFile,
	WorkspaceLeaf,
	Menu,
	normalizePath,
	setIcon,
} from "obsidian";
import { Elm } from "./Main.elm";

const VIEW_TYPE_ID_PANEL = "id-side-panel";
const ID_FIELD_DEFAULT = "id";
const TOC_TITLE_FIELD_DEFAULT = "toc";

interface IDSidePanelSettings {
	includeFolders: string[];
	excludeFolders: string[];
	showNotesWithoutId: boolean;
	idField: string;
	tocField: string;
	autoToc: boolean;
	tocLevel: number;
	splitLevel: number;
	indentation: boolean;
}

const DEFAULT_SETTINGS: IDSidePanelSettings = {
	includeFolders: [],
	excludeFolders: [],
	showNotesWithoutId: true,
	idField: "",
	tocField: "",
	autoToc: true,
	tocLevel: 1,
	splitLevel: 0,
	indentation: false,
};

interface NoteMeta {
	title: string;
	tocTitle: string | null;
	id: string | number | null;
	file: TFile;
}

class IDSidePanelView extends ItemView {
	plugin: IDSidePanelPlugin;
	// private virtualList: VirtualList;

	constructor(leaf: WorkspaceLeaf, plugin: IDSidePanelPlugin) {
		super(leaf);
		this.plugin = plugin;
	}

	private elmApp: any | null = null;

	getViewType() {
		return VIEW_TYPE_ID_PANEL;
	}
	getDisplayText() {
		return "Notes by ID";
	}

	async onOpen() {
		const container = this.containerEl.children[1] as HTMLElement;
		container.empty();

		const header = container.createDiv("nav-header");
		const toolbar = header.createDiv("nav-buttons-container");
		const tocButton = toolbar.createDiv("clickable-icon nav-action-button");
		setIcon(tocButton, "table-of-contents");
		tocButton.addEventListener("click", () => {
			const tocShown = tocButton.classList.toggle("is-active");
			if (this.elmApp && this.elmApp.ports.receiveDisplayIsToc) {
				this.elmApp.ports.receiveDisplayIsToc.send(tocShown);
			}
		});

		const elmContainer = container.createDiv();

		const activeFile = this.app.workspace.getActiveFile();

		this.elmApp = Elm.Main.init({
			node: elmContainer,
			flags: {
				settings: this.plugin.settings,
				activeFile: activeFile ? activeFile.path : null,
			},
		});

		this.elmApp.ports.openFile.subscribe((filePath: string) => {
			const file = this.app.vault.getAbstractFileByPath(
				normalizePath(filePath),
			);
			if (file instanceof TFile) {
				const leaf = this.app.workspace.getLeaf();
				leaf.openFile(file);
			}
		});

		this.elmApp.ports.createNote.subscribe(
			async ([filePath, content]: [string, string]) => {
				const uniqueFilePath = this.getUniqueFilePath(
					normalizePath(filePath),
				);
				const file = await this.app.vault.create(
					uniqueFilePath,
					content,
				);
				if (file instanceof TFile) {
					const leaf = this.app.workspace.getLeaf();
					leaf.openFile(file);
				}
			},
		);

		this.elmApp.ports.openContextMenu.subscribe(
			([x, y, filePath]: [number, number, string]) => {
				const file = this.app.vault.getAbstractFileByPath(
					normalizePath(filePath),
				);
				if (!file) return;

				const menu = new Menu();

				menu.addItem((item) =>
					item
						.setSection("action")
						.setTitle("Create new note in sequence")
						.setIcon("list-plus")
						.onClick(() => {
							if (
								this.elmApp &&
								this.elmApp.ports.receiveCreateNote
							) {
								this.elmApp.ports.receiveCreateNote.send([
									filePath,
									false,
								]);
							}
						}),
				);
				menu.addItem((item) =>
					item
						.setSection("action")
						.setTitle("Create new note in subsequence")
						.setIcon("list-tree")
						.onClick(() => {
							if (
								this.elmApp &&
								this.elmApp.ports.receiveCreateNote
							) {
								this.elmApp.ports.receiveCreateNote.send([
									filePath,
									true,
								]);
							}
						}),
				);
				menu.addSeparator();

				this.app.workspace.trigger(
					"file-menu",
					menu,
					file,
					"note-id-context-menu",
				);

				menu.showAtPosition({ x: x, y: y });
			},
		);

		this.registerEvent(
			this.app.workspace.on("file-open", (file) => {
				if (this.elmApp && this.elmApp.ports.receiveFileOpen) {
					const filePath = file?.path || null;
					this.elmApp.ports.receiveFileOpen.send(filePath);
				}
			}),
		);
		this.renderNotes();
	}

	getUniqueFilePath(path: string) {
		let counter = 1;
		const ext = path.includes(".")
			? path.substring(path.lastIndexOf("."))
			: "";
		const baseName = path.replace(ext, "");
		let uniquePath = path;

		while (
			this.app.vault.getAbstractFileByPath(normalizePath(uniquePath))
		) {
			uniquePath = `${baseName} (${counter})${ext}`;
			counter++;
		}

		return uniquePath;
	}

	getElmApp() {
		return this.elmApp;
	}

	renderNotes(changedFiles: string[] = []) {
		const { showNotesWithoutId } = this.plugin.settings;
		const allNotes = Array.from(this.plugin.noteCache.values());

		const notesWithID = allNotes
			.filter((n) => n.id !== null)
			.sort((a, b) => {
				if (a.id === null) return 1;
				if (b.id === null) return -1;
				return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
			});

		const notesWithoutID = allNotes
			.filter((n) => n.id === null)
			.sort((a, b) => a.title.localeCompare(b.title));

		let combined: NoteMeta[] = [];
		combined = combined.concat(notesWithID);
		if (showNotesWithoutId) {
			combined = combined.concat(notesWithoutID);
		}

		if (
			this.elmApp &&
			this.elmApp.ports &&
			this.elmApp.ports.receiveNotes
		) {
			const notes = combined.map((note) => ({
				title: note.title,
				tocTitle: note.tocTitle,
				id: note.id ? note.id.toString() : null, // Convert Maybe to a string
				filePath: note.file.path,
			}));

			this.elmApp.ports.receiveNotes.send([notes, changedFiles]);
		}
	}
}

export default class IDSidePanelPlugin extends Plugin {
	private scheduleRefreshTimeout: number | null = null;
	settings: IDSidePanelSettings;
	noteCache: Map<string, NoteMeta> = new Map();

	private getActivePanelView() {
		const leaves = this.app.workspace.getLeavesOfType(VIEW_TYPE_ID_PANEL);
		if (leaves.length > 0) {
			const view = leaves[0].view;
			if (view instanceof IDSidePanelView) {
				return view;
			}
		}
		return null;
	}

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
			const frontmatter: Record<
				string,
				string | number | boolean | null
			> = cache?.frontmatter ?? {};
			const frontmatterKeys = Object.keys(frontmatter).reduce(
				(acc, key) => {
					acc[key.toLowerCase()] = frontmatter[key];
					return acc;
				},
				{} as Record<string, any>,
			);
			const normalizedIdField = idField.toLowerCase() || ID_FIELD_DEFAULT;
			id = frontmatterKeys[normalizedIdField] ?? null;

			const normalizedTocTitleField =
				tocField.toLowerCase() || TOC_TITLE_FIELD_DEFAULT;
			tocTitle = frontmatterKeys[normalizedTocTitleField] ?? null;
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
	}

	private createNoteFromCommand(subsequence: boolean) {
		const elmApp = this.getElmApp();
		const currentNote = this.app.workspace.getActiveFile();
		if (!currentNote) {
			new Notice("No active file");
			return;
		}
		if (currentNote && elmApp && elmApp.ports.receiveCreateNote) {
			elmApp.ports.receiveCreateNote.send([
				currentNote.path,
				subsequence,
			]);
		} else {
			new Notice("Please open the side panel first");
		}
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

	async activateView() {
		let leaf = this.app.workspace.getLeavesOfType(VIEW_TYPE_ID_PANEL)[0];

		if (!leaf) {
			leaf =
				this.app.workspace.getRightLeaf(false) ??
				this.app.workspace.getLeaf(true);
			await leaf.setViewState({
				type: VIEW_TYPE_ID_PANEL,
				active: true,
			});
		}

		this.app.workspace.revealLeaf(leaf);
		await this.refreshView();
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

// Settings
import { PluginSettingTab, Setting } from "obsidian";

class IDSidePanelSettingTab extends PluginSettingTab {
	plugin: IDSidePanelPlugin;

	constructor(app: App, plugin: IDSidePanelPlugin) {
		super(app, plugin);
		this.plugin = plugin;
	}

	display(): void {
		const { containerEl } = this;
		containerEl.empty();

		new Setting(containerEl)
			.setName("ID property")
			.setDesc(
				"Define the frontmatter field used as the ID (case-insensitive).",
			)
			.addText((text) =>
				text
					.setPlaceholder(ID_FIELD_DEFAULT)
					.setValue(this.plugin.settings.idField)
					.onChange(async (value) => {
						this.plugin.settings.idField = value.trim();
						await this.plugin.saveSettings();
					}),
			);
		new Setting(containerEl)
			.setName("Table of contents title property")
			.setDesc(
				"Define the frontmatter field used as the title shown in the table of contents (case-insensitive).",
			)
			.addText((text) =>
				text
					.setPlaceholder(TOC_TITLE_FIELD_DEFAULT)
					.setValue(this.plugin.settings.tocField)
					.onChange(async (value) => {
						this.plugin.settings.tocField = value.trim();
						await this.plugin.saveSettings();
					}),
			);
		new Setting(containerEl)
			.setName("Include folders")
			.setDesc(
				"Only include notes from these folders. Leave empty to include all.",
			)
			.addTextArea((text) =>
				text
					.setPlaceholder("e.g., folder1, folder2")
					.setValue(this.plugin.settings.includeFolders.join(", "))
					.onChange(async (value) => {
						this.plugin.settings.includeFolders = value
							.split(",")
							.map((v) => v.trim())
							.filter((v) => v !== "")
							.map((v) => normalizePath(v));
						await this.plugin.saveSettings();
					}),
			);

		new Setting(containerEl)
			.setName("Exclude folders")
			.setDesc("Exclude notes from these folders.")
			.addTextArea((text) =>
				text
					.setPlaceholder("e.g., folder1, folder2")
					.setValue(this.plugin.settings.excludeFolders.join(", "))
					.onChange(async (value) => {
						this.plugin.settings.excludeFolders = value
							.split(",")
							.map((v) => v.trim())
							.filter((v) => v !== "")
							.map((v) => normalizePath(v));
						await this.plugin.saveSettings();
					}),
			);

		new Setting(containerEl)
			.setName("Show notes without ID")
			.setDesc("Toggle the display of notes without IDs.")
			.addToggle((toggle) =>
				toggle
					.setValue(this.plugin.settings.showNotesWithoutId)
					.onChange(async (value) => {
						this.plugin.settings.showNotesWithoutId = value;
						await this.plugin.saveSettings();
					}),
			);

		containerEl.createEl("br");
		const appearanceSection = containerEl.createEl("div", {
			cls: "setting-item setting-item-heading",
		});
		const appearanceSectionInfo = appearanceSection.createEl("div", {
			cls: "setting-item-info",
		});
		appearanceSectionInfo.createEl("div", {
			text: "Display",
			cls: "setting-item-name",
		});

		new Setting(containerEl)
			.setName("Automatically include notes in table of contents")
			.setDesc(
				"If enabled, notes will be included in the table of contents based on their hierarchy level. " +
					"If disabled, only notes with a 'toc' property will be shown.",
			)
			.addToggle((toggle) =>
				toggle
					.setValue(this.plugin.settings.autoToc)
					.onChange(async (value) => {
						this.plugin.settings.autoToc = value;
						await this.plugin.saveSettings();
						this.display();
					}),
			);
		new Setting(containerEl)
			.setName("Table of contents level")
			.setDesc(
				"Defines which hierarchy level of notes should be included in the table of contents. " +
					"A value of 1 includes only top-level notes, 2 includes sub-levels, and so on. " +
					"Notes with a 'toc' property are always included.",
			)
			.addSlider((slider) =>
				slider
					.setLimits(1, 10, 1)
					.setValue(this.plugin.settings.tocLevel)
					.setDynamicTooltip()
					.setDisabled(!this.plugin.settings.autoToc)
					.onChange(async (value) => {
						this.plugin.settings.tocLevel = value;
						await this.plugin.saveSettings();
					}),
			);

		new Setting(containerEl)
			.setName(
				"Only show notes with a 'toc' property in the table of contents",
			)
			.setDesc(
				"If enabled, only notes with a 'toc' property will be shown in the table of contents.",
			)
			.addToggle((toggle) =>
				toggle
					.setValue(this.plugin.settings.tocOnly)
					.onChange(async (value) => {
						this.plugin.settings.tocOnly = value;
						await this.plugin.saveSettings();
					}),
			);

		new Setting(containerEl)
			.setName("Hierarchy split level")
			.setDesc(
				"Defines how notes are visually grouped based on ID hierarchy. " +
					"A value of 1 separates top-level IDs (e.g., 1 vs. 2). " +
					"A value of 2 adds an additional split between sub-levels (e.g., 1.1 vs. 1.2), and so on.",
			)
			.addSlider((slider) =>
				slider
					.setLimits(0, 10, 1)
					.setValue(this.plugin.settings.splitLevel)
					.setDynamicTooltip()
					.onChange(async (value) => {
						this.plugin.settings.splitLevel = value;
						await this.plugin.saveSettings();
					}),
			);

		new Setting(containerEl)
			.setName("Indent notes")
			.setDesc("Indents notes based on their id level.")
			.addToggle((toggle) =>
				toggle
					.setValue(this.plugin.settings.indentation)
					.onChange(async (value) => {
						this.plugin.settings.indentation = value;
						await this.plugin.saveSettings();
					}),
			);
	}
}
