# Python pack

Defaults for a new project. An existing repo keeps its tools and maps them onto the same recipe names (rule CMD-4). The versions below are starting points; bootstrap resolves each to an exact version (rule TOOL-1).

## Tools

uv (env + lock), ruff (format + lint), pyright (types), pytest. ruff, pyright and pytest are dev dependencies in `pyproject.toml` (`[dependency-groups] dev`), so `uv.lock` pins them; `mise.toml` pins the interpreter, uv and the shared tools.

```toml
# mise.toml
[tools]
python = "3.14"
uv = "0.13"
just = "1.59"
lefthook = "2.2"
gitleaks = "8.30"
```

## New project

```sh
uv init --app        # or --lib for a library
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
    lefthook install

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

Services add `run` (e.g. `uv run uvicorn <pkg>.main:app --reload`), `package` and `deploy`. Libraries add `publish VERSION` (`uv publish`, after checking VERSION against `pyproject.toml`).

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

## Sandbox

Dockerfile `CUSTOMIZE HERE` runs as root, so install Python where the `node` user can read it:

```dockerfile
# uv: the pinned static-binary example already in CUSTOMIZE HERE, at the mise.toml version.
ENV UV_PYTHON_INSTALL_DIR=/opt/uv-python
RUN uv python install 3.14.x && chmod -R a+rX /opt/uv-python
```

`devcontainer.json` `containerEnv`: `"UV_PROJECT_ENVIRONMENT": "/home/node/.venv"`. The workspace is bind-mounted from the host, so without this the container's Linux `.venv` and a macOS host's `.venv` overwrite each other.

`EXTRA_DOMAINS`: `pypi.org`, `files.pythonhosted.org`, `astral.sh`, `objects.githubusercontent.com`, `release-assets.githubusercontent.com` (uv fetches managed Pythons from GitHub releases at runtime).
