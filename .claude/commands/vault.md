---
description: Manage vault — auth, list, attach, search, status
argument-hint: <auth|list|attach|detach|search|status> [args]
---

# Vault Management

Manage your knowledge vault from within the CLI. Vaults are created on loomkin.dev and attached locally.

Parse `$ARGUMENTS` to determine the subcommand and route accordingly.

## Subcommands

### `auth`

Authenticate with loomkin.dev via OAuth.

1. Check if a token already exists at `~/.config/loomkin/auth.json`
2. If not, open the browser to the loomkin.dev OAuth flow:
   ```bash
   open "https://loomkin.dev/oauth/authorize?client=cli&redirect_uri=http://localhost:19275/callback"
   ```
3. Start a temporary local server to receive the callback token (or instruct the user to paste it)
4. Store the token at `~/.config/loomkin/auth.json`
5. Verify the token works by calling the loomkin.dev API: `GET /api/v1/me`

If already authenticated, show the current user info and when the token expires.

### `list`

List all vaults accessible to the authenticated user.

1. Require auth (check `~/.config/loomkin/auth.json` exists, if not tell user to run `/vault auth`)
2. Call loomkin.dev API: `GET /api/v1/vaults`
3. Display vaults in a table: vault_id, name, storage_type, your role, member count
4. Indicate which vault (if any) is currently attached to this project

### `attach <vault-id>`

Attach a remote vault to the current project.

1. Require auth
2. Verify the vault exists and the user has access: `GET /api/v1/vaults/<vault-id>`
3. Store the attachment in `.loomkin/vault.json` in the project root:
   ```json
   {
     "vault_id": "<vault-id>",
     "remote": "https://loomkin.dev",
     "attached_at": "2026-04-02T00:00:00Z"
   }
   ```
4. Sync the vault index locally (pull entry metadata from the API)
5. Confirm: "Vault '<name>' attached. Agents will use this vault for knowledge management."

### `detach`

Detach the current vault from this project.

1. Check `.loomkin/vault.json` exists
2. Confirm with the user before removing
3. Remove `.loomkin/vault.json`
4. Report: "Vault detached. Agents will fall back to local-only vault."

### `search <query>`

Search the attached vault.

1. Check a vault is attached (read `.loomkin/vault.json`)
2. If attached, use the Loomkin vault search tool against the vault_id
3. Display results: title, type, path, relevance snippet
4. If no vault attached, tell the user to run `/vault attach`

### `status`

Show current vault status.

1. Check auth status (`~/.config/loomkin/auth.json`)
2. Check attachment status (`.loomkin/vault.json`)
3. If attached, show:
   - Vault name, id, storage type
   - Entry count by type
   - Last sync time
   - Link to vault on loomkin.dev
4. If not attached, suggest `/vault list` and `/vault attach`

## Notes

- The loomkin.dev API does not exist yet. When hitting API endpoints that don't exist, tell the user: "loomkin.dev API is not yet available. This command will work once the remote API is deployed."
- For `search`, fall back to local vault search if available (via `Loomkin.Vault.search/3` in the running Phoenix app)
- Always check auth before making API calls
- Store auth config in `~/.config/loomkin/` (XDG-style), not in the project

$ARGUMENTS
