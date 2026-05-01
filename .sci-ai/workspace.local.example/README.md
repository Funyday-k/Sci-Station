# Local Workspace AI Configuration Example

Copy examples from this directory into `.sci-ai/workspace.local/` for machine-specific agent bridge settings.

`.sci-ai/workspace.local/` is ignored by git. It is the place for local Claude Code bridge settings, MCP server paths, private endpoint choices, and other checkout-specific AI configuration.

Do not commit files from `.sci-ai/workspace.local/`, and do not include them when sending a trial build or source snapshot to another person.

Use references such as `keychain:...`, `env:...`, or `secret-ref:...` in shareable examples. Never paste raw API keys, OAuth tokens, refresh tokens, client secrets, private keys, or private endpoint credentials here.
