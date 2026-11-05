FROM node:22

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

# Install basic development tools and iptables/ipset
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  ca-certificates \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/node/.claude && \
  chown -R node:node /workspace /home/node/.claude

WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

ARG LAZYGIT_VERSION=0.66.2
RUN ARCH=$(dpkg --print-architecture) && \
  case "$ARCH" in \
    arm64) LAZYGIT_ARCH=arm64 ;; \
    amd64) LAZYGIT_ARCH=x86_64 ;; \
    *) echo "unsupported architecture: $ARCH" >&2 && exit 1 ;; \
  esac && \
  wget -O /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_linux_${LAZYGIT_ARCH}.tar.gz" && \
  tar -xzf /tmp/lazygit.tar.gz -C /usr/local/bin lazygit && \
  rm /tmp/lazygit.tar.gz

ARG NEOVIM_VERSION=0.12.6
RUN ARCH=$(dpkg --print-architecture) && \
  case "$ARCH" in \
    arm64) NEOVIM_ARCH=arm64 ;; \
    amd64) NEOVIM_ARCH=x86_64 ;; \
    *) echo "unsupported architecture: $ARCH" >&2 && exit 1 ;; \
  esac && \
  wget -O /tmp/nvim.tar.gz "https://github.com/neovim/neovim/releases/download/v${NEOVIM_VERSION}/nvim-linux-${NEOVIM_ARCH}.tar.gz" && \
  tar -xzf /tmp/nvim.tar.gz -C /usr/local --strip-components=1 && \
  rm /tmp/nvim.tar.gz

# ---------------------------------------------------------------------------
# CUSTOMIZE HERE: add your project's own language toolchain. Example (Python, via a
# pinned static-binary release rather than piping the curl|sh installer, for the same
# reason this whole Dockerfile avoids piping installer scripts where it can — a pinned
# release asset is reproducible and auditable, a network-fetched shell script is not):
#
#   ARG UV_VERSION=0.12.24
#   RUN ARCH=$(dpkg --print-architecture) && \
#     case "$ARCH" in \
#       arm64) UV_TARGET=aarch64-unknown-linux-gnu ;; \
#       amd64) UV_TARGET=x86_64-unknown-linux-gnu ;; \
#       *) echo "unsupported architecture: $ARCH" >&2 && exit 1 ;; \
#     esac && \
#     wget -O /tmp/uv.tar.gz "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${UV_TARGET}.tar.gz" && \
#     tar -xzf /tmp/uv.tar.gz -C /tmp && \
#     mv "/tmp/uv-${UV_TARGET}/uv" "/tmp/uv-${UV_TARGET}/uvx" /usr/local/bin/ && \
#     rm -rf /tmp/uv.tar.gz "/tmp/uv-${UV_TARGET}"
#
# Example (Rust, via a pinned rustup with its checksum checked; a project's
# rust-toolchain.toml can still select another version, which rustup fetches at runtime):
#
#   ARG RUSTUP_VERSION=1.29.3
#   ARG RUST_VERSION=1.99.1
#   ENV RUSTUP_HOME=/usr/local/rustup
#   ENV CARGO_HOME=/usr/local/cargo
#   ENV PATH=/usr/local/cargo/bin:$PATH
#   RUN ARCH=$(dpkg --print-architecture) && \
#     case "$ARCH" in \
#       arm64) RUST_TARGET=aarch64-unknown-linux-gnu; RUSTUP_SHA256=9f608c142e0e38a78957d0661ba1dfaf0b6fb37184cfaa4b9a0aa57af6184282 ;; \
#       amd64) RUST_TARGET=x86_64-unknown-linux-gnu; RUSTUP_SHA256=b1c8cb14e30889e7e2999e6b69e62d9e9b9ffc0f4df8180564d306d9680e6c55 ;; \
#       *) echo "unsupported architecture: $ARCH" >&2 && exit 1 ;; \
#     esac && \
#     wget -O /tmp/rustup-init "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/${RUST_TARGET}/rustup-init" && \
#     echo "${RUSTUP_SHA256}  /tmp/rustup-init" | sha256sum -c - && \
#     chmod +x /tmp/rustup-init && \
#     /tmp/rustup-init -y --no-modify-path --profile minimal --default-toolchain "${RUST_VERSION}" \
#       --component rustfmt --component clippy --component rust-analyzer --component rust-src && \
#     rm /tmp/rustup-init && \
#     chown -R node:node "$RUSTUP_HOME" "$CARGO_HOME"
#
# Remember: whatever registries this toolchain needs (PyPI, crates.io, RubyGems, the Go
# module proxy, etc.) also need adding to EXTRA_DOMAINS in init-firewall.sh, or installs
# will fail at container runtime even though this build step succeeds (builds aren't
# firewalled — only the running container is).
# ---------------------------------------------------------------------------

# Provides pnpm and yarn at the version each project's packageManager field pins.
RUN corepack enable

# Set up non-root user
USER node

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

# Set the default shell to zsh rather than sh
ENV SHELL=/bin/zsh

# Set the default editor and visual
ENV EDITOR=nano
ENV VISUAL=nano

# Default powerline10k theme
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# Install Claude
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Pin GitHub's SSH host keys so `git` over SSH doesn't fail with "Host key verification
# failed" (no interactive prompt to accept them). Fetched at build time — builds aren't
# firewalled — from the same api.github.com/meta endpoint init-firewall.sh trusts for
# GitHub's IP ranges. Only matters if the project opts into an SSH key; see the skill.
RUN mkdir -p -m 700 /home/node/.ssh && \
  wget -qO- https://api.github.com/meta | jq -r '.ssh_keys[] | "github.com " + .' > /home/node/.ssh/known_hosts && \
  test -s /home/node/.ssh/known_hosts


# Copy and set up firewall script, plus the on-demand web-research toggle
COPY init-firewall.sh web-research-toggle.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/web-research-toggle.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh, /usr/local/bin/web-research-toggle.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall
USER node
