---
name: agent-platform
description: Sci-Station Swift-native agent platform architecture, safety, provider, tool, hook, plugin, and MCP guidance.
version: 0.1.0
---

# Agent Platform

Sci-Station should implement agent behavior as Swift-native services first. OpenCode is a runtime architecture reference; Claude Code plugins are a preset ecosystem reference.

## Core Boundaries

- Keep reusable logic in `Sci-Station/Agent` and `Sci-Station/LLM`, covered by `SciStationCoreTestRunner`.
- Preserve existing `AgentRun`, `AgentThread`, `runs.jsonl`, and `threads.jsonl` while new session events mature.
- Store visible state under `.sci-station/agent/`; store credentials in Keychain or a secure backend.
- Treat workspace writes, shell commands, MCP side effects, and external network actions as auditable.

## First-Class Components

- agent profiles and subagent profiles
- tool registry metadata and output policy
- allow / ask / deny permission rules
- lifecycle hooks
- plugin, skill, and command schemas
- MCP server configurations with secret references
- provider request/response models that support messages, tools, model options, and cancellation
