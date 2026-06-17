import {
	App,
	FuzzySuggestModal,
	FuzzyMatch,
	Instruction,
	TFile,
	FrontMatterCache,
} from "obsidian";
import { NoteMeta } from "./types";

type PropertyValue = string | string[];

export abstract class NoteSearchModal extends FuzzySuggestModal<TFile> {
	idProperty: string;
	tocProperty: string;
	private noteCache: Map<string, NoteMeta>;

	constructor(
		app: App,
		idProperty: string,
		tocProperty: string,
		noteCache: Map<string, NoteMeta>,
		instructions: Instruction[],
	) {
		super(app);
		this.setPlaceholder(
			"Enter note title, note ID or table of contents title to open a note",
		);
		this.idProperty = idProperty;
		this.tocProperty = tocProperty;
		this.noteCache = noteCache;

		const navigateInstruction: Instruction[] = [
			{
				command: "↑↓",
				purpose: "navigate",
			},
		];
		const cancelInstruction: Instruction[] = [
			{
				command: "esc",
				purpose: "cancel",
			},
		];
		this.setInstructions([
			...navigateInstruction,
			...instructions,
			...cancelInstruction,
		]);
		this.limit = 20;
	}

	async onOpen(): Promise<void> {
		await super.onOpen();
		this.inputEl.addEventListener("keydown", this.handleKeyDown, true);
	}

	onClose(): void {
		super.onClose();
		this.inputEl.removeEventListener("keydown", this.handleKeyDown, true);
	}

	private handleKeyDown = (evt: KeyboardEvent): void => {
		if (
			evt.key === "Enter" &&
			(evt.ctrlKey || evt.metaKey || evt.altKey || evt.shiftKey)
		) {
			const selectedEl = this.resultContainerEl.querySelector(
				".suggestion-item.is-selected",
			);
			if (!selectedEl) return;

			const path = selectedEl.getAttribute("data-path");
			if (!path) return;

			const item = this.getItems().find((file) => file.path === path);
			if (!item) return;

			evt.preventDefault();
			evt.stopPropagation();
			this.close();
			this.onChooseItem(item, evt);
		}
	};

	getItemText(item: TFile): string {
		const noteMeta = this.noteCache.get(item.path);
		const metadata = this.app.metadataCache.getFileCache(item);
		const frontmatter = metadata?.frontmatter;
		const aliases = frontmatter?.["aliases"] ?? "";
		if (noteMeta) {
			return `${noteMeta.title} ${noteMeta.id ?? ""} ${noteMeta.tocTitle ?? ""} ${aliases}`;
		}

		const id = this.getFrontmatterValue(frontmatter, this.idProperty);
		const toc = this.getFrontmatterValue(frontmatter, this.tocProperty);
		return `${item.basename} ${id} ${toc} ${aliases}`;
	}

	private getFrontmatterValue(
		frontmatter: FrontMatterCache | undefined,
		property: string,
	): string {
		if (!frontmatter) return "";
		for (const key in frontmatter) {
			if (key.toLowerCase() === property.toLowerCase()) {
				return frontmatter[key];
			}
		}
		return "";
	}

	getItems(): TFile[] {
		return Array.from(this.noteCache.values()).map(
			(noteMeta) => noteMeta.file,
		);
	}

	private getMatchType(
		file: TFile,
		query: string,
	): "title" | "aliases" | "id" | "toc" {
		const noteMeta = this.noteCache.get(file.path);
		if (noteMeta) {
			if (this.fuzzyMatchIndices(noteMeta.title, query).length)
				return "title";
			if (
				noteMeta.id &&
				this.fuzzyMatchIndices(String(noteMeta.id), query).length
			)
				return "id";
			if (
				noteMeta.tocTitle &&
				this.fuzzyMatchIndices(noteMeta.tocTitle, query).length
			)
				return "toc";
		}
		if (this.fuzzyMatchIndices(file.basename, query).length) return "title";
		const frontmatter =
			this.app.metadataCache.getFileCache(file)?.frontmatter;
		if (frontmatter) {
			const aliasesValue = this.getFrontmatterValue(
				frontmatter,
				"aliases",
			);
			if (
				this.fuzzyMatchIndices(
					this.getPropertyDisplayValue(aliasesValue),
					query,
				).length
			)
				return "aliases";
			const idValue = this.getFrontmatterValue(
				frontmatter,
				this.idProperty,
			);
			if (
				this.fuzzyMatchIndices(
					this.getPropertyDisplayValue(idValue),
					query,
				).length
			)
				return "id";
			const tocValue = this.getFrontmatterValue(
				frontmatter,
				this.tocProperty,
			);
			if (
				this.fuzzyMatchIndices(
					this.getPropertyDisplayValue(tocValue),
					query,
				).length
			)
				return "toc";
		}
		return "title";
	}

