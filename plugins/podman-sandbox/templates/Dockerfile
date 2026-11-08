# Node version for the base image. Set it to the project's pinned Node, the exact version
# (e.g. 24.22.2) when the project pins one; Docker Hub tags every Node release.
ARG NODE_VERSION=24
FROM node:${NODE_VERSION}

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

# Shared dev tools every project gets: a task runner (just), git hooks (lefthook), a
# secrets scanner (gitleaks), linters for workflows and shell (actionlint, shellcheck)
# and a YAML query tool (yq). Pinned release binaries, installed
# at build time: builds aren't firewalled, so nothing here needs an EXTRA_DOMAINS entry.
ARG JUST_VERSION=1.59.0
ARG LEFTHOOK_VERSION=2.2.2
ARG GITLEAKS_VERSION=8.30.1
ARG ACTIONLINT_VERSION=1.7.12
ARG SHELLCHECK_VERSION=0.11.0
ARG YQ_VERSION=4.54.1
RUN set -eu && \
  case "$(dpkg --print-architecture)" in \
    arm64) RUST_ARCH=aarch64; GO_ARCH=arm64; GITLEAKS_ARCH=arm64 ;; \
    amd64) RUST_ARCH=x86_64;  GO_ARCH=amd64; GITLEAKS_ARCH=x64 ;; \
    *) echo "unsupported architecture" >&2 && exit 1 ;; \
  esac && \
  cd /tmp && \
  wget -qO- "https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-${RUST_ARCH}-unknown-linux-musl.tar.gz" \
    | tar -xz -C /usr/local/bin just && \
  wget -qO- "https://github.com/evilmartians/lefthook/releases/download/v${LEFTHOOK_VERSION}/lefthook_${LEFTHOOK_VERSION}_Linux_${RUST_ARCH}.gz" \
    | gunzip > /usr/local/bin/lefthook && \
  wget -qO- "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin gitleaks && \
  wget -qO- "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_${GO_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin actionlint && \
  wget -qO- "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.${RUST_ARCH}.tar.gz" \
    | tar -xz -C /tmp && mv "/tmp/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/ && rm -rf "/tmp/shellcheck-v${SHELLCHECK_VERSION}" && \
  wget -qO /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${GO_ARCH}" && \
  chmod +x /usr/local/bin/just /usr/local/bin/lefthook /usr/local/bin/gitleaks \
    /usr/local/bin/actionlint /usr/local/bin/shellcheck /usr/local/bin/yq && \
  for t in just lefthook gitleaks actionlint shellcheck yq; do "$t" --version >/dev/null; done

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
# Example (Terraform + tflint with the AWS ruleset, for the offline checks: fmt -check,
# init -backend=false, validate, tflint). Set TERRAFORM_VERSION to the version CI uses.
# Each version bump needs that release's SHA-256 from its terraform_<v>_SHA256SUMS or
# tflint checksums.txt. The ruleset plugin is fetched here at build time into
# TFLINT_PLUGIN_DIR, so tflint never downloads it at runtime; TFLINT_AWS_RULESET_VERSION
# must equal the version in the project's .tflint.hcl, or tflint reports it missing.
#
#   ARG TERRAFORM_VERSION=1.17.1
#   ARG TFLINT_VERSION=0.65.0
#   ARG TFLINT_AWS_RULESET_VERSION=0.50.0
#   ENV TFLINT_PLUGIN_DIR=/usr/local/share/tflint/plugins
#   RUN set -eu && \
#     case "$(dpkg --print-architecture)" in \
#       arm64) ARCH=arm64; TERRAFORM_SHA256=988e950a1c23058093b0e66ab2d5fb53fc18345ecfbd5871acf51dbac9325edd; TFLINT_SHA256=843017c47a98be1de4d88fa038daa293770fe25cd01656c4f08b2e30d1d3b3a0 ;; \
#       amd64) ARCH=amd64; TERRAFORM_SHA256=4638628058e71a55212b1c563712eac03b902128f40740f3dc8174df12135061; TFLINT_SHA256=d4c545ed2e29d6338604b586f34f544f380f70f243aa72f7b484713835eaec61 ;; \
#       *) echo "unsupported architecture" >&2 && exit 1 ;; \
#     esac && \
#     cd /tmp && \
#     wget -qO terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip" && \
#     echo "${TERRAFORM_SHA256}  terraform.zip" | sha256sum -c - && \
#     wget -qO tflint.zip "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_${ARCH}.zip" && \
#     echo "${TFLINT_SHA256}  tflint.zip" | sha256sum -c - && \
#     unzip -oq terraform.zip terraform -d /usr/local/bin && \
#     unzip -oq tflint.zip tflint -d /usr/local/bin && \
#     rm terraform.zip tflint.zip && \
#     printf 'plugin "aws" {\n  enabled = true\n  version = "%s"\n  source  = "github.com/terraform-linters/tflint-ruleset-aws"\n}\n' \
#       "${TFLINT_AWS_RULESET_VERSION}" > /tmp/aws.tflint.hcl && \
#     tflint --init --config /tmp/aws.tflint.hcl && \
#     rm /tmp/aws.tflint.hcl && \
#     chown -R node:node /usr/local/share/tflint && \
#     terraform version && tflint --version
#
# Remember: whatever registries this toolchain needs (PyPI, crates.io, RubyGems, the Go
# module proxy, etc.) also need adding to EXTRA_DOMAINS in init-firewall.sh, or installs
# will fail at container runtime even though this build step succeeds (builds aren't
# firewalled — only the running container is). Better still, fetch anything a tool would
# otherwise download on first use (linter plugins, rulesets) here, as the tflint example does.
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
