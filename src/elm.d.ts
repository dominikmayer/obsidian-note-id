declare module "*.elm" {
	export interface NoteMeta {
		title: string;
		tocTitle: string | null;
		id: string | null;
		filePath: string;
	}

	export interface Settings {
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

	export interface Flags {
		settings: Settings;
		activeFile: string | null;
	}

	export interface ElmApp {
		ports: {
			createNote: {
				subscribe(callback: (data: [string, string]) => void): void;
			};
			openFile: {
				subscribe(callback: (filePath: string) => void): void;
			};
			openContextMenu: {
				subscribe(
					callback: (data: [number, number, string]) => void,
				): void;
			};
			provideNewIdForNote: {
				subscribe(callback: (data: [string, string]) => void): void;
			};
			toggleTOCButton: {
				subscribe(callback: (flag: boolean) => void): void;
			};
			receiveNotes: {
				send(data: [NoteMeta[], string[]]): void;
			};
			receiveFileOpen: {
				send(data: string | null): void;
			};
			receiveCreateNote: {
				send(data: [string, boolean]): void;
			};
			receiveDisplayIsToc: {
				send(data: boolean): void;
			};
			receiveFileRenamed: {
				send(data: [string, string]): void;
			};
			receiveGetNewIdForNoteFromNote: {
				send(data: [string, string, boolean]): void;
			};
			receiveSettings: {
				send(data: Settings): void;
			};
		};
	}

	export const Elm: {
		Main: {
			init(options: { node?: HTMLElement | null; flags: Flags }): ElmApp;
		};
	};
}
