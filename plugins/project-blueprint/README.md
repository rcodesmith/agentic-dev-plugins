# project-blueprint

One blueprint for every project, whatever the language: the same commands, the same quality gates, the same branching and deploy model. It sets up new repos, brings existing ones in line, and audits them later. Python, Go, TypeScript and Rust are supported.

## What you get

**Skills**

| Skill | Invoked by | Does |
|---|---|---|
| `/bootstrap-project` | you | Brings a new or existing repo up to the blueprint, verifies it with a green `just check`, then hands off to `/setup-matt-pocock-skills` |
| `/project-doctor` | you | Audits a repo against every rule and reports pass, fail or N/A with evidence, then offers fixes |
| `trunk-delivery` | the agent | Applies the branching, merging, deploy, release and hotfix rules whenever the agent branches, merges or touches a deploy |
| `contract-drift` | the agent | Guards files copied between repos (a GraphQL or OpenAPI schema) with a CI check that goes red when the copy goes stale |

**In every project it sets up**

- **Standard commands.** A root `justfile` with `setup`, `fmt`, `fmt-check`, `lint`, `typecheck`, `test`, `build`, `secrets` and `check`, the same names in every language. Existing repos keep their tools; the recipes wrap them.
- **Language bootstrapping.** Per-language defaults for formatter, linter, type checker, test runner, lint config, `.gitignore` and Dependabot ecosystem:
  - Python: uv, ruff, pyright, pytest
  - Go: golangci-lint, `go test`
  - TypeScript: pnpm, Biome, `tsc`, Vitest
  - Rust: rustfmt, Clippy, `cargo test`
- **Pinned tools.** Every tool is pinned at an exact version in the language's own pin file (`.python-version`, `go.mod`, `.node-version`, `rust-toolchain.toml`) and in one CI setup action. How you install them on your machine is up to you.
- **A pre-commit hook** ([lefthook](https://github.com/evilmartians/lefthook)) that checks formatting and lint, scans staged changes for secrets with gitleaks, and refuses commits directly on `main`.
- **CI** that runs `just check` on every PR and every push to `main`, including a secrets scan of the full history.
- **Dependabot** for the language ecosystem and GitHub Actions, grouped, with a cooldown.
- **Trunk-based delivery.** `main` is the only long-lived branch. Short `<type>/<issue#>-<slug>` branches are squash-merged after review. Releases are tags.
- **Build once, promote the same artifact.** Services build one artifact per `main` commit, deploy it to dev automatically, and promote that same artifact to prod by a manual, plan-first dispatch. Libraries publish on a `vX.Y.Z` tag.
- **Runtime basics for services.** Config from the environment that fails loud when unset, structured JSON logs, and a health endpoint.
- **Agent orientation.** A short `CLAUDE.md`, a `README.md` with prerequisites and quickstart, and a `CODING_STANDARDS.md` that holds judgement calls only (mechanical rules go in lint config).
- **A rulebook** (`blueprint/rules.md`). Every rule has a check, so `/project-doctor` can audit any repo against the blueprint.

## How you work is up to you

The blueprint does not depend on where you develop: natively on a laptop, in a VM, in a devcontainer, or in the [`podman-sandbox`](../podman-sandbox) plugin. If you use the podman sandbox, each language pack says what the sandbox image needs, and the SBX rules keep it in step with the project's pins.

## Install

```
/plugin marketplace add rcodesmith/agentic-dev-plugins
/plugin install project-blueprint@agentic-dev-plugins
```

Installing it also installs [`mattpocock-skills`](https://github.com/mattpocock/skills): issue tracker, triage, glossary and ADRs, specs and tickets, TDD, code review, PR bodies. The blueprint points to those skills rather than duplicating them.

## Layout

- `blueprint/rules.md`: every rule, with its check and owner. Bootstrap and doctor both read it.
- `blueprint/languages/`: per-language tools, pins, `justfile`, lint config, CI setup and optional podman-sandbox values.
- `templates/`: files copied into projects, including the GitHub workflows and the CI setup action.
