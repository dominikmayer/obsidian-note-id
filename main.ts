import { App, ItemView, Plugin, setIcon, setTooltip, TAbstractFile, TFile, Vault, WorkspaceLeaf, Menu, normalizePath } from 'obsidian';
import { Elm } from "./Main.elm";

const VIEW_TYPE_ID_PANEL = 'id-side-panel';

interface IDSidePanelSettings {
    includeFolders: string[];
    excludeFolders: string[];
    showNotesWithoutId: boolean;
    idField: string;
}

const DEFAULT_SETTINGS: IDSidePanelSettings = {
    includeFolders: [],
    excludeFolders: [],
    showNotesWithoutId: true,
    idField: '',
};

interface NoteMeta {
    title: string;
    id: string | number | null;
    file: TFile;
}

const DEFAULT_ROW_HEIGHT = 28;

class IDSidePanelView extends ItemView {
    plugin: IDSidePanelPlugin;
    // private virtualList: VirtualList;

    constructor(leaf: WorkspaceLeaf, plugin: IDSidePanelPlugin) {
        super(leaf);
        this.plugin = plugin;
    }

    getViewType() { return VIEW_TYPE_ID_PANEL; }
    getDisplayText() { return 'Notes by ID'; }

    async onOpen() {
        const container = this.containerEl.children[1] as HTMLElement;
        container.empty();

        const elmContainer = container.createDiv();
        
        const elmApp = Elm.Main.init({
            node: elmContainer,
            flag: this.plugin.settings,
        });
        (this as any).elmApp = elmApp;

        elmApp.ports.openFile.subscribe((filePath: string) => {
            const file = this.app.vault.getAbstractFileByPath(filePath);
            if (file instanceof TFile) {
                const leaf = this.app.workspace.getLeaf();
                leaf.openFile(file);
            }
        });
    
        this.registerEvent(
            this.app.workspace.on('file-open', (file) => {
                if ((this as any).elmApp && (this as any).elmApp.ports.receiveFileOpen) {
                    const filePath = file?.path || null;
                    (this as any).elmApp.ports.receiveFileOpen.send(filePath);
                }
            })
        );
        this.renderNotes();
    }

    getElmApp() {
        return (this as any).elmApp;
    }

    renderNotes() {
        const { showNotesWithoutId } = this.plugin.settings;
        const allNotes = Array.from(this.plugin.noteCache.values());

        const notesWithID = allNotes
            .filter(n => n.id !== null)
            .sort((a, b) => {
                if (a.id === null) return 1;
                if (b.id === null) return -1;
                return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
            });

        const notesWithoutID = allNotes
            .filter(n => n.id === null)
            .sort((a, b) => a.title.localeCompare(b.title));

        let combined: NoteMeta[] = [];
        combined = combined.concat(notesWithID);
        if (showNotesWithoutId) {
            combined = combined.concat(notesWithoutID);
        }

        const elmApp = (this as any).elmApp;
        if (elmApp && elmApp.ports && elmApp.ports.receiveNotes) {
            elmApp.ports.receiveNotes.send(
                combined.map((note, index) => ({
                    title: note.title,
                    id: note.id ? note.id.toString() : null, // Convert Maybe to a string
                    filePath: note.file.path
                }))
            );
        }
    }
}

export default class IDSidePanelPlugin extends Plugin {
    private activePanelView: IDSidePanelView | null = null;
    private scheduleRefreshTimeout: number | null = null;
    settings: IDSidePanelSettings;
    noteCache: Map<string, NoteMeta> = new Map();

    async extractNoteMeta(file: TFile): Promise<NoteMeta | null> {
        const { includeFolders, excludeFolders, showNotesWithoutId, idField } = this.settings;
        const filePath = file.path.toLowerCase();

        // Normalize folder paths to remove trailing slashes and lower case them
        const normInclude = includeFolders.map(f => f.replace(/\/+$/, '').toLowerCase());
        const normExclude = excludeFolders.map(f => f.replace(/\/+$/, '').toLowerCase());

        const included =
            normInclude.length === 0 ||
            normInclude.some((folder) => filePath.startsWith(folder + '/'));
        const excluded = normExclude.some((folder) => filePath.startsWith(folder + '/'));

        if (!included || excluded) return null;

        const cache = this.app.metadataCache.getFileCache(file);
        let id = null;
        if (cache?.frontmatter && typeof cache.frontmatter === 'object') {
            const frontmatter = cache.frontmatter as Record<string, any>;
            const frontmatterKeys = Object.keys(frontmatter).reduce((acc, key) => {
                acc[key.toLowerCase()] = frontmatter[key];
                return acc;
            }, {} as Record<string, any>);
            const normalizedIdField = idField.toLowerCase() || 'id';
            id = frontmatterKeys[normalizedIdField] ?? null;
        }
    
        if (id === null && !showNotesWithoutId) return null;

        return { title: file.basename, id, file };
    }

