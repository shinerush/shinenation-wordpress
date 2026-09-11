# shinenation-wordpress

MCP control plane for **[shinenationtech.com](https://shinenationtech.com)** —
a WordPress site hosted on Hostinger.

This repository holds configuration and tooling only. It contains no
WordPress source code, no theme, and no credentials.

## Contents

| Path | Purpose |
|---|---|
| [`docs/MCP_SETUP.md`](docs/MCP_SETUP.md) | Full setup walkthrough — start here |
| `.mcp.json.example` | MCP server template; copy to `.mcp.json` locally (git-ignored) |
| `.env.example` | Credential template — copy to `.env` (git-ignored) |
| `scripts/verify-wp-connection.sh` | Read-only preflight against the live site |

## Quick start

```bash
cp .env.example .env        # then fill in real values
chmod 600 .env
cp .mcp.json.example .mcp.json
set -a; source .env; set +a
./scripts/verify-wp-connection.sh   # read-only; must pass first
claude                              # approve the 'wordpress' server when prompted
```

## Credential policy

- Real credentials live in `.env` only, which is git-ignored.
- `.mcp.json.example` is committed and must never contain a literal secret.
- The WordPress Application Password carries the full capabilities of its
  user account — scope that account to the narrowest role that works, and
  revoke under **Users → Profile → Application Passwords** if exposed.

## Known constraint

Claude Code cloud sandboxes block outbound traffic to `shinenationtech.com`.
They block `mcp.hostinger.com` too. That is why the live `.mcp.json` is
git-ignored rather than committed: a committed one auto-loads in every cloud
session and fails on startup. Run the MCP servers locally, or allowlist the
domains in the environment's network settings. Details in [`docs/MCP_SETUP.md`](docs/MCP_SETUP.md#2-where-to-run-this--read-this-before-anything-else).
