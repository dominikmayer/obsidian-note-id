import { TFile } from "obsidian";

export interface IDSidePanelSettings {
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

export const DEFAULT_SETTINGS: IDSidePanelSettings = {
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

export interface NoteMeta {
	title: string;
	tocTitle: string | null;
	id: string | number | null;
	file: TFile;
}

export type FrontmatterValue = string | number | boolean | null;
