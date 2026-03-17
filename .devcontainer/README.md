# Dev Container Environment

A shared development container with SSH access, Tailscale integration, and development tools (Erlang, Elixir, Node) via mise.

## Accessing the Container

The dev container runs with SSH access. To connect:

```bash
# Via Tailscale hostname (recommended)
ssh loomkin@<hostname>.tailnet-<id>.ts.net

# Via localhost (fallback when Tailscale is not configured)
ssh -p 2222 loomkin@localhost
```

SSH keys are fetched from GitHub for all users in `GITHUB_USERS` and added to the `loomkin` user account.

## Setup

1. Copy `.devcontainer/.env.example` to `.devcontainer/.env`:
   ```bash
   cp .devcontainer/.env.example .devcontainer/.env
   ```

2. Update `.env` with your values:
   - `TS_AUTHKEY`: Generate from [Tailscale Admin](https://login.tailscale.com/admin/settings/keys)
   - `GITHUB_USERS`: Comma-separated GitHub usernames
   - `TS_HOSTNAME`: Optional, defaults to `loomkin-dev`
   - `DATABASE_URL`: Optional, defaults to `ecto://postgres:postgres@postgres:5432/loomkin_dev`

## Environment Variables

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `TS_AUTHKEY` | Tailscale auth key for container to join tailnet | ✗ | - |
| `GITHUB_USERS` | Comma-separated GitHub usernames to fetch SSH keys from | ✓ | - |
| `TS_HOSTNAME` | Hostname for the container in tailnet | ✗ | `loomkin-dev` |
| `DATABASE_URL` | Ecto database connection URL | ✗ | `ecto://postgres:postgres@postgres:5432/loomkin_dev` |

## Running the Container

```bash
# Start the dev container
make dev.up

# Stop the dev container
make dev.down
```

## Contents

| File | Purpose |
|------|---------|
| `Dockerfile` | Builds the dev container with Erlang, Elixir, Node, Tailscale |
| `docker-compose.yml` | Defines dev and postgres services |
| `entrypoint.sh` | Runs on container start (SSH keys, Tailscale, sshd) |
| `devcontainer.json` | VS Code dev container configuration |
| `sshd_config` | SSH server configuration (key-based auth only) |
| `.env.example` | Template for environment variables |

## SSH Configuration

- Only SSH key authentication enabled
- Root login disabled
- Only `loomkin` user allowed to SSH
- Log level set to `INFO`

## Tailscale

When `TS_AUTHKEY` is set, the container joins your tailnet via Tailscale. Generate a reusable auth key from [Tailscale Admin](https://login.tailscale.com/admin/settings/keys):
- Type: **Reusable**
- Tags: `tag:dev-container`
- Expiration: **Never** (for shared dev environment)

If not set, Tailscale is skipped and the container listens on `localhost:2222`.

## Development Tools

Installed via mise (see `.mise.toml` in project root):
- **Erlang 28**
- **Elixir 1.20.0-rc.3**
- **Node 22**

## Database

A Postgres 17 container is included. Connect from the dev container:
```bash
psql -h postgres -U postgres -d loomkin_dev
```
