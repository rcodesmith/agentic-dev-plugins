# agentic-dev-plugins

Public Claude Code plugins for agentic development workflows.

## Install

```
/plugin marketplace add rcodesmith/agentic-dev-plugins
/plugin install podman-sandbox@agentic-dev-plugins
/plugin install project-blueprint@agentic-dev-plugins
```

`project-blueprint` also installs `mattpocock-skills` from `claude-plugins-official`, which this
marketplace allows as a cross-marketplace dependency.

## Plugins

- **podman-sandbox** — Run Claude Code in `--permission-mode auto` inside a Podman
  devcontainer, using a default-deny egress firewall as the real security boundary
  instead of per-directory prompts. The safety classifier stays active and can still
  refuse risky actions; what's relaxed is just the directory-scope restriction that
  would otherwise prompt on every path outside the workspace or shell commands where
  the auto mode classifier cannot determine the path. Ships a skill that walks
  through installing the pattern into a new project (adapting a Dockerfile/firewall
  allowlist for that project's toolchain) plus a `templates/` folder of starter files
  and a set of `podman-sandbox-*` CLI commands for day-to-day use.
- **project-blueprint** — One blueprint for every project: standard `just` commands, quality
  gates, trunk-based delivery and promote-by-dispatch deploys, across Python, Go, TypeScript
  and Rust. Builds on [mattpocock-skills](https://github.com/mattpocock/skills); works with or
  without podman-sandbox. See
  [its README](plugins/project-blueprint/README.md).
