# agentic-dev-plugins

Public Claude Code plugins for agentic development workflows.

## Install

```
/plugin marketplace add rcodesmith/agentic-dev-plugins
/plugin install podman-sandbox@agentic-dev-plugins
```

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
