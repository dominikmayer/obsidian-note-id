# Note ID

The [Obsidian](https://www.obsidian.md/) Note ID Plugin displays notes by their ID, enabling structured sequences for manuscripts or a Zettelkasten ("Folgezettel").

## Features

- **Note Organization by ID**: Displays notes in alphanumeric order based on the `id` [property](https://help.obsidian.md/Editing+and+formatting/Properties).
- **Cluster Identification**: Reveals clusters of related ideas, helping you see how your notes interconnect and where gaps or areas of high activity exist.
- **Support for Zettelkasten**: Ideal for Zettelkasten practitioners looking to position new notes logically and expand existing threads of thought.
- **Easily Create New Notes:** Use the context menu or a command to seamlessly create new notes that continue an existing sequence (e.g., 1.2 → 1.3) or start a subsequence branching from a note (e.g., 1.2 → 1.2a). This makes it simple to extend ideas and maintain logical connections.
- **Dedicated Table of Contents View:** The table of contents view functions as a curated index, displaying top-level notes and/or notes explicitly marked with the `toc` property – e.g., `toc: Zettelkasten` for the note that starts the Zettelkasten cluster. Unlike the main note list, which shows all notes, the table of contents view provides a structured way to highlight key topics without cluttering the sidebar

## How Clusters Work

Clusters form when related notes branch off from an initial idea, creating a web of connections. For example:

```
1.1 Initial idea
1.1a Related thought branching from 1.1
1.1a1 And another one branching from 1.1a
1.1a1a And one branching from 1.1a1
1.1a2 This one relates to 1.1a again
1.2 A new idea in the same theme
1.2a Further exploration of 1.2
```

By organizing notes this way, you can:

- Track the development of specific ideas.
- See where your focus has been and identify underdeveloped areas.
- Gain a bird's-eye view of your knowledge landscape.

For a more in-depth introduction check out _[How to Use Folgezettel in Your Zettelkasten: Everything You Need to Know to Get Started](https://writing.bobdoto.computer/how-to-use-folgezettel-in-your-zettelkasten-everything-you-need-to-know-to-get-started/)._

### Benefits over Filename-Based Sequences

Some users prepend sequence numbers to file names (e.g., 1.1 Note Title), but this approach can make notes harder to manage. Notes appear cluttered, and the numbers show up in links, reducing readability. Using the `id` property avoids these issues, keeping filenames clean while maintaining a structured sequence in the sidebar view.

## Installation

### From the web

1. Open the plugin on the [Obsidian Plugin Website](https://obsidian.md/plugins?id=note-id).
2. Click on `Install`.

### From within Obsidian

1. Open Obsidian.
2. Go to `Settings > Community Plugins`.
3. Search for "Note ID".
4. Install and enable the plugin.

## Usage

1. Press `Ctrl + P` or `Cmd + P` to open the Command palette.
2. Execute `Note ID: Open side panel` and you will see a sidebar panel with all your notes. (You can change which notes to include/exclude in the plugin settings.)
3. Add an `id` [property](https://help.obsidian.md/Editing+and+formatting/Properties) to your first note (e.g., `id: 1.1`). (You can change the name of the property in the settings.)
4. Use the Command palette, a configurable [hotkey](https://help.obsidian.md/User+interface/Hotkeys) or the context menu in the sidebar panel to create a new note in sequence (`1.1` → `1.2`) or subsequence (`1.1` → `1.1a`).
5. Optionally add a `toc` property with the title that should show up in the table of contents (e.g., `toc: Productivity`).

### Example

This note has the title `Deep work is the key to being productive`:

```
---
id: 3.1
toc: Productivity
---

Deep work is the ability to focus without distraction on cognitively demanding tasks. It allows you to produce at an elite level and should be a core part of any knowledge worker's routine.
```

- This note serves as an entry point for the Productivity cluster, so it appears in the table of contents under `Productivity`.
- Related notes can reference or extend it (e.g., id: 3.1a for a note on time blocking)

## Settings

The plugin allows you to

- change the name of `id` and `toc` properties,
- select the folders with notes to include or exclude,
- decide whether notes without ID should be shown,
- choose whether the table of contents should automatically include notes based on hierarchy level, or only show manually selected entries,
- indent notes depending on the "hierarchy" level of their ID, and
- configure the visual separation between notes.

## Feedback and Contributions

Feedback and contributions are welcome! Visit [GitHub](https://github.com/dominikmayer/obsidian-note-id) to [report issues](https://github.com/dominikmayer/obsidian-note-id/issues), [ask questions](https://github.com/dominikmayer/obsidian-note-id/discussions), or submit pull requests.

## Other Plugins

- [Reader Mode](https://github.com/dominikmayer/obsidian-reader-mode) ensures that notes are opened in reader mode, so you can see dialogs rendered right away.
- [Yesterday](https://github.com/dominikmayer/obsidian-yesterday) lets you create and edit a [Yesterday](https://www.yesterday.md) journal in Obsidian.