    async initializeCache() {
        this.noteCache.clear();
        const markdownFiles = this.app.vault.getMarkdownFiles();
        for (const file of markdownFiles) {
            const meta = await this.extractNoteMeta(file);
            if (meta) {
                this.noteCache.set(file.path, meta);
            }
        }
    }

    private getElmApp() {
        return this.activePanelView ? this.activePanelView.getElmApp() : null;
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

        this.addRibbonIcon('file-digit', 'Open side panel', () => this.activateView());
        this.addCommand({
            id: 'open-id-side-panel',
            name: 'Open side panel',
            callback: () => this.activateView(),
        });

        this.registerEvent(
            this.app.vault.on('modify', async (file) => {
                await this.handleFileChange(file);
            })
        );

        this.registerEvent(
            this.app.vault.on('rename', async (file, oldPath) => {
                this.noteCache.delete(oldPath);
                await this.handleFileChange(file);
                // Sending this after the files are reloaded so scrolling works
                const elmApp = this.getElmApp();
                if (elmApp && elmApp.ports.receiveFileRenamed) {
                    elmApp.ports.receiveFileRenamed.send([oldPath, file.path]);
                }
            })
        );

        this.registerEvent(
            this.app.vault.on('delete', async (file) => {
                if (file instanceof TFile && file.extension === 'md') {
                    if (this.noteCache.has(file.path)) {
                        this.noteCache.delete(file.path);
                        this.queueRefresh();
                    }
                }
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
    
            const metaChanged = !oldMeta || 
                                newMeta.id !== oldMeta.id || 
                                newMeta.title !== oldMeta.title;
    
            if (metaChanged) {
                this.noteCache.set(file.path, newMeta);
                this.queueRefresh();
            }
        }
    }

    private queueRefresh(): void {
        if (this.scheduleRefreshTimeout) {
            clearTimeout(this.scheduleRefreshTimeout);
        }
        this.scheduleRefreshTimeout = window.setTimeout(() => {
            this.scheduleRefreshTimeout = null;
            if (this.activePanelView)
                this.activePanelView.renderNotes();
        }, 50);
    }

    async activateView() {
        // Get the right leaf or create one if it doesn't exist
        let leaf = this.app.workspace.getRightLeaf(false);

        if (!leaf) {
            // Use getLeaf() to create a new leaf
            leaf = this.app.workspace.getLeaf(true);
        }

        await leaf.setViewState({
            type: VIEW_TYPE_ID_PANEL,
            active: true,
        });

        // Reveal the leaf to make it active
        this.app.workspace.revealLeaf(leaf);
        await this.refreshView();
    }

    async refreshView() {
        if (this.activePanelView) {
            this.activePanelView.renderNotes();
        }
    }

    async saveSettings() {
        await this.saveData(this.settings);
        await this.initializeCache();
        await this.refreshView();
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
                    .setPlaceholder('id')
                    .setValue(this.plugin.settings.idField)
                    .onChange(async (value) => {
                        this.plugin.settings.idField = value.trim();
                        await this.plugin.saveSettings();
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
                            .filter((v) => v !== '')
                            .map((v) => normalizePath(v));
                        await this.plugin.saveSettings();
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
                            .filter((v) => v !== '')
                            .map((v) => normalizePath(v));
                        await this.plugin.saveSettings();
                    })
            );

        new Setting(containerEl)
            .setName('Show notes without ID')
            .setDesc('Toggle the display of notes without IDs.')
            .addToggle((toggle) =>
                toggle
                    .setValue(this.plugin.settings.showNotesWithoutId)
                    .onChange(async (value) => {
                        this.plugin.settings.showNotesWithoutId = value;
                        await this.plugin.saveSettings();
                    })
            );
    }
}