# Deploy workflows

The workflow templates are in [`../../../templates/github/workflows/`](../../../templates/github/workflows/). All project-specific behaviour lives behind three `just` recipes, so the templates are copied as they are, apart from the adaptations listed below.

| Template | Trigger | Does |
|---|---|---|
| `check.yml` | PR, push to `main`, `workflow_call` | `just setup` then `just check` |
| `build.yml` | `check` succeeding on a push to `main` | `just package main-<sha>`, then deploys that tag to `development` if the commit is still the tip of `main` |
| `deploy-environment.yml` | `workflow_call` only | `just deploy <env> <artifact> <plan\|apply>`, serialized per deployable and environment |
| `deploy-production.yml` | `workflow_dispatch` | refuses non-`main` refs, then calls `deploy-environment` for `production` |
| `release.yml` | push of tag `v*.*.*` | verifies the tag's commit is on `main`, calls `check`, `just publish <version>` |

Services take the first four; libraries take `check.yml` and `release.yml`; tools take `check.yml`.

## What may be adapted

- **The trunk name**, where the repo keeps `master`: every `main` in every template.
- **`id-token: write`**, which the templates grant for OIDC to the cloud. Called workflows can only narrow the caller's permissions, so it is removed from `build.yml`, `deploy-production.yml` and `deploy-environment.yml` **together**, or not at all.
- **Monorepos**: one `build.yml` per deployable, with `paths:` filters, its own artifact prefix (`web-main-<sha>`), and `deployable: web` passed to `deploy-environment`, so each deployable queues separately.
- **The build-once exception** below, when the framework forces it.

Anything else is a change to the blueprint, not to the project.

## The recipe contract

- **`package ARTIFACT`** builds the deployable thing once and pushes it where every environment can fetch it (a container registry, an S3 bucket), tagged `ARTIFACT`. It is the only recipe that builds.
- **`deploy ENV ARTIFACT MODE`** deploys an artifact that already exists. MODE is `plan` (show what would change, touch nothing) or `apply`. It **fails before doing anything** when `ARTIFACT` is not found in the target's registry; it never falls back to building.
- **`publish VERSION`** publishes a library at VERSION, after checking VERSION matches the project's own version field. Prefer the registry's trusted publishing (OIDC) where the publishing tool supports it; otherwise use a scoped token held in the `release` environment.

Credentials reach these recipes as environment variables (prefer OIDC to the cloud over long-lived keys). The templates pass every input through `env:`, never by `${{ }}` inside `run:`: a dispatch input is user-controlled text, and interpolating it into shell is script injection.

## Plan-then-apply

With `apply` unticked, a prod dispatch only plans. The operator reads the plan, then dispatches again with `apply` ticked. The second run **plans again** and applies that new plan; it matches the reviewed one unless prod drifted between the runs, so read the apply run's own plan output.

## The gate is only as strong as the plan allows

The `require-main` job stops accidental dispatches from feature branches, which would run unreviewed deploy code. It is not a security boundary: the workflow file is read from the dispatched ref, so someone with write access can push a branch without the check. Only required reviewers on the `production` environment close that gap, and those need a public repo or a paid plan. Where they are unavailable, say so in `docs/delivery.md`.

## Without GitHub Environments

GitHub's documentation says GitHub Free offers environments on public repositories only; some private Free repos have been seen using them anyway. Test it: create an environment in the repo's settings and see whether a job naming it can read its secrets. Record the answer in `docs/delivery.md`.

Without environments, every secret is a repo secret, and `secrets: inherit` hands the dev deploy the prod credentials. Keep them apart in the cloud instead:

- **Separate cloud accounts or projects for dev and prod**, each trusting GitHub OIDC.
- **Name secrets by environment** (`DEVELOPMENT_ROLE_ARN`, `PRODUCTION_ROLE_ARN`), and have `just deploy` read only the variables for `ENV`.
- **Accept the residual risk out loud**: any workflow on `main` can reach prod credentials, so the gate is review of what merges to `main`. Write that sentence into `docs/delivery.md`.

`environment:` stays declared in the templates, so environments, when available, need no workflow change. Check in the same test that a job naming an environment still runs on this repo.

## Build-once exceptions

Some frameworks bake environment config into the build. Next.js inlines `NEXT_PUBLIC_*` at build time. Prefer making the build environment-agnostic (read config at runtime, from the server or a fetched config file). When that is not yet possible, the documented exception is:

- `package` runs per environment, but **only from a commit that already deployed to dev**, and the prod dispatch names that commit (`main-<sha>`) rather than a branch.
- Adapt `deploy-production.yml` to check out exactly that SHA and run `just package` for production before `just deploy`, so the code is the tested code even though the bundle is rebuilt.
- Record the exception, and the work to remove it, in an ADR.
