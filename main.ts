import { App, ItemView, Plugin, setIcon, TAbstractFile, TFile, Vault, WorkspaceLeaf } from 'obsidian';

const VIEW_TYPE_ID_PANEL = 'id-side-panel';

interface IDSidePanelSettings {
    includeFolders: string[];
    excludeFolders: string[];
    showNotesWithoutID: boolean;
    customIDField: string;
}

const DEFAULT_SETTINGS: IDSidePanelSettings = {
    includeFolders: [],
    excludeFolders: [],
    showNotesWithoutID: true,
    customIDField: '',
};

interface NoteMeta { title: string; id: string | number | null; file: TFile; }

class IDSidePanelView extends ItemView {
    plugin: IDSidePanelPlugin;

    constructor(leaf: WorkspaceLeaf, plugin: IDSidePanelPlugin) {
        super(leaf);
        this.plugin = plugin;
    }

    getViewType() {
        return VIEW_TYPE_ID_PANEL;
    }

    getDisplayText() {
        return 'Notes by ID';
    }

    async onOpen() {
        const container = this.containerEl.children[1] as HTMLElement;
        container.empty();

        this.renderNotes(container);

		this.registerEvent(
			this.app.workspace.on('file-open', async (file) => {
				if (file instanceof TFile && file.extension === 'md') {
					await this.refresh();
				}
			})
		);
    }

    async renderNotes(container: HTMLElement) {
        const { showNotesWithoutID } = this.plugin.settings;
        const allNotes = Array.from(this.plugin.noteCache.values());
    
        const notesWithID: NoteMeta[] = [];
        const notesWithoutID: NoteMeta[] = [];
        for (const note of allNotes) {
            if (note.id !== null) {
                notesWithID.push(note);
            } else if (showNotesWithoutID) {
                notesWithoutID.push(note);
            }
        }
    
        // Sorting remains the same
        notesWithID.sort((a, b) => {
            if (a.id === null) return 1;
            if (b.id === null) return -1;
            if (a.id < b.id) return -1;
            if (a.id > b.id) return 1;
            return 0;
        });
    
        notesWithoutID.sort((a, b) => a.title.localeCompare(b.title));
    
        // Create a container for notes with IDs
        const listElWithID = container.createEl('div');
        const activeFile = this.app.workspace.getActiveFile();
        for (const note of notesWithID) {
            const listItem = listElWithID.createEl('div');
            listItem.addClass('tree-item');
    
            const titleItem = listItem.createEl('div');
            titleItem.addClasses(['tree-item-self', 'is-clickable']);
    
            const iconItem = titleItem.createEl('div');
            setIcon(iconItem, 'file');
            iconItem.addClass('tree-item-icon');
    
            const nameItem = titleItem.createEl('div');
            nameItem.addClass('tree-item-inner');
            const idPart = nameItem.createEl('span', { text: `${note.id}: ` });
            idPart.addClass('note-id');
            const namePart = nameItem.createEl('span', { text: `${note.title}` });
    
            if (activeFile && activeFile.path === note.file.path) {
                titleItem.addClass('is-active');
            }
    
            listItem.addEventListener('click', () => {
                const leaf = this.app.workspace.getLeaf();
                leaf.openFile(note.file);
            });
        }

        if (notesWithID.length > 0 && showNotesWithoutID && notesWithoutID.length > 0) {
            container.createEl('hr');
        }
        
        if (showNotesWithoutID) {
            const listElWithoutID = container.createEl('div');
            for (const note of notesWithoutID) {
                const listItem = listElWithoutID.createEl('div');
                listItem.addClass('tree-item');
        
                const titleItem = listItem.createEl('div');
                titleItem.addClasses(['tree-item-self', 'is-clickable']);
        
                const iconItem = titleItem.createEl('div');
                setIcon(iconItem, 'file-question');
                iconItem.addClass('tree-item-icon');
        
                const nameItem = titleItem.createEl('div');
                nameItem.addClass('tree-item-inner');
                const namePart = nameItem.createEl('span', { text: `${note.title}` });
        
                if (activeFile && activeFile.path === note.file.path) {
                    titleItem.addClass('is-active');
                }
        
                listItem.addEventListener('click', () => {
                    const leaf = this.app.workspace.getLeaf();
                    leaf.openFile(note.file);
                });
            }
        }
    }

	public async refresh() {
        if ('requestIdleCallback' in window) {
            requestIdleCallback(() => this.refreshNotes());
        } else {
            this.refreshNotes()
        }
    }

    private async refreshNotes() {
        const container = this.containerEl.children[1] as HTMLElement;
        container.empty();
        this.renderNotes(container);
    }
}

export default class IDSidePanelPlugin extends Plugin {
    private activePanelView: IDSidePanelView | null = null;
    settings: IDSidePanelSettings;
    noteCache: Map<string, NoteMeta> = new Map();

