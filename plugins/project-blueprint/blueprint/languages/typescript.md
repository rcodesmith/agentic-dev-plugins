# TypeScript pack

Defaults for a new project. An existing repo keeps its tools (eslint, prettier, jest, turbo) and maps them onto the same recipe names (rule CMD-4): the recipe calls the existing `package.json` script. The versions below are starting points; bootstrap resolves each to an exact version (rule TOOL-1).

## Tools

Node + pnpm, Biome (format + lint + import sorting), `tsc --noEmit` (types), Vitest. Biome, TypeScript and Vitest are dev dependencies, pinned by `pnpm-lock.yaml`.

```toml
# mise.toml
[tools]
node = "24"
pnpm = "12"
just = "1.59"
lefthook = "2.2"
gitleaks = "8.30"
```

Set `packageManager` in `package.json` to the same pnpm version.

## New project

```sh
pnpm init
pnpm add -D typescript @biomejs/biome vitest @types/node
pnpm exec tsc --init
pnpm exec biome init
```

The first `pnpm add` writes `pnpm-lock.yaml`; `--frozen-lockfile` in `setup` fails without it. `tsc --init` defaults to `nodenext` module resolution, so relative imports need their `.js` extension (`./add.js`).

## justfile

```just
set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

setup:
    pnpm install --frozen-lockfile
    lefthook install

fmt:
    pnpm exec biome check --write .

fmt-check:
    pnpm exec biome format .

lint:
    pnpm exec biome ci .

typecheck:
    pnpm exec tsc --noEmit

test:
    pnpm exec vitest run

build:
    pnpm run build

secrets:
    gitleaks git --redact --no-banner

check: fmt-check lint typecheck test secrets
```

`lint` uses `biome ci`, which checks formatting, lint rules and import sorting together, so `check` fails on anything `fmt` would change.

Services add `run` (`pnpm run dev`), `package` and `deploy`. Libraries add `publish VERSION` (`pnpm publish --no-git-checks` after checking `package.json` matches VERSION).

In a pnpm/Turbo workspace, the recipes call `pnpm turbo run <task>` instead, and each package keeps its own scripts.

## Lint config

In `biome.json` (created by `biome init`), turn on the VCS integration:

```json
{
  "vcs": { "enabled": true, "clientKind": "git", "useIgnoreFile": true }
}
```

`useIgnoreFile` keeps Biome out of `dist/`, `.next/` and `coverage/` by reading `.gitignore`.

## Next.js

`NEXT_PUBLIC_*` values are inlined at build time, so one build cannot be promoted across environments unchanged. See the build-once exception in [`../../skills/trunk-delivery/references/deploy-workflows.md`](../../skills/trunk-delivery/references/deploy-workflows.md).

## Runtime (services)

Validate env at startup with a schema (zod) that has no defaults for required values (rule RUN-2). Structured logs via `pino`.

## .gitignore additions

`node_modules/`, `dist/`, `.next/`, `coverage/`, `*.tsbuildinfo`, `.turbo/`

## Dependabot

`package-ecosystem: npm` (covers pnpm).

## Sandbox

Set the `NODE_VERSION` build arg in `devcontainer.json` to the `mise.toml` Node major; the base image is `node:${NODE_VERSION}`. Pin pnpm in `CUSTOMIZE HERE` with `corepack enable && corepack prepare pnpm@<version> --activate`.

`node_modules` holds platform-specific binaries (Biome's among them), and the workspace is bind-mounted from the host. On a macOS host, install dependencies in one place only, inside the sandbox or on the host, never both.

`EXTRA_DOMAINS`: nothing extra for npm; `registry.npmjs.org` is in the base allowlist because Claude Code itself needs it.
