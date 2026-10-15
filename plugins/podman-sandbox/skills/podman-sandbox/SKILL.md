---
name: podman-sandbox
description: Set up (or work inside) a Podman devcontainer that runs Claude Code in auto mode with the directory-scope restriction relaxed, using a default-deny egress firewall as the real security boundary instead of per-directory prompts. Use when a user wants to sandbox Claude Code for a project, asks to "set up the podman sandbox", "install the sandbox pattern here", or is working inside an already-installed sandbox and hits one of the known issues this skill documents (OAuth login failing, Playwright MCP browser not found, firewall blocking something unexpectedly).
---

# Podman sandbox

Runs Claude Code with `--permission-mode auto` (not `--dangerously-skip-permissions`)
inside a Podman container with a default-deny egress firewall. Auto mode's safety
classifier stays fully active — it can still refuse or flag risky actions on its own.
What's relaxed is only `blockReadsOutsideWorkingDirectories`, the setting that
otherwise prompts on every path outside the workspace or shell commands where the
auto mode classifier cannot determine the path; once the
container's filesystem and network access are themselves tightly scoped, that
directory-scope check is redundant friction, so the container + firewall — not the
classifier — is the actual security boundary against untrusted network/filesystem
access.

Adapted from Anthropic's own reference devcontainer
(`https://github.com/anthropics/claude-code/tree/main/.devcontainer`).

This skill has two jobs: **installing** the pattern into a new project (this file's
main content), and **carrying forward hard-won debugging knowledge** for working
inside an already-installed sandbox (the Troubleshooting section) — several of these
bugs produce no useful error on their own and took real debugging time to pin down.

## Prerequisites (one-time, per machine)

- Podman, with the machine given enough memory to build comfortably:
  ```
  podman machine stop && podman machine set --memory 4096 && podman machine start
  ```
- `@devcontainers/cli`: `npm install -g @devcontainers/cli`
- Don't use VS Code's/Cursor's own Dev Containers UI for this — their Podman support
  has reported rough edges. Drive `devcontainer`/`podman` from the terminal instead.
- Run `scripts/install-cli.sh` (from wherever this plugin is installed) once, and
  again after any plugin update, to get stable `podman-sandbox-*` commands on `PATH`
  (the plugin's own install path is versioned, so these symlinks are what makes the
  commands version-independent). See that script's own comments for exactly what it
  creates.
- Optionally, a `.env.podman-sandbox-secrets` file at a project's workspace root, if
  the agent needs runtime credentials inside the sandbox (GitHub PAT, Grafana token,
  AWS creds, etc.) — see "Secrets" below. Per-project, not shared.

## Installing this into a new project

Do NOT just copy the template files blind — the two steps below need real judgment
about the specific project, not just mechanical copying.

1. **Create `.devcontainer-podman-sandbox/` in the target repo** and copy in this
   plugin's `templates/Dockerfile`, `templates/init-firewall.sh`,
   `templates/web-research-toggle.sh`, and `templates/devcontainer.json` unchanged
   as a starting point.

2. **Inspect the target repo and adapt the Dockerfile's toolchain section.** Look for
   `pyproject.toml`/`requirements.txt` (Python), `package.json` (Node — already
   covered by the Node 20 base image, usually nothing to add), `go.mod` (Go),
   `Cargo.toml` (Rust), `Gemfile` (Ruby), etc. Add whatever the project needs to
   build/run in the marked `CUSTOMIZE HERE` section of the Dockerfile. Prefer a
   pinned static-binary release over piping a shell installer, same reasoning as the
   Dockerfile's own existing tools (reproducible, auditable; a `curl|sh` installer
   downloaded fresh on every build is neither).

