FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# System dependencies for Erlang/Elixir compilation and dev tooling
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential autoconf m4 libncurses-dev libssl-dev \
    inotify-tools git curl wget unzip tmux \
    openssh-server sudo \
    locales ca-certificates gnupg \
    # Erlang extras
    libsctp-dev libgmp-dev \
    && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

# Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# mise (version manager)
ENV MISE_INSTALL_PATH=/usr/local/bin/mise
RUN curl https://mise.run | sh

# Create shared dev user
RUN useradd -m -s /bin/bash -G sudo loomkin \
    && echo "loomkin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/loomkin \
    && chmod 0440 /etc/sudoers.d/loomkin

# SSH setup
RUN mkdir -p /run/sshd
COPY .devcontainer/sshd_config /etc/ssh/sshd_config

# mise config for tool versions (single source of truth from project root)
COPY --chown=loomkin:loomkin .mise.toml /home/loomkin/.mise.toml

# Install Erlang, Elixir, Node via mise as loomkin
USER loomkin
WORKDIR /home/loomkin

# Initialize GitHub keys for all engineers via cloud-init equivalent
RUN mkdir -p /home/loomkin/.ssh \
    && touch /home/loomkin/.ssh/authorized_keys \
    && echo 'Initializing GitHub SSH keys...' \
    && for user in ${GITHUB_USERS}; do \
        echo "Fetching keys for ${user}"; \
        curl -s "https://github.com/${user}.keys" >> /home/loomkin/.ssh/authorized_keys 2>/dev/null || true; \
      done \
    && chmod 600 /home/loomkin/.ssh/authorized_keys \
    && echo 'GitHub SSH keys initialized'

# Activate mise in shell so SSH sessions get tools on PATH
RUN echo 'eval "$(mise activate bash)"' >> /home/loomkin/.bashrc \
    && echo 'cd /home/loomkin/loomkin' >> /home/loomkin/.bashrc

ENV MISE_TRUSTED_CONFIG_PATHS=/home/loomkin/.mise.toml

RUN mise trust /home/loomkin/.mise.toml \
    && mise install \
    && mise exec -- mix local.hex --force \
    && mise exec -- mix local.rebar --force

# Back to root for entrypoint
USER root
COPY .devcontainer/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
