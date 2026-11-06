# TypeScript pack

Defaults for a new project. An existing repo keeps its tools (eslint, prettier, jest, turbo) and maps them onto the same recipe names (rule CMD-4): the recipe calls the existing `package.json` script. The versions below are starting points; bootstrap resolves each to an exact version (rule TOOL-1).

## Tools

Node + pnpm, Biome (format + lint + import sorting), `tsc --noEmit` (types), Vitest. Biome, TypeScript and Vitest are dev dependencies, pinned by `pnpm-lock.yaml`.

## Pins

- **Node**: `.node-version`, at an exact version (`24.22.2`). `setup-node` reads it, as do fnm, nodenv, asdf and mise.
- **pnpm**: `packageManager` in `package.json` (`"pnpm@11.28.11"`). Corepack and `pnpm/action-setup` read it.

## New project

```sh
echo 24.22.2 > .node-version
pnpm init               # then set "packageManager": "pnpm@<version>" and "type": "module"
pnpm add -D typescript @biomejs/biome vitest @types/node
pnpm exec tsc --init    # then set "types": ["node"] and "outDir": "dist"
pnpm exec biome init
```

Then edit what the generators wrote:

- **`package.json`**: `"type": "module"`. `tsc --init` turns on `verbatimModuleSyntax` with `nodenext`, which rejects `import` syntax in a CommonJS package, and a package without `type` is CommonJS. Add the `build` script `just build` calls, `"build": "tsc"`; `pnpm init` writes only `test` (a framework's own build, such as `next build`, replaces it).
- **`tsconfig.json`**: `"types": ["node"]`, because `tsc --init` writes `"types": []`, which leaves out `@types/node` (`process.env` would not type-check); and `"outDir": "dist"`.

The first `pnpm add` writes `pnpm-lock.yaml`; `--frozen-lockfile` in `setup` fails without it. With `nodenext`, relative imports need their `.js` extension (`./add.js`).

## justfile

```just
set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

setup:
    pnpm install --frozen-lockfile
    [ -n "${CI:-}" ] || lefthook install

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

Services add `run` (`pnpm run dev`), `package` and `deploy`. Libraries add `publish`, which builds first because `release.yml` runs nothing between `setup` and `publish`:

```just
publish $VERSION:
    test "$(node -p 'require("./package.json").version')" = "$VERSION" || { echo "package.json is not at $VERSION" >&2; exit 1; }
    pnpm run build
    pnpm publish --no-git-checks
```

In a pnpm/Turbo workspace, the recipes call `pnpm turbo run <task>` instead, and each package keeps its own scripts.

## Lint config

In `biome.json` (created by `biome init`), turn on the VCS integration and read indentation from `.editorconfig`:

```json
{
  "vcs": { "enabled": true, "clientKind": "git", "useIgnoreFile": true },
  "formatter": { "enabled": true, "useEditorconfig": true }
}
```

`useIgnoreFile` keeps Biome out of `dist/`, `.next/` and `coverage/` by reading `.gitignore`. `useEditorconfig` makes Biome format with the 2-space indent the template `.editorconfig` gives editors; Biome's own default is tabs, so without it every editor save fights `fmt-check`. Remove any `indentStyle` or `indentWidth` that `biome init` wrote, since settings in `biome.json` win over `.editorconfig`.

## Next.js

`NEXT_PUBLIC_*` values are inlined at build time, so one build cannot be promoted across environments unchanged. See the build-once exception in [`../../skills/trunk-delivery/references/deploy-workflows.md`](../../skills/trunk-delivery/references/deploy-workflows.md).

## Runtime (services)

Validate env at startup with a schema (zod) that has no defaults for required values (rule RUN-2). Structured logs via `pino`.

## .gitignore additions

`node_modules/`, `dist/`, `.next/`, `coverage/`, `*.tsbuildinfo`, `.turbo/`

## Dependabot

`package-ecosystem: npm` (covers pnpm).

## CI setup

Add to `.github/actions/setup/action.yml`:

```yaml
    - uses: pnpm/action-setup@v6
    - uses: actions/setup-node@v7
      with:
        node-version-file: .node-version
        cache: pnpm
```

## Podman sandbox (optional)

Only when the project uses the `podman-sandbox` plugin. Set the `NODE_VERSION` build arg in `devcontainer.json` to the exact `.node-version` value (`24.22.2`, not `24`); the base image is `node:${NODE_VERSION}`, and Docker Hub tags every Node release, so the sandbox runs the same Node as CI (rule SBX-2). Pin pnpm in `CUSTOMIZE HERE` with `corepack enable && corepack prepare pnpm@<version> --activate`.

`node_modules` holds platform-specific binaries (Biome's among them), and the workspace is bind-mounted from the host. On a macOS host, install dependencies in one place only, inside the sandbox or on the host, never both.

`EXTRA_DOMAINS`: nothing extra for npm; `registry.npmjs.org` is in the base allowlist because Claude Code itself needs it.
