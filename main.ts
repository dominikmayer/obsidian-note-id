import { App, ItemView, Plugin, setIcon, setTooltip, TAbstractFile, TFile, Vault, WorkspaceLeaf } from 'obsidian';

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
    private virtualList: VirtualList;

    constructor(leaf: WorkspaceLeaf, plugin: IDSidePanelPlugin) {
        super(leaf);
        this.plugin = plugin;
    }

    getViewType() { return VIEW_TYPE_ID_PANEL; }
    getDisplayText() { return 'Notes by ID'; }
    public getVirtualList(): VirtualList {
        return this.virtualList;
    }

    async onOpen() {
        const container = this.containerEl.children[1] as HTMLElement;
        container.empty();

        this.virtualList = new VirtualList(this.app, container);

        this.virtualList.setActiveFile(this.app.workspace.getActiveFile());
        this.renderNotes();

        this.registerEvent(
            this.app.workspace.on('file-open', (file) => {
                this.refresh(file)
            })
        );
    }

    public async refresh(file: TFile | null = null) {
        this.virtualList.setActiveFile(file);
        this.renderNotes();
    }

    renderNotes() {
        const { showNotesWithoutID } = this.plugin.settings;
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
        if (showNotesWithoutID) {
            combined = combined.concat(notesWithoutID);
        }

        this.virtualList.setItems(combined);
    }
}

export default class IDSidePanelPlugin extends Plugin {
    private activePanelView: IDSidePanelView | null = null;
    private scheduleRefreshTimeout: number | null = null;
    settings: IDSidePanelSettings;
    noteCache: Map<string, NoteMeta> = new Map();

    async extractNoteMeta(file: TFile): Promise<NoteMeta | null> {
        const { includeFolders, excludeFolders, showNotesWithoutID, customIDField } = this.settings;
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
            const idField = customIDField.toLowerCase() || 'id';
            id = frontmatterKeys[idField] ?? null;
        }
        // Optionally filter out notes without ID if not showing them
        if (id === null && !showNotesWithoutID) return null;
        return { title: file.basename, id, file };
    }

    async initializeCache() {
        this.noteCache.clear();
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
                if (this.activePanelView && this.activePanelView?.getVirtualList().getActiveFilePath() === oldPath && file instanceof TFile) {
                    this.activePanelView.getVirtualList().setActiveFile(file);
                }
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
            const newMeta = await this.extractNoteMeta(file);

            if (newMeta) {
                this.noteCache.set(file.path, newMeta);
            } else {
                this.noteCache.delete(file.path);
            }

            this.queueRefresh();
        }
    }

    private queueRefresh(): void {
        if (this.scheduleRefreshTimeout) {
            clearTimeout(this.scheduleRefreshTimeout);
        }
        this.scheduleRefreshTimeout = window.setTimeout(() => {
            this.scheduleRefreshTimeout = null;
            void this.refreshView();
        }, 50);
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
            this.activePanelView.refresh();
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
                    .setPlaceholder('ID')
                    .setValue(this.plugin.settings.customIDField)
                    .onChange(async (value) => {
                        this.plugin.settings.customIDField = value.trim();
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
                            .filter((v) => v !== '');
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
                            .filter((v) => v !== '');
                        await this.plugin.saveSettings();
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
                    })
            );
    }
}

class VirtualList {
    private app: App;
    private rootEl: HTMLElement;
    private spacerEl: HTMLElement;
    private itemsEl: HTMLElement;

    private itemHeight = 28; // px, assume each row is ~28px tall
    private buffer = 5;      // how many extra rows to render above/below the viewport
    private items: NoteMeta[] = [];
    private renderedStart = 0;
    private renderedEnd = -1;
    private activeFilePath: string | null = null;
    private dataChanged = false;

    constructor(app: App, rootEl: HTMLElement) {
        this.app = app;
        this.rootEl = rootEl;
        this.rootEl.addClass('note-id-list');

        // This spacer fills total scrollable area
        this.spacerEl = this.rootEl.createEl('div');
        this.spacerEl.addClass('note-id-list-spacer');

        // This itemsEl holds the actual rendered items
        this.itemsEl = this.spacerEl.createEl('div');
        this.itemsEl.addClass('note-id-list-items');

        // Listen to scroll
        this.rootEl.addEventListener('scroll', () => this.onScroll());
    }

