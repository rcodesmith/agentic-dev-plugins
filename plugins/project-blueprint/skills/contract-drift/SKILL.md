---
name: contract-drift
description: Detect and guard files copied by hand between repos (a GraphQL or OpenAPI schema, protos, shared config). Use when a repo holds a copy of another repo's contract, when changing a schema another repo consumes, or when wiring a schema drift check into CI.
---

# Contract drift

A **contract** is a file one repo owns and another repo copies: a GraphQL schema, an OpenAPI spec, `.proto` files, a JSON schema. A hand-made copy goes **stale** silently: the consumer cannot type against what the owner added, and nothing says so.

## 1. Register the contract

In the consumer, add a row to `docs/contracts.md` (create it if missing):

| Copy | Source of truth | Owner repo | How it updates |
|---|---|---|---|

"How it updates" is one of: **hand-copy** (today's state, to be retired), **pull** (consumer CI fetches it), or **publish** (owner CI pushes it on change).

Done when every copied file in the consumer has a row.

## 2. Add the drift check

A separate workflow, `.github/workflows/contract-drift.yml`, **not** a job in `check.yml`. It goes red whenever the owner moves, so it must not sit on the path that gates deploys and releases.

```yaml
name: contract-drift

on:
  pull_request:
  schedule:
    - cron: "0 6 * * 1-5"
  workflow_dispatch:

permissions:
  contents: read

jobs:
  drift:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - env:
          # Private owner: a fine-grained, read-only token scoped to the owner repos.
          # Public owner: the fallback works.
          GH_TOKEN: ${{ secrets.CONTRACT_READ_TOKEN || github.token }}
          # One line per row of docs/contracts.md: owner repo, source path, copy path.
          CONTRACTS: |
            org/owner-repo src/schema.gql apps/web/schema.gql
        run: |
          status=0
          while read -r repo src copy; do
            [ -n "$repo" ] || continue
            dir="owners/$repo"
            [ -d "$dir" ] || gh repo clone "$repo" "$dir" -- --depth 1 --quiet
            if ! diff -u "$copy" "$dir/$src"; then
              echo "::error::$copy has drifted from $repo:$src. Run 'just sync-contracts' and commit."
              status=1
            fi
          done <<< "$CONTRACTS"
          exit "$status"
```

Add a line to `CONTRACTS` per registered contract. Each owner repo is cloned once, however many contracts it owns, and every drifted copy is reported before the job fails. Dependabot and fork PRs cannot read repo secrets, so against a private owner this check fails on them; leave it off the required checks.

Done when `actionlint` passes on the file and a deliberately edited copy turns the job red.

## 3. Make the copy cheap

Add a `just sync-contracts` recipe that copies every registered contract from its source and runs codegen, so a red check has a one-command fix.

Done when `just sync-contracts` followed by `git diff --exit-code` on the copies passes.

## 4. Retire the hand-copy

The end state is **publish**: the owner's CI opens a PR in each consumer when the contract changes. Raise that as an issue in the owner repo rather than building it unasked; the drift check is the floor until then.

## When changing a contract

A change to the source of truth touches both repos: change the owner, then run `just sync-contracts` in each consumer and regenerate. Say so in the owner's PR body (`pr`'s merge-danger section).
