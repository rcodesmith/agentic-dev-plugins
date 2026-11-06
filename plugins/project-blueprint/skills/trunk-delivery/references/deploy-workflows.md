# Deploy workflows

The workflow templates are in [`../../../templates/github/workflows/`](../../../templates/github/workflows/). All project-specific behaviour lives behind three `just` recipes and the marked credentials slots, so the templates are copied as they are, apart from the adaptations listed below.

| Template | Trigger | Does |
|---|---|---|
| `check.yml` | PR, push to `main`, `workflow_call` | `just setup`, `just check`, `just build`, then `actionlint` |
| `build.yml` | `check` succeeding on a push to `main` | `just package main-<sha>`, then deploys that tag to `development` if the commit is still the tip of `main` |
| `deploy-environment.yml` | `workflow_call` only | checks out the artifact's own commit, `just setup`, then `just deploy <env> <artifact> <plan\|apply>`; applies are serialized per deployable and environment |
| `deploy-production.yml` | `workflow_dispatch` | refuses non-`main` refs and artifacts whose commit is not on `main`, then calls `deploy-environment` for `production` |
| `release.yml` | push of tag `v*.*.*` | verifies the tag's commit is on `main`, calls `check`, `just publish <version>` |

Services take the first four; libraries take `check.yml` and `release.yml`; tools take `check.yml`.

## What may be adapted

