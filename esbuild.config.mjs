import esbuild from "esbuild";
import process from "process";
import builtins from "builtin-modules";
import elmPlugin from "esbuild-plugin-elm";
import path from "path";
import fs from "fs";

const banner =
`/*
THIS IS A GENERATED/BUNDLED FILE BY ESBUILD
if you want to view the source, please visit the github repository of this plugin
*/
`;

const prod = (process.argv[2] === "production");

const context = await esbuild.context({
	banner: {
		js: banner,
	},
	entryPoints: ["main.ts"],
	bundle: true,
	external: [
		"obsidian",
		"electron",
		"@codemirror/autocomplete",
		"@codemirror/collab",
		"@codemirror/commands",
		"@codemirror/language",
		"@codemirror/lint",
		"@codemirror/search",
		"@codemirror/state",
		"@codemirror/view",
		"@lezer/common",
		"@lezer/highlight",
		"@lezer/lr",
		...builtins],
	format: "cjs",
	target: "es2018",
	logLevel: "info",
	sourcemap: prod ? false : "inline",
	treeShaking: true,
	outfile: "main.js",
	plugins: [elmPlugin()],
	minify: prod,
});

// Watch mode
if (!prod) {
    // Start watching with esbuild
    await context.watch();

    const elmDir = path.resolve("src");
    fs.watch(elmDir, { recursive: true }, (eventType, filename) => {
        if (filename.endsWith(".elm")) {
            console.log(`Change detected in ${filename}. Rebuilding...`);
            context.rebuild();
        }
    });
} else {
    await context.rebuild();
    process.exit(0);
}