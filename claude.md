# Claude Code Project Guidelines

## Environment

This project runs in a **dev container** (VS Code Dev Containers / GitHub Codespaces).

- **Base image**: `node:20`
- **User**: `node` (non-root)
- **Working directory**: `/workspace`
- **Shell**: zsh (default)

## Network Firewall

The dev container runs a restrictive firewall (`init-firewall.sh`) that only allows outbound connections to specific domains. This is intentional for security.

### Allowed Domains

| Domain                                 | Purpose                                    |
| -------------------------------------- | ------------------------------------------ |
| GitHub IPs                             | Git operations (clone, push, pull, gh CLI) |
| `registry.npmjs.org`                   | npm package installation                   |
| `pypi.org`, `files.pythonhosted.org`   | pip package installation                   |
| `api.anthropic.com`                    | Claude API                                 |
| `sentry.io`                            | Error tracking                             |
| `statsig.anthropic.com`, `statsig.com` | Analytics                                  |
| `marketplace.visualstudio.com`         | VS Code extensions                         |
| `vscode.blob.core.windows.net`         | VS Code assets                             |
| `update.code.visualstudio.com`         | VS Code updates                            |

### Blocked (by design)

- `apt-get install` - Debian/Ubuntu repositories are blocked for security
- General internet access - Only allowlisted domains work
