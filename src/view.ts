import {
	ItemView,
	TAbstractFile,
	TFile,
	WorkspaceLeaf,
	Menu,
	Notice,
	normalizePath,
	setIcon,
} from "obsidian";
import IDSidePanelPlugin from "../main";
import { VIEW_TYPE_ID_PANEL } from "./constants";
import { Elm, ElmApp } from "./NoteId.elm";
import { OpenNoteModal } from "./openNoteModal";
import { AttachNoteModal } from "./attachNoteModal";
import { NoteMeta } from "./types";
import { PortNoteMeta } from "/.elm";

export class IDSidePanelView extends ItemView {
	plugin: IDSidePanelPlugin;
	private rawMetadata: Array<{
		path: string;
		basename: string;
		frontmatter: Array<[string, string]> | null;
	}> = [];

	constructor(leaf: WorkspaceLeaf, plugin: IDSidePanelPlugin) {
		super(leaf);
		this.plugin = plugin;
	}

	private elmApp: ElmApp | null = null;

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
		this.addSearch(header, toolbar);

		const elmContainer = container.createDiv();

		const activeFile = this.app.workspace.getActiveFile();

		this.elmApp = Elm.NoteId.init({
			node: elmContainer,
			flags: {
				settings: this.plugin.getSettings(),
				activeFile: activeFile ? activeFile.path : null,
			},
		});

		this.initializeCache();

		if (
			this.elmApp &&
			this.elmApp.ports.receiveRawFileMeta &&
			this.rawMetadata.length > 0
		) {
			this.elmApp.ports.receiveRawFileMeta.send(this.rawMetadata);
		}

		this.registerEvents();
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

		this.elmApp.ports.toggleTOCButton.subscribe(
			async (toggled: boolean) => {
				tocButton.classList.toggle("is-active", toggled);
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

		this.elmApp.ports.provideNewIdForNote.subscribe(
			(data: [string, string]) => {
				const id = data[0];
				const filePath = data[1];

				const file = this.app.vault.getAbstractFileByPath(
					normalizePath(filePath),
				);

				if (file instanceof TFile) {
					this.updateId(file, id);
				} else {
					new Notice("Couldn't update note");
				}
			},
		);

		this.elmApp.ports.provideNotesForSearch.subscribe((notes) => {
			new OpenNoteModal(
				this.app,
				this.plugin.getSettings().idField,
				this.plugin.getSettings().tocField,
				this.mapPortNoteMeta(notes),
			).open();
		});

		this.elmApp.ports.provideNotesForAttach.subscribe(
			([currentPath, notes]) => {
				const currentFile = this.app.vault.getAbstractFileByPath(
					normalizePath(currentPath),
				);
				if (currentFile instanceof TFile && this.elmApp) {
					new AttachNoteModal(
						this.app,
						this.plugin.getSettings().idField,
						this.plugin.getSettings().tocField,
						this.mapPortNoteMeta(notes),
						currentFile,
						this.elmApp,
					).open();
				}
			},
		);
	}

	private registerEvents() {
		this.registerEvent(
			this.app.vault.on("modify", async (file) => {
				await this.handleFileChange(file);
			}),
		);

		this.registerEvent(
			this.app.vault.on("rename", async (file, oldPath) => {
				if (this.elmApp && this.elmApp.ports.receiveFileRenamed) {
					this.elmApp.ports.receiveFileRenamed.send([
						oldPath,
						file.path,
					]);
				}
			}),
		);

		this.registerEvent(
			this.app.vault.on("delete", async (file) => {
				if (file instanceof TFile && file.extension === "md") {
					if (this.elmApp && this.elmApp.ports.receiveFileDeleted) {
						this.elmApp.ports.receiveFileDeleted.send(file.path);
					}
				}
			}),
		);

		this.registerEvent(
			this.app.metadataCache.on("changed", async (file) => {
				await this.handleFileChange(file);
			}),
		);

		this.registerEvent(
			this.app.workspace.on("file-open", (file) => {
				const elmApp = this.getElmApp();
				if (elmApp && elmApp.ports.receiveFileOpen) {
					const filePath = file?.path || null;
					elmApp.ports.receiveFileOpen.send(filePath);
				}
			}),
		);
	}

	async handleFileChange(file: TAbstractFile) {
		if (!(file instanceof TFile) || file.extension !== "md") {
			return;
		}

		// Extract raw metadata
		const rawMeta = this.extractRawFileMeta(file);

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

	private addSearch(header: HTMLDivElement, toolbar: HTMLDivElement) {
		const searchButton = toolbar.createDiv(
			"clickable-icon nav-action-button",
		);
		setIcon(searchButton, "search");

		const search = header.createDiv("search-input-container");
		search.style.display = "none"; // Initially hidden

		const searchInput = search.createEl("input");
		searchInput.placeholder = "Enter search term…";
		searchInput.spellcheck = false;
		searchInput.enterKeyHint = "search";
		searchInput.type = "search";

		const searchClearButton = search.createDiv("search-input-clear-button");
		searchClearButton.setText("Clear search");
		setIcon(searchClearButton, "close");

		searchButton.addEventListener("click", () => {
			const isVisible = search.style.display !== "none";
			searchButton.classList.toggle("is-active", !isVisible);
			if (isVisible) {
				search.style.display = "none";
				searchInput.value = "";
				this.handleSearchInputChanged("");
			} else {
				search.style.display = "block";
				searchInput.focus();
			}
		});

		searchInput.addEventListener("input", () => {
			this.handleSearchInputChanged(searchInput.value);
		});

		searchClearButton.addEventListener("click", () => {
			searchInput.value = "";
			searchInput.focus();
			this.handleSearchInputChanged("");
		});
	}

	private handleSearchInputChanged(text: string) {
		console.log("Search input changed:", text);
		if (this.elmApp && this.elmApp.ports.receiveFilter) {
			this.elmApp.ports.receiveFilter.send(
				text.trim() === "" ? null : text,
			);
		}
	}

	private mapPortNoteMeta(notes: PortNoteMeta[]): Map<string, NoteMeta> {
		const noteMap = new Map<string, NoteMeta>();

		notes.forEach((note) => {
			const file = this.app.vault.getAbstractFileByPath(
				normalizePath(note.filePath),
			);
			if (file instanceof TFile) {
				noteMap.set(note.filePath, {
					title: note.title,
					tocTitle: note.tocTitle,
					id: note.id,
					file: file,
				});
			}
		});
		return noteMap;
	}

	private getUniqueFilePath(path: string) {
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

	private async updateId(file: TFile, newValue: string) {
		if (!file) {
			new Notice("Couldn't update note");
			return;
		}
		const idField = this.plugin.getSettings().idField;

		await this.app.fileManager.processFrontMatter(file, (frontmatter) => {
			frontmatter[idField] = newValue;
		});
	}

	private extractRawFileMeta(file: TFile): {
		path: string;
		basename: string;
		frontmatter: Array<[string, string]> | null;
	} {
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

	private initializeCache() {
		this.rawMetadata = this.app.vault
			.getMarkdownFiles()
			.map((file) => this.extractRawFileMeta(file));
	}
}
