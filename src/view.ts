import {
	ItemView,
	TFile,
	WorkspaceLeaf,
	Menu,
	normalizePath,
	setIcon,
} from "obsidian";
import IDSidePanelPlugin from "../main";
import { VIEW_TYPE_ID_PANEL } from "./constants";
import { NoteMeta } from "./types";
import { Elm, ElmApp } from "./Main.elm";

export class IDSidePanelView extends ItemView {
	plugin: IDSidePanelPlugin;

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

		this.registerEvent(
			this.app.workspace.on("file-open", (file) => {
				if (this.elmApp && this.elmApp.ports.receiveFileOpen) {
					const filePath = file?.path || null;
					this.elmApp.ports.receiveFileOpen.send(filePath);
				}
			}),
		);
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