    public setItems(items: NoteMeta[]): void {
        this.items = items;
        this.dataChanged = true;
        this.updateContainerHeight();
        requestAnimationFrame(() => this.renderRows());
    }

    public getActiveFilePath(): string | null {
        return this.activeFilePath;
    }

    public setActiveFile(file: TFile | null): void {
        if (file) {
            this.activeFilePath = file.path;
            this.updateActiveHighlight();
            this.scrollToActiveFile();
        }
    }

    private scrollToActiveFile(): void {
        if (!this.activeFilePath) return;

        const activeIndex = this.items.findIndex((item) => item.file.path === this.activeFilePath);
        if (activeIndex === -1) return;

        const scrollToPosition = activeIndex * this.itemHeight;
        const containerHeight = this.rootEl.clientHeight;

        // Check if the active file is already in view
        if (
            scrollToPosition >= this.rootEl.scrollTop &&
            scrollToPosition < this.rootEl.scrollTop + containerHeight
        ) {
            return;
        }

        // Scroll to the position of the active file
        this.rootEl.scrollTop = scrollToPosition - containerHeight / 2 + this.itemHeight / 2;
    }

    private updateContainerHeight(): void {
        const totalHeight = this.items.length * this.itemHeight;
        this.spacerEl.style.height = totalHeight + 'px';
    }

    private onScroll(): void {
        this.renderRows();
    }

    private renderRows(): void {
        const scrollTop = this.rootEl.scrollTop;
        const containerHeight = this.rootEl.clientHeight;

        // Calculate visible range
        const startIndex = Math.max(
            0,
            Math.floor(scrollTop / this.itemHeight) - this.buffer
        );
        const endIndex = Math.min(
            this.items.length - 1,
            Math.floor((scrollTop + containerHeight) / this.itemHeight) + this.buffer
        );

        // Avoid unnecessary re-renders
        if (!this.dataChanged && startIndex === this.renderedStart && endIndex === this.renderedEnd) {
            return;
        }

        this.renderedStart = startIndex;
        this.renderedEnd = endIndex;
        this.dataChanged = false;

        // Clear out old rows
        this.itemsEl.empty();

        // Render the rows for the visible range
        for (let i = startIndex; i <= endIndex; i++) {
            const note = this.items[i];
            const top = i * this.itemHeight;

            const rowEl = this.itemsEl.createEl('div');
            rowEl.addClass('note-id-item');
            rowEl.style.top = `${top}px`;
            rowEl.style.height = `${this.itemHeight}px`;

            const titleItem = rowEl.createEl('div');
            titleItem.addClasses(['tree-item-self', 'is-clickable']);
            titleItem.setAttr('data-file-path', note.file.path);

            const iconItem = titleItem.createEl('div');
            setIcon(iconItem, note.id != null ? 'file' : 'file-question');
            iconItem.addClass('tree-item-icon');

            const nameItem = titleItem.createEl('div');
            nameItem.addClass('note-id-item-inner');

            setTooltip(nameItem, note.title)
            
            if (note.id != null) {
                nameItem.createEl('span', { text: `${note.id}: ` }).addClass('note-id');
            }
            nameItem.createEl('span', { text: note.title });

            // Highlight the active file
            if (this.activeFilePath === note.file.path) {
                titleItem.addClass('is-active');
            }

            rowEl.addEventListener('click', () => {
                const leaf = this.app.workspace.getLeaf();
                leaf.openFile(note.file);
            });
        }
    }

    private updateActiveHighlight(): void {
        // Highlight the active file in the rendered range
        Array.from(this.itemsEl.children).forEach((rowEl) => {
            const titleItem = rowEl.querySelector('.tree-item-self');
            const filePath = titleItem?.getAttribute('data-file-path');
            if (filePath === this.activeFilePath) {
                titleItem?.addClass('is-active');
            } else {
                titleItem?.removeClass('is-active');
            }
        });
    }
}