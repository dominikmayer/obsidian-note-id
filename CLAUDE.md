# Obsidian Note ID Plugin Commands & Guidelines

## Build Commands
- `npm run dev` - Development build
- `npm run build` - Production build (runs TypeScript check and esbuild)
- `npm run version` - Bump version, updates manifest.json and versions.json

## Test Commands
- `npm test` - Run all tests with elm-test
- `npx elm-test tests/NoteIdTest.elm --fuzz 100` - Run specific test file
- `npx elm-test tests/NoteIdTest.elm --filter "getNewIdInSequence"` - Run specific test case
- `npx eslint src/**/*.ts` - Lint TypeScript files
- `npx elm-review` - Lint Elm files

## Code Style Guidelines
- **TypeScript**: 4-space indentation, strict null checks, no implicit any
- **Elm**: Explicit exposing, functional style with pattern matching
- **Imports**: Alphabetical in Elm, explicit imports with specific exposing
- **Naming**: camelCase for variables/functions, PascalCase for types/modules
- **Error Handling**: Elm uses Result types, pattern matching for error cases
- **Architecture**: Elm for core logic, TypeScript for Obsidian integration
- **Tests**: Descriptive test names, helper functions to avoid repetition