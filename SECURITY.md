# Security policy

## Supported versions

Sci-Station is currently a Developer Preview. Security fixes target the latest published preview and the development line on `main`. Older previews are not maintained as separate security branches; reporters should include their exact app version, build number and commit if built from source. No long-term support or response-time SLA is offered.

Version `0.1.0` was distributed without Developer ID signing or notarization. The new public release pipeline requires signing, notarization, stapling and Gatekeeper verification; its presence in the repository does not retroactively validate older downloads. Verify the specific release's assets and checksums.

## Report a vulnerability privately

Use [GitHub private vulnerability reporting](https://github.com/Funyday-k/Sci-Station/security/advisories/new). Reports are visible to the repository maintainers and invited collaborators, rather than the public Issue tracker. If the form is unavailable, open a public Issue asking only for a private contact channel; do not include vulnerability details, credentials, private files or an exploit.

Include the affected version, operating system, prerequisites, minimal reproduction using synthetic data, expected and actual behavior, and impact. Relevant areas include Research Root path traversal and symlinks, import/archive handling, MCP subprocess and network access, Agent approvals/writeback, Keychain credentials, logs, sidecar protocol boundaries and release integrity.

If a credential has been exposed, revoke or rotate it with its provider and redact it before reporting. Do not send real API keys or private research data as evidence.

## Response and disclosure

The maintainer aims to acknowledge a report within seven calendar days, reproduce and assess its impact, agree a disclosure plan with the reporter, and publish an advisory with affected versions and remediation when a fix is available. These are best-effort targets for a volunteer project. Disclosure timing depends on impact, reproducibility and fix readiness; maintainers will communicate delays in the private advisory.

Reports made in good faith are welcome. Test only systems and data you control or are authorized to test, and avoid disrupting other users. This policy does not grant permission to test third-party LLM, metadata or MCP services.
