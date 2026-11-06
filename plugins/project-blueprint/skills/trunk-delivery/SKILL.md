---
name: trunk-delivery
description: Trunk-based branching, merging, deploy and release rules. Use when creating or naming a branch, starting work while on `main`, merging a PR, deploying or promoting to an environment, cutting a release or hotfix, or writing CI deploy workflows.
---

# Trunk delivery

One trunk, short-lived branches, environments as deploy targets. Every rule below has a reason; the reasons are in [Why](#why) so the rules stay scannable.

## Branches

- **`main` is the only long-lived branch.** A repo whose trunk is still `master` keeps it until a rename is scheduled; read `main` as "the trunk" below, and in the workflow templates.
- **Work branches** are `<type>/<issue#>-<slug>`: type is one of `feat`, `fix`, `chore`, `docs`, `ci`, `refactor`, `research`. Drop `<issue#>-` only for a chore with no issue. Example: `fix/251-supporting-content-panels`.
- **A work branch lives days, not weeks.** Unfinished behaviour ships to `main` behind a flag that defaults off.
- **`/mattpocock-skills:implement-spec`'s integration branch** is `spec/<issue#>-<slug>`. It may outlive the days-not-weeks rule while the spec is in progress. The per-ticket branches `implement-spec` creates in worktrees are its own and keep whatever names it gives them; they merge into the integration branch only.
- **Bot branches** (`dependabot/*`) are exempt from the naming rule.

### Before committing

Check the current branch. On `main`, create a work branch first: `/mattpocock-skills:implement` commits to whatever branch is checked out. The lefthook pre-commit hook refuses commits on the trunk as a backstop; the first commit of an empty repo is allowed.

## Merging

1. Rebase or merge `main` into the branch until it is current.
2. `just check` passes locally.
3. Run `mattpocock-skills:code-review` with `main` as the fixed point; fix what it finds. (Claude Code also ships a built-in `code-review`; this step means the mattpocock-skills one, which reviews against `CODING_STANDARDS.md` and the issue.)
4. Open the PR with a body shaped by `pr`, closing its issue (`Closes #N`).
5. CI `check` is green.
6. **Squash merge.** The branch is deleted on merge.

Set the repo up for this once:

```sh
gh repo edit --enable-squash-merge --enable-merge-commit=false --enable-rebase-merge=false --delete-branch-on-merge
```

Branch protection is not available on private repos on GitHub Free. There, the gate is CI plus this convention; record that in `docs/delivery.md` so nobody assumes a protection that does not exist. On public repos and paid plans, add a ruleset on `main` requiring a PR and the `check` status. Rulesets and Environments are set in the GitHub UI: hand them to the user with `wizard`.

## Deploys (services)

- **Environments are deploy targets, never branches.** There is no `develop`, `staging` or `production` branch.
- **Build once, promote the same artifact.** A push to `main` runs `check`; when it passes, `just package` builds one artifact tagged `main-<sha>`. Every environment deploys that artifact; nothing rebuilds it.
- **Dev is automatic.** The new artifact deploys to `development` if its commit is still the tip of `main`; an older commit that finishes late never overwrites a newer one.
- **Prod is a named promotion.** `deploy-production` is a `workflow_dispatch` taking an **existing** artifact tag. It plans by default and applies only when `apply` is ticked. It fails on any ref other than `main`, and on an artifact whose commit is not on `main`. It declares `environment: production`, so reviewers can be added later with no workflow change.
- **A deploy runs the artifact's own commit's deploy code**, the pairing dev ran. A rollback is promoting an older artifact, and brings that commit's deploy code with it.
- **Applies are serialized per deployable and environment**, plans queue separately, and an in-progress deploy is never cancelled.
- **Dev and prod credentials are kept apart.** With GitHub Environments, each environment holds its own secrets. Without them (private repos on GitHub Free), see "Without GitHub Environments" in the reference below before writing any deploy workflow.
- **A new environment** (staging, a demo) is a deploy target plus a dispatch or job calling `deploy-environment`. It never gets a branch.

The templates, what may be adapted in them, and the `just` recipe contract they call are in [`references/deploy-workflows.md`](references/deploy-workflows.md). Read it before writing or changing any deploy workflow.

## Releases (libraries)

- A release is a `vX.Y.Z` tag on a commit already on `main`. `release.yml` verifies that ancestry, runs `check`, then `just publish`.
- Version by semver. A `release/X.Y` branch exists only while an old major is still supported, and receives cherry-picks from `main`, never the reverse.

## Hotfixes

A hotfix is an ordinary `fix/` branch merged to `main`, then promoted. Rolling back instead means promoting an older artifact (see Deploys). A fix that lands anywhere but `main` is lost on the next deploy.

## Why

- **A branch is not a gate.** Nothing checks it is current, nothing records who promoted what, and promotion-by-merge gets forgotten: a common outage is a fix merged to trunk that never reached the environment branch. A dispatch records who promoted which artifact and when.
- **A rebuilt artifact is not the one that was tested.** Unpinned base images and OS packages drift between builds.
- **Dev deploys automatically so it means "trunk".** A manual step lets dev drift, and then "works on dev" proves nothing.
- **Prod is explicit because timing is a decision.** Decisions need a named action, not a side effect of a merge.
- **Squash merge** keeps `main` one commit per PR, so a revert is one commit and `git log` reads as a changelog.