3. **Add matching entries to `EXTRA_DOMAINS` in `init-firewall.sh`.** Whatever
   registry the toolchain above needs to reach at container *runtime* (not build
   time — builds aren't firewalled, only the running container is) needs to resolve
   through this allowlist or installs will fail with no obvious reason why. Common
   ones: PyPI (`pypi.org`, `files.pythonhosted.org`, `astral.sh` for `uv`), Rust
   (`crates.io`, `static.crates.io`), Go (`proxy.golang.org`, `sum.golang.org`),
   RubyGems (`rubygems.org`). GitHub release-asset downloads (e.g. a toolchain's own
   release tarball) redirect through `objects.githubusercontent.com`, which isn't
   covered by the GitHub IP ranges already in the base allowlist — add it if the
   toolchain installs via a GitHub release.

4. **Ask the user two separate secrets questions.** First, what must *never* be set
   inside the container at all — API keys, broker/vendor credentials, cloud
   credentials, anything that turns "safe to run unattended" code into code that
   reaches a real external account. Write this list into a short section of this
   project's own `.devcontainer-podman-sandbox/README.md`. Second, what the agent
   *does* legitimately need at runtime (e.g. a scoped GitHub PAT for `gh`/`git push`)
   — those go in `.env.podman-sandbox-secrets` at the workspace root, see "Secrets"
   below; make sure it's covered by `.gitignore` before anything is written to it.

5. **Bring it up and verify the firewall is actually restrictive**:
   ```
   cd <target-repo>
   devcontainer up --workspace-folder . --config .devcontainer-podman-sandbox/devcontainer.json --docker-path podman
   ```
   From inside (`devcontainer exec ... -- bash`), confirm `curl -m5 https://example.com`
   fails and whatever package manager you added works (e.g. `pip install` / `cargo
   search` / `go list` against its registry).

6. **Log in** (see "Claude Code auth" below — do NOT use the default login flow or
   `claude setup-token`) and **run `podman-sandbox-start` from inside the target
   repo** going forward.

## Daily usage (once installed)

```
cd <project>
podman-sandbox-start                    # bring up + attach
podman-sandbox-start --remote-control   # pass extra claude flags through
podman-sandbox-research-on              # from a separate terminal, while a session is running
podman-sandbox-research-off
podman-sandbox-cleanup                  # remove stopped sandbox containers, any project
```

Each project gets its own container identity (named config volume keyed off the
workspace path) — auth, installed MCP servers, plugins, and the secrets file don't
carry over between projects by design.

To point any of these at a project other than the current directory, add
`--workspace <path>` (useful for running a quick command against a project you're not
currently sitting in).

## Claude Code auth

**Use `claude auth login --claudeai` inside the container, not the default
first-run login flow and not `claude setup-token`.**

The default browser-based login tries to redirect to a listener on `127.0.0.1`
*inside the container's own network namespace* — your host browser can't reach that,
so it fails with "Sign-in did not complete" and nothing useful in the terminal.
`claude setup-token` sidesteps that (mint a token on the host, inject via
`--remote-env` per session) but does **not** register the session the same way a real
login does — if you ever want Remote Control, sessions authenticated this way won't
show up in Claude Desktop (`claude auth status` reports `authMethod: "oauth_token"`
instead of `"claude.ai"`).

`claude auth login --claudeai` uses a different flow: the redirect goes to a real
hosted page (`platform.claude.com/oauth/code/callback`), which shows a code to paste
back into the terminal (`Paste code here if prompted >`) instead of trying a local
redirect. This works from inside the container, and persists in the
`claude-code-config-*` named volume — survives container recreation, so it's a
one-time thing per project:

```
devcontainer exec --workspace-folder . --config .devcontainer-podman-sandbox/devcontainer.json --docker-path podman -- claude auth login --claudeai
```

Remote Control (`claude --remote-control`) works once logged in this way. Requires a
Pro/Max/Team/Enterprise plan; API keys aren't supported.

## Secrets

Not wired up by default — no credentials mounted or baked in. Any runtime credential
the agent needs inside the container (GitHub PAT, Grafana token, AWS creds, whatever
the project uses) goes in one file at the **workspace root** (not inside
`.devcontainer-podman-sandbox/`): `.env.podman-sandbox-secrets`, plain `KEY=VALUE`
lines, one per secret. It's per-project, not shared, and optional — nothing is
injected if the file doesn't exist.

1. Create the file and add whatever's needed, e.g. `GH_TOKEN=ghp_...`. If one of the
   entries is a GitHub PAT, use a **fine-grained, scoped** one — limited
   repos/permissions, with an expiration, not a broad personal token: `research-on`
   mode means a compromised dependency could reach anywhere this token can.
2. `chmod 600 .env.podman-sandbox-secrets`.
3. Make sure it's git-ignored. `podman-sandbox-start` double-checks both the
   permission and the git-ignore status at every launch and **refuses to use the
   file** (hard error, not a silent skip) if either check fails.

`podman-sandbox-start` passes the file straight to `podman exec --env-file`, never as
a `--remote-env`-style command-line argument — a value passed that way sits in the
`devcontainer`/`podman exec` process's own argv, visible via `ps` to any local
process, for the entire session. The file itself still lives briefly on disk in
plaintext (mode 600, never committed) — a smaller exposure than a live cleartext
argv, but not nothing; don't put a project using this file inside a folder that syncs
to cloud storage or gets backed up unencrypted.

Run `gh auth setup-git` once per session (inside the container) if `GH_TOKEN` is one
of the entries and you also want `git push`/`pull` over HTTPS to work, not just
`gh`/API calls.

## Optional: browser automation (Playwright MCP)

Not installed by default — adds real image size and a specific gotcha (below). If
wanted:

1. Add to the Dockerfile (pin both versions, and make sure they match — see next
   point):
   ```
   ARG PLAYWRIGHT_MCP_VERSION=0.0.83
   ARG PLAYWRIGHT_VERSION=1.64.0-alpha-1790635538000
   RUN npm install -g @playwright/mcp@${PLAYWRIGHT_MCP_VERSION}
   USER root
   RUN npx -y playwright@${PLAYWRIGHT_VERSION} install-deps chromium
   USER node
   RUN npx -y playwright@${PLAYWRIGHT_VERSION} install chromium
   ```
2. **`PLAYWRIGHT_VERSION` must exactly match `@playwright/mcp`'s own `playwright`
   dependency** — check with `npm view @playwright/mcp@<version> dependencies`.
   `@playwright/mcp` often pins to an alpha snapshot of the *next* Playwright release,
   not whatever's currently tagged `latest` on the standalone `playwright` package —
   installing "latest stable" chromium instead can silently install the wrong browser
   revision for what `@playwright/mcp` expects at runtime.
3. **Known gotcha**: `@playwright/mcp` defaults to launching the *real Google Chrome*
   channel (`--browser chrome`, looking for `/opt/google/chrome/chrome`), not the
   bundled Chromium that actually gets installed above. Real Chrome isn't installed
   (keeps the image smaller), so the MCP server fails at init with `Chromium
   distribution 'chrome' is not found`, and its own suggested fix
   (`npx playwright install chrome`) fails too — it needs non-interactive root
   (`apt-get`) that this container doesn't grant. Fix: register the MCP server with
   an explicit `--executable-path` pointing at the bundled binary instead:
   ```
   devcontainer exec --workspace-folder . --config .devcontainer-podman-sandbox/devcontainer.json --docker-path podman -- \
     claude mcp add --scope user playwright -- npx @playwright/mcp@0.0.83 \
     --headless --browser chrome \
     --executable-path /home/node/.cache/ms-playwright/chromium-<rev>/chrome-linux-arm64/chrome \
     --no-sandbox
   ```
   Find `<rev>` with `find ~/.cache/ms-playwright -iname '*chrome*' -type f` inside
   the container — it's a version-specific directory name tied to `PLAYWRIGHT_VERSION`,
   re-check it any time that pin changes. `--scope user` persists the registration in
   the same named volume as auth, so it's one-time per project. `--no-sandbox` is
   needed because Chrome's own internal sandboxing wants kernel features this
   container doesn't grant by default.
4. A currently-running `claude` session won't see a newly-registered MCP server —
   MCP servers load at process start. Restart it: `/exit`, then
   `podman-sandbox-start --continue` (resumes the same conversation).
5. Navigating anywhere **not** on the firewall allowlist still needs
   `podman-sandbox-research-on` first, same as any other outbound request.

## Troubleshooting

- **`init-firewall.sh` aborts mid-run with an `ipset` error.** CDN-backed domains can
  resolve to the same IP as each other across separate `dig` calls within the script
  — a plain `ipset add` errors on that duplicate and, under `set -e`, aborts the
  whole script. The template here already uses `ipset add ... -exist` for this; if
  you're diagnosing a copy that doesn't have that yet, that's the fix.
- **A newly installed plugin or MCP server doesn't show up in an already-running
  session.** Both load at `claude` process startup, not hot-reloaded. Restart:
  `/exit`, then `podman-sandbox-start --continue` to resume the same conversation
  (or `--resume` for an interactive picker if there's more than one recent session).
- **The firewall allowlist resolves hostnames to IPs once, at container start.** If a
  CDN-backed allowlisted host rotates IPs during a long-lived session, egress to it
  can start failing until the container restarts and `init-firewall.sh` re-resolves.
- **Making a host plugin/skill (e.g. one installed via `claude plugin install`)
  available inside the container**: the container's `~/.claude` is an isolated named
  volume, not your host's real one — install it again inside the container,
  `--scope user`, same marketplace/plugin name as the host. Find what's on the host
  first with `claude plugin marketplace list` / `claude plugin list` so the container
  matches exactly (same marketplace source, same plugin), rather than guessing.
