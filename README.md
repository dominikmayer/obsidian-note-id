# Note ID

The [Obsidian](https://www.obsidian.md/) Note ID Plugin displays notes by their ID, enabling structured sequences in a Zettelkasten ("Folgezettel").

## Features

- **Note Organization by ID**: Displays notes in alphanumeric order based on the `id` property.
- **Cluster Identification**: Reveals clusters of related ideas, helping you see how your notes interconnect and where gaps or areas of high activity exist.
- **Support for Zettelkasten**: Ideal for Zettelkasten practitioners looking to position new notes logically and expand existing threads of thought.
- **Easily Create New Notes:** Use commands to seamlessly create new notes that continue an existing sequence (e.g., 1.2 → 1.3) or start a subsequence branching from a note (e.g., 1.2 → 1.2a). This makes it simple to extend ideas and maintain logical connections.

### How Clusters Work

Clusters form when related notes branch off from an initial idea, creating a web of connections. For example:

```
1.1 Initial idea
1.1a Related thought branching from 1.1
1.2 A new idea in the same theme
1.2a Further exploration of 1.2
```

By organizing notes this way, you can:

- Track the development of specific ideas.
- See where your focus has been and identify underdeveloped areas.
- Gain a bird's-eye view of your knowledge landscape.

For a more in-depth introduction check out _[How to Use Folgezettel in Your Zettelkasten: Everything You Need to Know to Get Started](https://writing.bobdoto.computer/how-to-use-folgezettel-in-your-zettelkasten-everything-you-need-to-know-to-get-started/)._

### Benefits over Filename-Based Sequences

Some users prepend sequence numbers to file names (e.g., 1.1 Note Title), but this approach can make notes harder to manage. Notes appear cluttered, and the numbers show up in links, reducing readability. Using the `ID` property avoids these issues, keeping filenames clean while maintaining a structured sequence in the sidebar view.

## Installation

1. Open Obsidian.
2. Go to `Settings > Community Plugins`.
3. Search for "Note ID".
4. Install and enable the plugin.

## Usage

1. Add an `ID` property to the frontmatter of your notes (e.g., `ID: 1.1`).
2. Open the sidebar panel to view notes ordered by their IDs.
3. Use the panel to explore note clusters and expand your thinking systematically.

## Settings

The plugin allows you to

- change the name of the ID property
- select the folders with notes to include or exclude
- decide whether notes without ID should be shown

## Feedback and Contributions

Feedback and contributions are welcome! Visit [GitHub](https://github.com/dominikmayer/obsidian-note-id) to report issues or submit pull requests.

### Other Plugins

- [Reader Mode](https://github.com/dominikmayer/obsidian-reader-mode) ensures that notes are opened in reader mode, so you can see dialogs rendered right away.
- [Yesterday](https://github.com/dominikmayer/obsidian-yesterday) lets you create and edit a [Yesterday](https://www.yesterday.md) journal in Obsidian.
