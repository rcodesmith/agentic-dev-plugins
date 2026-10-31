# project-blueprint

One blueprint for every project, whatever the language: the same `just` commands, the same quality gates, trunk-based delivery, and the podman sandbox. Python, Go and TypeScript packs are included.

## Install

```
/plugin marketplace add rcodesmith/agentic-dev-plugins
/plugin install project-blueprint@agentic-dev-plugins
```

Installing it also installs its two dependencies:

- [`mattpocock-skills`](https://github.com/mattpocock/skills): issue tracker, triage, glossary and ADRs, specs and tickets, TDD, code review, PR bodies. The blueprint points to it rather than duplicating it.
- [`podman-sandbox`](../podman-sandbox): the sandbox the agent works in.

## Skills

| Skill | Invoked by | Does |
|---|---|---|
| `/bootstrap-project` | you | Brings a new or existing repo up to the blueprint, then hands off to `/setup-matt-pocock-skills` and the sandbox |
| `/project-doctor` | you | Checks a repo against every rule and reports pass, fail or N/A with evidence |
| `trunk-delivery` | the agent | Branch naming, merging, deploys, releases, hotfixes |
| `contract-drift` | the agent | Guards files copied by hand between repos |

## Layout

- `blueprint/rules.md`: every rule, with its check and owner. Bootstrap and doctor both read it.
- `blueprint/languages/`: per-language tools, `justfile`, lint config and sandbox values.
- `templates/`: files copied into projects, including the GitHub workflows.

## The model in one paragraph

Every repo has a root `justfile` with `setup`, `fmt`, `fmt-check`, `lint`, `typecheck`, `test`, `build`, `secrets` and `check`; CI and the pre-commit hook run those, so the workflow is the same in every language. `main` is the only long-lived branch. Work happens on short `<type>/<issue#>-<slug>` branches, squash-merged after `code-review`. Services build one artifact per `main` commit, auto-deploy it to dev, and promote that same artifact to prod by a manual dispatch.
