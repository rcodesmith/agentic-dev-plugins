# Python pack

Defaults for a new project. An existing repo keeps its tools and maps them onto the same recipe names (rule CMD-4). The versions below are starting points; bootstrap resolves each to an exact version (rule TOOL-1).

## Tools

uv (env + lock), ruff (format + lint), pyright (types), pytest. ruff, pyright and pytest are dev dependencies in `pyproject.toml` (`[dependency-groups] dev`), so `uv.lock` pins them.

## Pins

- **Python**: `.python-version`, at an exact version (`3.14.0`). uv reads it and installs that interpreter.
- **uv**: `required-version` in `pyproject.toml`; `setup-uv` in CI reads it.

```toml
# pyproject.toml
[tool.uv]
required-version = "==0.13.7"
```

## New project

```sh
uv init --app        # or --lib for a library; writes .python-version
uv python pin 3.14.0 # an exact version
uv add --dev ruff pyright pytest
uv lock
```

`--locked` in `setup` fails without a lockfile, so `uv lock` runs before the first `just setup`.

## justfile

```just
set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

setup:
    uv sync --locked
    [ -n "${CI:-}" ] || lefthook install

fmt:
    uv run ruff format .
    uv run ruff check --fix .

fmt-check:
    uv run ruff format --check .

lint:
    uv run ruff check .

typecheck:
    uv run pyright

test:
    uv run pytest

build:
    uv build

secrets:
    gitleaks git --redact --no-banner

check: fmt-check lint typecheck test secrets
```

Services add `run` (e.g. `uv run uvicorn <pkg>.main:app --reload`), `package` and `deploy`. Libraries add `publish`, which builds first because `release.yml` runs nothing between `setup` and `publish`:

```just
publish $VERSION:
    test "$(uv version --short)" = "$VERSION" || { echo "pyproject.toml is not at $VERSION" >&2; exit 1; }
    rm -rf dist
    uv build
    uv publish
```

`uv publish` uses trusted publishing automatically in GitHub Actions when PyPI is configured for it.

## Lint config

```toml
# pyproject.toml
[tool.ruff.lint]
select = ["E", "F", "I", "B", "UP", "SIM", "RUF"]

[tool.pyright]
typeCheckingMode = "standard"
```

## Runtime (services)

Config via `pydantic-settings`, with required fields that have no default (rule RUN-2). Structured logs via `structlog` with the JSON renderer.

## .gitignore additions

`.venv/`, `__pycache__/`, `*.pyc`, `.pytest_cache/`, `.ruff_cache/`, `dist/`, `build/`, `*.egg-info/`

## Dependabot

`package-ecosystem: uv`

## CI setup

Add to `.github/actions/setup/action.yml`:

```yaml
    - uses: astral-sh/setup-uv@v10.3.3
```

setup-uv publishes no floating major tag (`@v10` does not resolve), so pin its exact release tag or a SHA; Dependabot keeps either current. It reads uv's version from `required-version` in `pyproject.toml`. `uv sync` in `just setup` installs the interpreter `.python-version` names.

## Podman sandbox (optional)

Only when the project uses the `podman-sandbox` plugin. Dockerfile `CUSTOMIZE HERE` runs as root, so install Python where the `node` user can read it:

```dockerfile
# uv: the pinned static-binary example already in CUSTOMIZE HERE, at the required-version.
ENV UV_PYTHON_INSTALL_DIR=/opt/uv-python
RUN uv python install 3.14.0 && chmod -R a+rX /opt/uv-python
```

`devcontainer.json` `containerEnv`: `"UV_PROJECT_ENVIRONMENT": "/home/node/.venv"`. The workspace is bind-mounted from the host, so without this the container's Linux `.venv` and a macOS host's `.venv` overwrite each other.

`EXTRA_DOMAINS`: `pypi.org`, `files.pythonhosted.org`, `astral.sh`, `objects.githubusercontent.com`, `release-assets.githubusercontent.com` (uv fetches managed Pythons from GitHub releases at runtime).
