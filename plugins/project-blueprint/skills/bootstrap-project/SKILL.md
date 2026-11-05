---
name: bootstrap-project
description: Set up a new or existing repo to the project blueprint (standard commands, quality gates, trunk delivery, sandbox), then hand off to mattpocock-skills and podman-sandbox setup.
disable-model-invocation: true
---

# Bootstrap a project

Bring a repo up to the blueprint. The rules are in [`../../blueprint/rules.md`](../../blueprint/rules.md); the language defaults in [`../../blueprint/languages/`](../../blueprint/languages/); the files to copy in [`../../templates/`](../../templates/). This skill applies them; it does not restate them.

The plugin declares `mattpocock-skills` as a dependency, so it is installed with it. The `podman-sandbox` plugin is optional.

## 1. Explore

Read what exists; assume nothing. Settle each of these, with evidence:

- **Empty or existing?** An existing repo keeps its tools; the standard recipes wrap them (rule CMD-4).
- **Language(s)**: from `pyproject.toml`, `go.mod`, `package.json`, `Cargo.toml`, or the user's answer when the repo is empty. One pack per language; a polyglot repo gets one root `justfile` whose recipes call each part.
- **Kind**: service (deploys), library (publishes), or tool (neither). This picks the CMD-2 recipes and the workflow templates.
- **Deploy target** for a service: where `package` pushes and what `deploy` drives (Terraform, SST, a container host). Ask; do not guess.
- **GitHub**: `gh repo view --json nameWithOwner,visibility,defaultBranchRef` for visibility and the trunk's name. Ask the user for the plan (Free, Pro, Team): `gh` cannot read it, and it decides whether rulesets, Environments and required reviewers exist (TRUNK-6).
- **Where the developer works**: natively, in a VM, in a devcontainer or in the podman sandbox. The blueprint works in all of them; ask whether they want the podman sandbox (the SBX rules apply only if so).
- **The tools are present.** `just`, `lefthook`, `gitleaks` and the pack's toolchain must run where you are. If one is missing, give the user the pinned versions to install their own way and wait; inside the podman sandbox, a missing toolchain means its image needs the pack's **Podman sandbox** additions and a rebuild.
- **Current branch.** On an existing repo with commits, create `chore/bootstrap` (or `chore/<issue#>-bootstrap`) before writing anything.

Done when every bullet has an answer.

## 2. Confirm the plan

Show the user, in one message: the files you will create or change, the recipe-to-tool mapping, which workflow templates apply, and anything you will leave as-is because the repo already does it differently. Wait for a yes.

## 3. Lay down the skeleton

This step owns AGENT-1, AGENT-5, AGENT-6, CMD-1, CMD-2, CMD-4, TOOL-1 to TOOL-3, GATE-1 to GATE-5, TRUNK-3 to TRUNK-6, and RUN-1 to RUN-4 for a service.

- **A new project** first runs its pack's **New project** commands.
- `CLAUDE.md`: create it if neither `CLAUDE.md` nor `AGENTS.md` exists. Keep it a router: what the repo is, `just` as the entry point, pointers to `CODING_STANDARDS.md` and `docs/`. Write it with `writing-for-agents`. `/setup-matt-pocock-skills` adds the `## Agent skills` block later.
- `README.md` (with Prerequisites, AGENT-6), the pack's pin files, `justfile`, `lefthook.yml`, `.editorconfig`, `.gitignore` (template plus the pack's additions), `CODING_STANDARDS.md`, lint config.
- **Pins**: resolve every version the pack names to the exact latest release (`gh release list --repo <owner>/<tool> --limit 1`, or the language's own release index), and use the same versions in the pin files, `.github/actions/setup/action.yml` and the README's Prerequisites.
- `.github/actions/setup/action.yml` with the pack's **CI setup** steps added, and `.github/workflows/` from the templates for the project's kind, adapted only as [`deploy-workflows.md`](../trunk-delivery/references/deploy-workflows.md) allows, and `.github/dependabot.yml`.
- **Services**: stub the `package` and `deploy` recipes for the deploy target.
- `docs/delivery.md` for every kind, answering TRUNK-6. For a service, follow "Without GitHub Environments" in `deploy-workflows.md` if the plan lacks them.
- Leave `GLOSSARY.md` and `docs/adr/` alone: `domain-modeling` creates them when a term or decision first needs one.

Done when every rule this step owns passes its check, or is N/A for this project's kind.

## 4. Verify

Run `just setup`, `just check`, and `actionlint`. All pass, and `lefthook` reports the pre-commit hook installed. On a new project with no code yet, add one trivial test so `test` has something to run.

If `just secrets` finds a leak in an existing repo's history, stop and tell the user: the secret must be **rotated** first. Once it is, add each finding's fingerprint to `.gitleaksignore` (gitleaks prints it) so `check` goes green without hiding new leaks.

Fix and re-run until green; a red `check` is not a finished bootstrap.

## 5. Hand off

These steps belong to other skills or to the user. Present them as a numbered list, in this order, marking which you can run and which the user must:

1. **`/setup-matt-pocock-skills`**: the user types it (it is user-invoked only). It writes the `## Agent skills` block into `CLAUDE.md`, the `docs/agents/` files and, when `triage` is installed, the labels.
2. **Podman sandbox**, only if the user wants it: install the `podman-sandbox` plugin if needed, then invoke its skill to create `.devcontainer-podman-sandbox/`. Feed it the language pack's **Podman sandbox** section and the TOOL-1 versions (SBX-2, SBX-3). Bringing the container up and `claude auth login --claudeai` are the user's, on the host.
3. **GitHub settings**: run the `gh repo edit` command in `trunk-delivery`'s Merging section. Environments, deploy secrets and rulesets are in the GitHub UI: offer `wizard` to walk the user through them.
4. **Commit** once steps 1 and 2 (if taken) are done, so their files are included, on the bootstrap branch, and open a PR with `pr`. An empty repo's first commit goes straight to `main`.
5. **Next**: `/grill-with-docs` to start the glossary once there is a first feature to talk about, and `/project-doctor` to confirm nothing is left open.
