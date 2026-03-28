# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ModalEdit is a VS Code extension that adds configurable modal editing (like Vim) to VS Code. It leverages VS Code's built-in commands and allows users to define custom keybindings in `settings.json` rather than hardcoding them.

## Development Commands

A Makefile provides convenient shortcuts for common development tasks. Run `make help` to see all available targets.

### Quick Start
- `make install` - Install dependencies
- `make compile` - Compile TypeScript to `out/` directory
- `make watch` - Auto-recompile on file changes
- `make deploy` - Production build (bundles to `dist/` via litscript)
- `make lits-watch` - Development server with live reload

### Extension Testing
- `make package` - Create .vsix package (runs deploy first)
- `make install-ext` - Build and install extension to VS Code
- `make reinstall` - Complete rebuild cycle (uninstall → package → install)
- `make uninstall-ext` - Remove extension from VS Code

### Maintenance
- `make clean` - Remove generated files (out/, dist/, node_modules/, *.vsix, docs HTML)
- `npm version <major|minor|patch>` - Bump version and auto-push tags

### Direct npm scripts
- `npm run compile` - Same as `make compile`
- `npm run deploy` - Same as `make deploy`
- `npm run lits-watch` - Same as `make lits-watch`

## Architecture

### Core Modules (src/)

**extension.ts** - Entry point
- Activates on VS Code startup (`onStartupFinished`)
- Registers all commands via `commands.register()`
- Sets up event subscriptions (config changes, editor changes, text changes)
- Initializes mode (normal or insert) based on settings

**actions.ts** - Keybinding configuration parser and state
- Defines TypeScript interfaces for configuration schema:
  - `Action` - Union type: Command | Keymap | number (keymap reference)
  - `Command` - String, Conditional, Parameterized, or Command array
  - `Conditional` - JavaScript expression with branches
  - `Parameterized` - Command with args and optional repeat count
  - `Keymap` - Nested dictionary of keys to actions, supports recursive references via numeric IDs
- Parses user configuration from `settings.json`
- Manages cursor styles and status bar text/colors for different modes
- Handles configuration updates and validation

**commands.ts** - Command implementations and state management
- Implements ModalEdit-specific commands (search, bookmarks, snippets, etc.)
- Manages extension state: current mode, search parameters, bookmarks, quick snippets
- Handles mode switching (normal ↔ insert ↔ search ↔ selection)
- Updates cursor styles and status bar based on current mode

### Key Concepts

**Keybinding Configuration Philosophy**
- Unlike most Vim emulators, ModalEdit doesn't hardcode keybindings
- Users define keybindings in `modaledit.keybindings` and `modaledit.selectbindings` sections of `settings.json`
- Keybindings map to VS Code commands (built-in or from other extensions)
- Supports:
  - Single commands: `"i": "modaledit.enterInsert"`
  - Commands with arguments: Object with `command`, `args`, optional `repeat`
  - Command sequences: Arrays of commands
  - Conditional commands: JavaScript expressions evaluated at runtime
  - Multi-key sequences: Nested keymaps
  - Recursive keymaps: Via numeric IDs for arbitrarily long sequences (e.g., `3w` to move 3 words)

**Action Evaluation Context**
When commands are evaluated, these variables are available in JavaScript expressions:
- `__file`, `__line`, `__col`, `__char` - Current position info
- `__selection`, `__selecting` - Selection state
- `__keySequence` / `__keys` - Array of pressed keys
- `__rkeys` - Reversed keys array (for accessing last key easily)
- `__cmd` / `__rcmd` - Keys joined as strings

**Modes**
- Normal mode: Keys invoke commands instead of typing text
- Insert mode: Standard VS Code editing
- Search mode: Incremental search (like Vim's `/`)
- Selection/Visual mode: Not a separate mode but indicated in status bar when selection is active

**Presets**
- `presets/vim.jsonc` - Built-in Vim keybindings
- Users can import presets via `modaledit.importPresets` command
- Preset files must export object with `keybindings` and/or `selectbindings` properties

### Build System

**litscript** - Literate programming tool
- Generates documentation from code comments
- Bundles extension for distribution (`dist/extension.js`)
- Configuration in `litsconfig.json`
- Processes markdown files and TypeScript source together

### Output Structure

- `out/` - TypeScript compilation output (development)
- `dist/` - Bundled extension for production (via litscript)
- Main entry point: `dist/extension.js` (specified in `package.json`)

## VS Code Extension Specifics

### Commands Contributed
All commands are prefixed with `modaledit.` (e.g., `modaledit.toggle`, `modaledit.enterNormal`)

### Configuration Properties
- `modaledit.keybindings` - Normal mode keybindings
- `modaledit.selectbindings` - Selection/visual mode keybindings
- `modaledit.*CursorStyle` - Cursor shapes for each mode
- `modaledit.*StatusText` / `modaledit.*StatusColor` - Status bar appearance

### Context Keys
- `modaledit.searching` - Used in `when` clauses for search mode keybindings

## Development Notes

- No test files present in the repository
- TypeScript strict mode enabled
- Target: ES6, CommonJS modules
- Extension activates immediately on VS Code startup
- Uses literate programming approach (code documentation is generated from source comments)
