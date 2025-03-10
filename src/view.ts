import {
	ItemView,
	TFile,
	WorkspaceLeaf,
	Menu,
	Notice,
	normalizePath,
	setIcon,
} from "obsidian";
import IDSidePanelPlugin from "../main";
import { VIEW_TYPE_ID_PANEL } from "./constants";
import { Elm, ElmApp } from "./Main.elm";
import { OpenNoteModal } from "./openNoteModal";
import { AttachNoteModal } from "./attachNoteModal";
import { NoteMeta } from "./types";
import { PortNoteMeta } from "/.elm";

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
				settings: this.plugin.getSettings(),
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

		this.registerEvent(
			this.app.workspace.on("file-open", (file) => {
				if (this.elmApp && this.elmApp.ports.receiveFileOpen) {
					const filePath = file?.path || null;
					this.elmApp.ports.receiveFileOpen.send(filePath);
				}
			}),
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

	mapPortNoteMeta(notes: PortNoteMeta[]): Map<string, NoteMeta> {
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
}