- **The trunk name**, where the repo keeps `master`: every `main` in every template.
- **Credentials**, in the places marked `CREDENTIALS` and in the recipe step's `env:` block. See [Credentials](#credentials).
- **`packages: write`** on `build.yml`'s `package` job, when the registry is GHCR.
- **`id-token: write`**, which the templates grant for OIDC to the cloud. Called workflows can only narrow the caller's permissions, so it is removed from `build.yml`'s `deploy-development` job, `deploy-production.yml`'s `deploy` job and `deploy-environment.yml` **together**, or not at all. On `build.yml`'s `package` job it is off; turn it on only when the registry login uses OIDC.
- **Monorepos**, as in [Monorepos](#monorepos).
- **The build-once exception** below, when the framework forces it.

Anything else is a change to the blueprint, not to the project.

## The recipe contract

- **`package ARTIFACT`** builds the deployable thing once and pushes it where every environment can fetch it (a container registry, an S3 bucket), tagged `ARTIFACT`. It is the only recipe that builds.
- **`deploy ENV ARTIFACT MODE`** deploys an artifact that already exists. MODE is `plan` (show what would change, touch nothing) or `apply`. It **fails before doing anything** when `ARTIFACT` is not found in the target's registry; it never falls back to building.
- **`publish VERSION`** publishes a library at VERSION, after checking VERSION matches the project's own version field, and builds the package itself first: `release.yml` runs nothing between `just setup` and `just publish`. Prefer the registry's trusted publishing (OIDC) where the publishing tool supports it; otherwise use a scoped token held in the `release` environment.

The templates pass every input through `env:`, never by `${{ }}` inside `run:`: a dispatch input is user-controlled text, and interpolating it into shell is script injection. For the same reason, declare recipe parameters with `$` (`deploy $ENV $ARTIFACT $MODE:`) so they arrive as quoted environment variables rather than `{{ }}` text spliced into the recipe's shell.

Until `package` and `deploy` are implemented, their stubs **fail** (`echo "package: not implemented" >&2; exit 1`). A stub that exits 0 turns the first merge into a green "deploy" that shipped nothing.

## Which code deploys

`deploy-environment` checks out the artifact's own commit, not the tip of `main`. Dev deployed that artifact with that commit's deploy code, so promoting it to prod repeats the pairing dev tested. Rolling back is promoting an older artifact, and its deploy code comes with it: an infrastructure change made after that commit is reverted too. When that is not wanted, roll forward with a fix instead.

## Queues

GitHub keeps at most one running and one pending run per concurrency group; a newer pending run replaces the older one, which shows as cancelled.

- **`check` on `main`** queues per commit, and `build` has no queue, so every commit whose check passes gets its artifact.
- **Dev deploys** share one queue per deployable. A waiting deploy replaced by a newer one is the intended outcome: dev follows the tip.
- **Prod applies** share one queue, and plans queue separately, so a plan never displaces a waiting apply. Two applies dispatched while a third runs leave only the newer one waiting. A plan can run while an apply holds the state lock; it then fails, and is re-run.
## Credentials

A recipe sees a secret only when the workflow names it. `secrets: inherit` makes the caller's secrets *available* to the called workflow; it does not put any of them in a step's environment. So each template marks two places:

- **The `CREDENTIALS` comment**, before the recipe step: the project's login step goes there, for example an OIDC role assumption for the cloud, or a registry login before `just package`.
- **The recipe step's `env:` block**: each secret or variable the recipe reads, by name (`DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}`).

Prefer OIDC to long-lived keys. Keep each identity as narrow as the job:

- **`package`** runs dependency installs on every `main` commit, so its role (if it has one) can push to the registry and nothing else.
- **Deploy roles** trust only tokens whose subject names their GitHub environment (`repo:<owner>/<repo>:environment:production`), so neither `package` nor a dev deploy can assume the prod role. This needs GitHub Environments; without them, see below.

## Without GitHub Environments

GitHub's documentation says GitHub Free offers environments on public repositories only; some private Free repos have been seen using them anyway. Test it: create an environment in the repo's settings and see whether a job naming it can read its secrets. Record the answer in `docs/delivery.md`.

Without environments, every secret and variable is repo-level, and `secrets: inherit` hands the dev deploy the prod credentials. Keep them apart by name and in the cloud instead:

- **Name values by environment** (`DEVELOPMENT_DEPLOY_ROLE_ARN`, `PRODUCTION_DEPLOY_ROLE_ARN`) and select them in the credentials slot with `vars[format('{0}_DEPLOY_ROLE_ARN', inputs.environment)]` (or `secrets[...]`). GitHub treats these names as case-insensitive, so `development_…` finds `DEVELOPMENT_…`; confirm that in the same test.
- **Separate cloud accounts or projects for dev and prod**, each trusting GitHub OIDC.
- **Accept the residual risk out loud**: the OIDC subject no longer names an environment, so any workflow on `main` can reach prod credentials, and the gate is review of what merges to `main`. Write that sentence into `docs/delivery.md`.

`environment:` stays declared in the templates, so environments, when available, need no workflow change. Check in the same test that a job naming an environment still runs on this repo.

## Monorepos

Each deployable gets its own `build-<name>.yml` and its own production promotion. Per deployable (here `web`, under `apps/web/`):

- **Artifact prefix**: `web-main-<sha>` in the `tag` step. `deploy-production`'s artifact check reads the commit after `main-`, so the prefix needs no change there.
- **Which deployable**: `DEPLOYABLE: web` in the `package` step's `env:`, and `deployable: web` passed to `deploy-environment`, which hands it to `just deploy` as `DEPLOYABLE` and queues each deployable separately. Production does the same: add a `deployable` `choice` input to `deploy-production.yml` (an input, not a free string), and pass it through.
- **Only build what changed.** `workflow_run` takes no `paths:` filter, so add a first job that compares this commit with the last successful run of the same workflow, and make `package` depend on it:

```yaml
  changes:
    if: github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event == 'push'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      actions: read
    outputs:
      changed: ${{ steps.diff.outputs.changed }}
    steps:
      - uses: actions/checkout@v7
        with:
          ref: ${{ github.event.workflow_run.head_sha }}
          fetch-depth: 0
      - id: diff
        env:
          GH_TOKEN: ${{ github.token }}
          WORKFLOW: ${{ github.workflow }}
          PATHS: apps/web packages/shared # the deployable and what it depends on
        run: |
          last=$(gh run list --workflow "$WORKFLOW" --branch main --status success --limit 1 --json headSha --jq '.[0].headSha // empty')
          # No earlier success, or it is gone from history: build.
          if [ -z "$last" ] || ! git cat-file -e "$last^{commit}" 2>/dev/null; then
            echo "changed=true" >> "$GITHUB_OUTPUT"
          elif git diff --quiet "$last" HEAD -- $PATHS; then
            echo "changed=false" >> "$GITHUB_OUTPUT"
          else
            echo "changed=true" >> "$GITHUB_OUTPUT"
          fi
```

`package` then takes `needs: changes` and `if: needs.changes.outputs.changed == 'true'`. Comparing with the last successful run, not the parent commit, catches a change whose own run failed.

## Plan-then-apply

With `apply` unticked, a prod dispatch only plans. The operator reads the plan, then dispatches again with `apply` ticked. The second run **plans again** and applies that new plan; it matches the reviewed one unless prod drifted between the runs, so read the apply run's own plan output.

## The gate is only as strong as the plan allows

The `require-main` job stops accidental dispatches from feature branches, which would run unreviewed deploy code. It is not a security boundary: the workflow file is read from the dispatched ref, so someone with write access can push a branch without the check. Only required reviewers on the `production` environment close that gap, and those need a public repo or a paid plan. Where they are unavailable, say so in `docs/delivery.md`.

## Build-once exceptions

Some frameworks bake environment config into the build. Next.js inlines `NEXT_PUBLIC_*` at build time. Prefer making the build environment-agnostic (read config at runtime, from the server or a fetched config file). When that is not yet possible, the documented exception is:

- `package` runs per environment, but **only from a commit that already deployed to dev**, and the prod dispatch names that commit (`main-<sha>`) rather than a branch.
- Add a job to `deploy-production.yml` between `require-main` and `deploy` that checks out `needs.require-main.outputs.sha` and runs `just package` for production, so the code is the tested code even though the bundle is rebuilt.
- Record the exception, and the work to remove it, in an ADR.
