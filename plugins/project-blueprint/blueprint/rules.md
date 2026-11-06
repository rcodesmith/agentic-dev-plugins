# Blueprint rules

The single source of truth for what a blueprint project contains. `bootstrap-project` applies these rules; `project-doctor` checks them. Each rule has an id, the rule, the **check** that decides pass or fail, and the **owner**: where the fix lives. When the owner is another skill, fix by sending the user to that skill rather than re-implementing it here.

Language-specific values (tool names, lint config, registry domains) live in [`languages/`](languages/). Branching and deploy rules live in the `trunk-delivery` skill ([`../skills/trunk-delivery/SKILL.md`](../skills/trunk-delivery/SKILL.md)); the TRUNK rows below only check them.

A rule is **N/A** when its condition is false (a library has no deploys; a repo with no copied files has no contract). Say why in the verdict.

**Kind** is one of: **service** (deploys), **library** (publishes), **tool** (neither).

## AGENT: agent orientation

| ID | Rule | Check | Owner |
|---|---|---|---|
| AGENT-1 | One agent steering file at the root, `CLAUDE.md` (or `AGENTS.md` if that is what exists). It routes to other docs rather than explaining them. | File exists; under ~150 lines; no restated config (scripts, versions) the environment already holds. | `writing-for-agents` |
| AGENT-2 | mattpocock-skills is configured. | `CLAUDE.md` has an `## Agent skills` block; `docs/agents/issue-tracker.md` and `docs/agents/domain.md` exist. | User runs `/mattpocock-skills:setup-matt-pocock-skills` |
| AGENT-3 | Triage labels exist on the tracker. N/A when the `triage` skill is not installed (setup skips labels then). | `docs/agents/triage-labels.md` exists and `gh label list --limit 1000 --json name` contains each label it names (without `--limit`, `gh` returns only the first 30). | User runs `/mattpocock-skills:setup-matt-pocock-skills` |
| AGENT-4 | The domain glossary is `GLOSSARY.md` (or `GLOSSARY-MAP.md`), created lazily. Its absence passes; a legacy `CONTEXT.md` used as a glossary fails. | No root or per-context `CONTEXT.md` holding term definitions. | Rename, then `/mattpocock-skills:grill-with-docs` |
| AGENT-5 | `CODING_STANDARDS.md` holds judgement calls only; mechanical rules are lint config. | File exists; each entry is a rule no linter could check. | `templates/CODING_STANDARDS.md`; `/mattpocock-skills:retro` proposes moving entries into lint |
| AGENT-6 | `README.md` covers: what it is, prerequisites, quickstart, the standard commands, where docs live. **Prerequisites** lists each tool and version from TOOL-1; how to install them is the developer's choice. The quickstart is `just setup`. | All five present; the prerequisite versions match TOOL-1's pins. | This plugin |

## CMD: standard commands

| ID | Rule | Check | Owner |
|---|---|---|---|
| CMD-1 | A root `justfile` exposes the standard recipes: `setup`, `fmt`, `fmt-check`, `lint`, `typecheck`, `test`, `build`, `secrets`, `check`. `check` runs `fmt-check lint typecheck test secrets`. | `just --summary` lists every recipe. | Language pack |
| CMD-2 | Services add `run`, `package ARTIFACT` and `deploy ENV ARTIFACT MODE`. Libraries add `publish VERSION`. | Recipes present for the project's kind. | Language pack, `trunk-delivery` |
| CMD-3 | `just check` passes on a clean clone. A history leak that has been rotated is listed in `.gitleaksignore`, not left failing. | Run it. | Whoever broke it |
| CMD-4 | The recipes are the contract, not the tools. An existing repo keeps its tools (eslint, mypy, Make targets) and wraps them in the standard recipe names. | No recipe re-implements logic that already lives in `package.json`, `pyproject.toml` or a Makefile; it calls it. | This plugin |

## TOOL: toolchain

| ID | Rule | Check | Owner |
|---|---|---|---|
| TOOL-1 | Every tool the recipes, hooks and CI call is pinned at an exact version. The language toolchain uses the language's own pin file (the pack's **Pins**); the shared tools CI runs (`just`, `gitleaks`, `actionlint`) are pinned in `.github/actions/setup/action.yml`; `lefthook`, which runs only on developer machines, is pinned by the README's Prerequisites. The README's Prerequisites list every one of them for developers. How a developer installs them (Homebrew, asdf, mise, a VM image, the podman sandbox) is not prescribed. | Each binary named in the `justfile`, `lefthook.yml` and the workflows is pinned by the pack's pin file, the setup action, the lockfile, or (developer-only tools) the README's Prerequisites; no `latest` and no bare major. | Language pack, `templates/github/actions/setup/` |
| TOOL-2 | Dependencies are locked and installed from the lock. | Lockfile committed (`uv.lock`, `go.sum`, `pnpm-lock.yaml`, `Cargo.lock`); `setup` installs in locked/frozen mode. | Language pack |
| TOOL-3 | `.editorconfig` and `.gitignore` exist; `.gitignore` covers `.env*` (except `.env.example`), and the sandbox secrets when SBX applies. | Files present; `git check-ignore .env` matches, and `.env.podman-sandbox-secrets` too when SBX applies. | `templates/` |
| TOOL-4 | Pins move. Dependabot updates lockfiles and actions, but not the toolchain pin files, the setup action's versions or a sandbox's `*_VERSION` build args, so those are reviewed by hand. | Each pinned version is no more than a minor behind its latest release (`gh release view --repo <owner>/<tool> --json tagName`: the release GitHub marks latest, never a prerelease), or the gap is deliberate. A setup-action version bump comes with that release's SHA-256. | This plugin |

