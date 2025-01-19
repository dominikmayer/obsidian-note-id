import { App, ItemView, Plugin, setIcon, TFile, Vault, WorkspaceLeaf } from 'obsidian';

const VIEW_TYPE_ID_PANEL = 'id-side-panel';

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
        // Retrieve all markdown files in the vault
        const markdownFiles = this.app.vault.getMarkdownFiles();
    
        // Filter and sort by normalized YAML "ID"
        interface NoteMeta { title: string; id: string | number | null; file: TFile; }
        const notesWithID: NoteMeta[] = [];
        const notesWithoutID: NoteMeta[] = [];
    
        for (const file of markdownFiles) {
            const cache = this.app.metadataCache.getFileCache(file);
            if (cache?.frontmatter && typeof cache.frontmatter === 'object') {
                const frontmatter = cache.frontmatter as Record<string, any>;
    
                const frontmatterKeys = Object.keys(frontmatter).reduce((acc, key) => {
                    acc[key.toLowerCase()] = frontmatter[key];
                    return acc;
                }, {} as Record<string, any>);
    
                if (frontmatterKeys['id'] != null) {
                    notesWithID.push({
                        title: file.basename,
                        id: frontmatterKeys['id'],
                        file: file
                    });
                } else {
                    notesWithoutID.push({
                        title: file.basename,
                        id: null,
                        file: file
                    });
                }
            } else {
                notesWithoutID.push({
                    title: file.basename,
                    id: null,
                    file: file
                });
            }
        }
    
        // Sort notes with IDs by ID (assuming numerical or lexicographical order)
        notesWithID.sort((a, b) => {
            if (a.id === null) return 1;
            if (b.id === null) return -1;
            if (a.id < b.id) return -1;
            if (a.id > b.id) return 1;
            return 0;
        });

        // Sort notes without IDs by filename
        notesWithoutID.sort((a, b) => {
            if (a.title < b.title) return -1;
            if (a.title > b.title) return 1;
            return 0;
        });
    
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
    
        // Add a divider
        container.createEl('hr');
        
        // Create a container for notes without IDs
        const listElWithoutID = container.createEl('div');
        for (const note of notesWithoutID) {
            const listItem = listElWithoutID.createEl('div');
            listItem.addClass('tree-item');
    
            const titleItem = listItem.createEl('div');
            titleItem.addClasses(['tree-item-self', 'is-clickable']);
    
            const iconItem = titleItem.createEl('div');
            setIcon(iconItem, 'file');
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

	public async refresh() {
        const container = this.containerEl.children[1] as HTMLElement;
        container.empty();
        await this.renderNotes(container);
    }
}

// src/main.ts (continuation)
export default class IDSidePanelPlugin extends Plugin {
    private activePanelView: IDSidePanelView | null = null;

    async onload() {
        // Register the view
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
        this.addRibbonIcon('file-digit', 'Open ID Side Panel', () => this.activateView());
        this.addCommand({
            id: 'open-id-side-panel',
            name: 'Open ID Side Panel',
            callback: () => this.activateView(),
        });

        // Listen to file changes and metadata changes
        this.registerEvent(
            this.app.vault.on('modify', async (file) => {
                if (file instanceof TFile && file.extension === 'md') {
                    await this.refreshView();
                }
            })
        );

        this.registerEvent(
            this.app.metadataCache.on('changed', async (file) => {
                if (file instanceof TFile && file.extension === 'md') {
                    await this.refreshView();
                }
            })
        );
    }

    async onunload() {
        // Detach the side panel and clean up
        this.app.workspace.detachLeavesOfType(VIEW_TYPE_ID_PANEL);
        this.activePanelView = null;
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
}