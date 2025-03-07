import IDSidePanelPlugin from "../main";
import { ID_FIELD_DEFAULT, TOC_TITLE_FIELD_DEFAULT } from "./constants";
import { App, PluginSettingTab, Setting, normalizePath } from "obsidian";

export class IDSidePanelSettingTab extends PluginSettingTab {
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

		containerEl.createEl("br");
		const tocSection = containerEl.createEl("div", {
			cls: "setting-item setting-item-heading",
		});
		const tocSectionInfo = tocSection.createEl("div", {
			cls: "setting-item-info",
		});
		tocSectionInfo.createEl("div", {
			text: "Table of contents",
			cls: "setting-item-name",
		});

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
			.setName("Automatically include notes in table of contents")
			.setDesc(
				"If enabled, notes will be included in the table of contents based on their hierarchy level. " +
					"If disabled, only notes with the table of contents title property will be shown.",
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
					"A value of 1 includes only top-level notes (1, 2, …), 2 includes sub-levels (1.1, 1.2, …), and so on. " +
					"Notes with the table of contents title property are always included.",
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
	}
}