## GATE: quality gates

| ID | Rule | Check | Owner |
|---|---|---|---|
| GATE-1 | A pre-commit hook runs `fmt-check`, `lint`, a staged-secrets scan, and refuses commits on the trunk, through lefthook. | `lefthook.yml` matches `templates/lefthook.yml`; `just setup` installs it. | `templates/lefthook.yml` |
| GATE-2 | CI runs `just check`, `just build` and `actionlint` on every PR and on every push to the trunk. | `check.yml` triggers on `pull_request` and `push` to the trunk, runs `just check` with `fetch-depth: 0` (the secrets scan reads history), then `just build` and `actionlint`. | `templates/github/workflows/check.yml` |
| GATE-3 | Dependabot updates the language ecosystem and GitHub Actions, grouped, with a cooldown. | `.github/dependabot.yml` lists both ecosystems; each has `cooldown`. | `templates/github/dependabot.yml` |
| GATE-4 | Actions are pinned by release tag and kept current by Dependabot: the major tag (`@vN`) where the action publishes one, otherwise its exact release (`@vX.Y.Z`). SHA pinning is the stricter option. Local `./` workflow references are exempt. | Every remote `uses:` names `@vN`, `@vX.Y.Z` or a SHA, and that ref exists (`gh api repos/<owner>/<action>/git/matching-refs/tags/<tag>`); none name a branch. | `templates/` |
| GATE-5 | Workflow inputs reach shell through `env:`, never by `${{ }}` interpolation inside `run:`. | `actionlint` passes; grep `run:` blocks for `${{ inputs.` / `${{ github.event.`. | `trunk-delivery` templates |

## SBX: podman sandbox (optional)

N/A unless the project uses the `podman-sandbox` plugin. Where developers work (natively, in a VM, in a devcontainer, in the podman sandbox) is their choice; these rules only keep the sandbox correct when it is used.

| ID | Rule | Check | Owner |
|---|---|---|---|
| SBX-1 | The sandbox files are complete. | `.devcontainer-podman-sandbox/` holds `Dockerfile`, `devcontainer.json`, `init-firewall.sh`, `web-research-toggle.sh`. | `podman-sandbox` skill |
| SBX-2 | The sandbox provides the TOOL-1 versions. The shared tools come from the base image's `*_VERSION` build args; the language toolchain from `CUSTOMIZE HERE`; Node from `NODE_VERSION`. | Compare `devcontainer.json` build args and the `CUSTOMIZE HERE` section against the TOOL-1 pins. | `podman-sandbox` skill + language pack |
| SBX-3 | `init-firewall.sh` `EXTRA_DOMAINS` covers the language's runtime registries. | Every domain listed in the language pack's **Podman sandbox** section is present. | Language pack |
| SBX-4 | `.devcontainer-podman-sandbox/README.md` records what must never be set in the container, and the "First run" login steps. | Both sections present. | `podman-sandbox` skill |

## TRUNK: branching and delivery

The rules themselves are in `trunk-delivery`. These rows check them.

| ID | Rule | Check | Owner |
|---|---|---|---|
| TRUNK-1 | The trunk is the only long-lived branch. | `git for-each-ref --sort=committerdate refs/remotes --format='%(committerdate:short) %(refname:short)'` shows no `develop`, `staging` or `production`, no `release/*` except a supported old major, and no work branch older than ~2 weeks. `spec/*` and `dependabot/*` are exempt from the age limit. | `trunk-delivery` |
| TRUNK-2 | The repo merges by squash only and deletes merged branches. | `gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed,deleteBranchOnMerge`. | `trunk-delivery` |
| TRUNK-3 | No workflow deploys or publishes from a push to anything but the trunk or a release tag, and every workflow names the repo's actual trunk. | Each workflow's `on.push.branches` and ref checks name the trunk (`main`, or `master` where kept). | `trunk-delivery` |
| TRUNK-4 | Services: build once on the trunk, auto-deploy dev, promote prod by dispatch naming an existing artifact. | `build.yml`, `deploy-environment.yml`, `deploy-production.yml` present and shaped like the templates. | `trunk-delivery` |
| TRUNK-5 | Libraries: publish on a `vX.Y.Z` tag whose commit is on the trunk. | `release.yml` present and checks ancestry. | `trunk-delivery` |
| TRUNK-6 | `docs/delivery.md` records the plan (ask the user: `gh` cannot read it), whether GitHub Environments, rulesets and required reviewers are available, and for services how dev and prod credentials are kept apart. | File exists and answers each point. | `trunk-delivery`; `wizard` for the GitHub UI steps |

## CONTRACT: cross-repo contracts

| ID | Rule | Check | Owner |
|---|---|---|---|
| CONTRACT-1 | Every file copied from another repo by hand (a schema, an OpenAPI spec, a proto) has a drift check in CI. | Each copy is listed in `docs/contracts.md` with its source of truth, and `contract-drift.yml` diffs it. | `contract-drift` |

## RUN: runtime basics (services only)

| ID | Rule | Check | Owner |
|---|---|---|---|
| RUN-1 | Config comes from the environment; `.env.example` lists every variable. | `.env.example` exists and every variable the code reads is in it. | This plugin |
| RUN-2 | Required config **fails loud** when unset. No hardcoded fallback for an endpoint, credential or account. | Grep config loading for defaults on URLs, hosts, IPs and keys. A fallback that "works" sends a misconfigured deploy somewhere real. | This plugin |
| RUN-3 | Logs are structured (JSON) to stdout. | Logger config. | Language pack |
| RUN-4 | A `/health` (or equivalent) endpoint reports readiness. | Route exists. | This plugin |