    async extractNoteMeta(file: TFile): Promise<NoteMeta | null> {
        const { includeFolders, excludeFolders, showNotesWithoutID, customIDField } = this.settings;
        const filePath = file.path.toLowerCase();
        const included =
          includeFolders.length === 0 ||
          includeFolders.some((folder) => filePath.startsWith(folder.toLowerCase()));
        const excluded = excludeFolders.some((folder) =>
          filePath.startsWith(folder.toLowerCase())
        );
        if (!included || excluded) return null;
    
        const cache = this.app.metadataCache.getFileCache(file);
        let id = null;
        if (cache?.frontmatter && typeof cache.frontmatter === 'object') {
          const frontmatter = cache.frontmatter as Record<string, any>;
          const frontmatterKeys = Object.keys(frontmatter).reduce((acc, key) => {
            acc[key.toLowerCase()] = frontmatter[key];
            return acc;
          }, {} as Record<string, any>);
          const idField = customIDField.toLowerCase() || 'id';
          id = frontmatterKeys[idField] ?? null;
        }
        // Optionally filter out notes without ID if not showing them
        if (id === null && !showNotesWithoutID) return null;
        return { title: file.basename, id, file };
      }

      async initializeCache() {
        const markdownFiles = this.app.vault.getMarkdownFiles();
        for (const file of markdownFiles) {
          const meta = await this.extractNoteMeta(file);
          if (meta) this.noteCache.set(file.path, meta);
        }
      }

    async onload() {

        this.settings = Object.assign({}, DEFAULT_SETTINGS, await this.loadData());
        await this.initializeCache();
        this.addSettingTab(new IDSidePanelSettingTab(this.app, this));

        this.registerView(
            VIEW_TYPE_ID_PANEL,
            (leaf) => {
                const view = new IDSidePanelView(leaf, this);
				view.icon = 'file-digit'
                this.activePanelView = view;
                return view;
            }
        );

        // Add a ribbon icon and command to open the panel
        this.addRibbonIcon('file-digit', 'Open side panel', () => this.activateView());
        this.addCommand({
            id: 'open-id-side-panel',
            name: 'Open side panel',
            callback: () => this.activateView(),
        });

        // Listen to file changes and metadata changes
        this.registerEvent(
            this.app.vault.on('modify', async (file) => {
                await this.handleFileChange(file);
            })
        );

        this.registerEvent(
            this.app.vault.on('rename', async (file) => {
                await this.handleFileChange(file);
            })
        );

        this.registerEvent(
            this.app.metadataCache.on('changed', async (file) => {
                await this.handleFileChange(file);
            })
        );
    }

    async handleFileChange(file: TAbstractFile) {
        if (file instanceof TFile && file.extension === 'md') {
            // Remove any cache entries for the same file object but under a different key
            for (const [path, meta] of this.noteCache.entries()) {
                if (meta.file === file && path !== file.path) {
                    this.noteCache.delete(path);
                }
            }
    
            const meta = await this.extractNoteMeta(file);
            if (meta) {
                this.noteCache.set(file.path, meta);
            } else {
                this.noteCache.delete(file.path);
            }
            await this.refreshView();
        }
    }

	async activateView() {
		// Get the right leaf or create one if it doesn't exist
		let leaf = this.app.workspace.getRightLeaf(false);
	
		if (!leaf) {
			// Use getLeaf() to create a new leaf
			leaf = this.app.workspace.getLeaf(true);
		}
	
		// Set the view state for the leaf
		await leaf.setViewState({
			type: VIEW_TYPE_ID_PANEL,
			active: true,
		});
	
		// Reveal the leaf to make it active
		this.app.workspace.revealLeaf(leaf);
	}

    async refreshView() {
        if (this.activePanelView) {
            await this.activePanelView.refresh();
        } else {
            // If the panel isn't open, reopen it to ensure consistency
            await this.activateView();
        }
    }

    async saveSettings() {
        await this.saveData(this.settings);
    }
}

// Settings
import { PluginSettingTab, Setting } from 'obsidian';

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
            .setName('ID property')
            .setDesc('Define the frontmatter field used as the ID (case-insensitive).')
            .addText((text) =>
                text
                    .setPlaceholder('ID')
                    .setValue(this.plugin.settings.customIDField)
                    .onChange(async (value) => {
                        this.plugin.settings.customIDField = value.trim();
                        await this.plugin.saveSettings();
                        await this.plugin.refreshView();
                    })
            );
        new Setting(containerEl)
            .setName('Include folders')
            .setDesc('Only include notes from these folders. Leave empty to include all.')
            .addTextArea((text) =>
                text
                    .setPlaceholder('e.g., folder1, folder2')
                    .setValue(this.plugin.settings.includeFolders.join(', '))
                    .onChange(async (value) => {
                        this.plugin.settings.includeFolders = value
                            .split(',')
                            .map((v) => v.trim())
                            .filter((v) => v !== '');
                        await this.plugin.saveSettings();
                        await this.plugin.refreshView();
                    })
            );

        new Setting(containerEl)
            .setName('Exclude folders')
            .setDesc('Exclude notes from these folders.')
            .addTextArea((text) =>
                text
                    .setPlaceholder('e.g., folder1, folder2')
                    .setValue(this.plugin.settings.excludeFolders.join(', '))
                    .onChange(async (value) => {
                        this.plugin.settings.excludeFolders = value
                            .split(',')
                            .map((v) => v.trim())
                            .filter((v) => v !== '');
                        await this.plugin.saveSettings();
                        await this.plugin.refreshView();
                    })
            );

        new Setting(containerEl)
            .setName('Show notes without ID')
            .setDesc('Toggle the display of notes without IDs.')
            .addToggle((toggle) =>
                toggle
                    .setValue(this.plugin.settings.showNotesWithoutID)
                    .onChange(async (value) => {
                        this.plugin.settings.showNotesWithoutID = value;
                        await this.plugin.saveSettings();
                        await this.plugin.refreshView();
                    })
            );
    }
}