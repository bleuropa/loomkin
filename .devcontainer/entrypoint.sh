#!/usr/bin/env bash
set -euo pipefail

# --- Validate required environment variables ---
if [ -z "${GITHUB_USERS:-}" ]; then
  echo "ERROR: GITHUB_USERS not set. Copy .devcontainer/.env.example to .devcontainer/.env"
  exit 1
fi

# --- Generate SSH host keys if not present (per-container unique keys) ---
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
  echo "Generating SSH host keys..."
  ssh-keygen -A
fi

# --- SSH keys are already in authorized_keys from Dockerfile build ---

# --- Pin Docker service names before Tailscale overwrites DNS ---
getent hosts postgres >> /etc/hosts || true

# --- Start Tailscale ---
if [ -n "${TS_AUTHKEY:-}" ] && [ "$TS_AUTHKEY" != "tskey-auth-placeholder" ]; then
  echo "Starting Tailscale..."
  tailscaled --state=/var/lib/tailscale/tailscaled.state &

  # Wait for Tailscale to be ready
  sleep 2
  if ! tailscale up --authkey="$TS_AUTHKEY" --hostname="$TS_HOSTNAME" --ssh; then
    echo "WARNING: Tailscale failed to start"
  fi
else
  echo "WARNING: TS_AUTHKEY not set or using placeholder, skipping Tailscale"
fi

# --- Trust mise config on boot ---
echo "Ensuring mise config is trusted..."
mise trust /home/loomkin/.mise.toml || true

# --- Start SSH daemon (foreground) ---
echo "Starting sshd..."
exec /usr/sbin/sshd -D -e
