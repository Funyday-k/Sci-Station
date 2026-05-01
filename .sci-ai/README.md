# Sci-Station AI Configuration

`.sci-ai` separates product AI presets from local workspace agent bridge files.

For trial sharing, only the tracked product presets should be included. Do not copy local agent bridge files, MCP endpoints, API keys, OAuth tokens, refresh tokens, client secrets, private keys, or machine-specific paths into this directory.

## GitHub-Tracked Product Presets

`sci-station/` is the Sci-Station product preset area. Files here are safe to commit and must not contain secrets.

- `sci-station/presets/`: built-in agent presets, skills, hooks, commands, and MCP server references.
- `sci-station/mcp/`: non-sensitive MCP configuration templates and schema examples.

## Local Workspace Configuration

`workspace.local/` is ignored by git. Use it for this checkout's local AI agent bridge files, local Claude Code settings, local MCP endpoints, and machine-specific paths.

Root-level `.claude/` and `.mcp.json` are also ignored. They may remain as compatibility bridge files for tools that require those exact paths, but the canonical local area is `.sci-ai/workspace.local/`.

Never put API keys, OAuth tokens, refresh tokens, client secrets, private keys, or machine-specific credentials in tracked `.sci-ai/sci-station/` files.
