#!/bin/bash
# Brings up the Podman sandbox devcontainer for a project (building/creating it if
# needed, reusing it if already running) and drops you into a `claude` session inside
# it.
#
# Usage: start.sh [--workspace <path>] [--shell] [claude flags...]
# Defaults to the current directory as the workspace. The project must already have
# this pattern installed into it (a .devcontainer-podman-sandbox/ with its own
# devcontainer.json, Dockerfile, init-firewall.sh, web-research-toggle.sh — see this
# plugin's skill for how to set that up in a new project).
#
# --shell drops you into zsh instead of claude (same secrets injection); extra args
# are then ignored.
#
# A different --workspace gets its OWN identity: the named config volume (auth, MCP
# servers, installed plugins) is keyed off the workspace path devcontainers CLI infers
# an --id-label from, so a different project means redoing `claude auth login
# --claudeai` (and any MCP/plugin setup you want) once for that project. This is
# deliberate — unrelated projects shouldn't silently share credentials/state.
#
# Extra args are passed through to claude, e.g.:
#   start.sh --remote-control
#   start.sh --workspace ~/code/some-other-project --remote-control
#
# Runtime secrets (GitHub PAT, Grafana token, AWS creds, whatever the project needs)
# come from a single file at the workspace root: .env.podman-sandbox-secrets, plain
# KEY=VALUE lines, one per secret. It's optional and per-workspace (not shared across
# projects) — if absent, nothing extra is injected. If present, it must be mode 600
# and git-ignored; this script refuses to use it otherwise rather than silently
# skipping the check. Values are handed to `podman exec --env-file`, never as a
# command-line argument, so they never show up in `ps` for the lifetime of the
# session.
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
WORKSPACE="$(pwd)"
SHELL_MODE=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --workspace)
            WORKSPACE="$(cd "$2" && pwd)"
            shift 2
            ;;
        --shell)
            SHELL_MODE=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

CONFIG="$WORKSPACE/.devcontainer-podman-sandbox/devcontainer.json"

if [ ! -f "$CONFIG" ]; then
    echo "No sandbox config found at $CONFIG" >&2
    echo "This project doesn't have the pattern installed yet — see the podman-sandbox skill." >&2
    exit 1
fi

devcontainer up --workspace-folder "$WORKSPACE" --config "$CONFIG" --docker-path podman

CONTAINER_ID="$("$SCRIPT_DIR/find-container.sh" --workspace "$WORKSPACE")" || {
    echo "devcontainer up succeeded but no matching container is running — aborting." >&2
    exit 1
}

SECRETS_FILE="$WORKSPACE/.env.podman-sandbox-secrets"
ENV_FILE_ARGS=()

if [ -e "$SECRETS_FILE" ]; then
    PERMS="$(stat -f '%OLp' "$SECRETS_FILE" 2>/dev/null || stat -c '%a' "$SECRETS_FILE")"
    if [ "$PERMS" != "600" ]; then
        echo "Refusing to use $SECRETS_FILE: mode is $PERMS, must be 600." >&2
        echo "Fix with: chmod 600 $SECRETS_FILE" >&2
        exit 1
    fi
    if git -C "$WORKSPACE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        if ! git -C "$WORKSPACE" check-ignore -q -- "$SECRETS_FILE"; then
            echo "Refusing to use $SECRETS_FILE: it is not git-ignored in $WORKSPACE." >&2
            echo "Add it to .gitignore before storing secrets in it." >&2
            exit 1
        fi
    fi
    echo "Found secrets file ($SECRETS_FILE) — injecting its entries for this session only."
    ENV_FILE_ARGS=(--env-file "$SECRETS_FILE")
fi

if [ "$SHELL_MODE" = true ]; then
    CMD=(zsh)
else
    CMD=(claude --permission-mode auto "$@")
fi

podman exec -it "${ENV_FILE_ARGS[@]}" "$CONTAINER_ID" "${CMD[@]}"