	private getPropertyDisplayValue(value: PropertyValue): string {
		if (Array.isArray(value)) {
			return value.join(", ");
		} else if (typeof value === "string") {
			return value;
		} else {
			return String(value);
		}
	}

	renderSuggestion(file: FuzzyMatch<TFile>, el: HTMLElement): void {
		const query = this.inputEl.value;
		const matchType = this.getMatchType(file.item, query);
		const noteMeta = this.noteCache.get(file.item.path);

		// Fallback values from frontmatter if noteMeta isn’t available.
		const metadata = this.app.metadataCache.getFileCache(file.item);
		const frontmatter = metadata?.frontmatter;
		const fallbackTitle = file.item.basename;
		const fallbackId = this.getFrontmatterValue(
			frontmatter,
			this.idProperty,
		);
		const fallbackToc = this.getFrontmatterValue(
			frontmatter,
			this.tocProperty,
		);
		const fallbackAlias = this.getFrontmatterValue(frontmatter, "aliases");

		const title = noteMeta?.title ?? fallbackTitle;
		const id = noteMeta?.id ?? fallbackId;
		const toc = noteMeta?.tocTitle ?? fallbackToc;
		const alias = fallbackAlias;

		let titleText = "";
		let noteLeft = "";
		let noteRight = "";

		if (matchType === "title") {
			// Show note title in the suggestion title (highlighted).
			// Note: note is "id: toc title"
			titleText = title;
			noteLeft = id ? String(id) : "";
			noteRight = toc ? toc : "";
		} else if (matchType === "aliases" || matchType === "toc") {
			// Show alias (or toc) in the suggestion title (highlighted).
			// Note: note is "id: note title"
			titleText = matchType === "aliases" ? alias : toc;
			noteLeft = id ? String(id) : "";
			noteRight = title;
		} else if (matchType === "id") {
			// Show id in the suggestion title (highlighted).
			// Note: note is "toc title: note title"
			titleText = id ? String(id) : "";
			noteLeft = toc ? toc : "";
			noteRight = title;
		}

		// Only include colon if both note parts exist.
		const noteText =
			noteLeft && noteRight
				? `${noteLeft}: ${noteRight}`
				: noteLeft || noteRight;

		el.setAttribute("data-path", file.item.path);

		el.addClass("mod-complex");
		const contentEl = el.createEl("div", { cls: "suggestion-content" });
		const titleEl = contentEl.createEl("div", { cls: "suggestion-title" });
		const noteEl = contentEl.createEl("div", { cls: "suggestion-note" });

		this.renderHighlightedText(titleEl, titleText, query);
		noteEl.setText(noteText);
	}

	private renderHighlightedText(
		element: HTMLElement,
		text: string,
		query: string,
	): void {
		element.empty();
		if (!query) {
			element.setText(text);
			return;
		}

		const indices = this.fuzzyMatchIndices(text, query);
		if (indices.length === 0) {
			element.setText(text);
			return;
		}

		let lastIndex = 0;
		indices.forEach((index) => {
			if (index > lastIndex) {
				element.appendText(text.slice(lastIndex, index));
			}
			const span = element.createEl("span", {
				cls: "suggestion-highlight",
			});
			span.setText(text[index]);
			lastIndex = index + 1;
		});

		if (lastIndex < text.length) {
			element.appendText(text.slice(lastIndex));
		}
	}

	private fuzzyMatchIndices(text: string, query: string): number[] {
		const indices: number[] = [];
		let queryIndex = 0;
		for (let i = 0; i < text.length && queryIndex < query.length; i++) {
			if (text[i].toLowerCase() === query[queryIndex].toLowerCase()) {
				indices.push(i);
				queryIndex++;
			}
		}
		return queryIndex === query.length ? indices : [];
	}
}
