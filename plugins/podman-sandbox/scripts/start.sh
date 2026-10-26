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
#
# Git over SSH is opt-in the same way: an optional private key (ideally a per-repo
# deploy key) at the workspace root, .podman-sandbox-ssh-key, held to the same mode-600
# and git-ignored checks. It's already visible inside the container through the
# workspace bind mount, so nothing extra is mounted — this script only points
# GIT_SSH_COMMAND at it for the session.
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

# Refuses (hard error, not a silent skip) to use a credential file that isn't mode 600
# and git-ignored.
require_private_file() {
    local file="$1"
    local perms
    # GNU form first: on Linux, `stat -f` means filesystem status and "succeeds" with
    # junk, while BSD/macOS stat rejects -c and falls through.
    perms="$(stat -c '%a' "$file" 2>/dev/null || stat -f '%OLp' "$file")"
    if [ "$perms" != "600" ]; then
        echo "Refusing to use $file: mode is $perms, must be 600." >&2
        echo "Fix with: chmod 600 $file" >&2
        exit 1
    fi
    if git -C "$WORKSPACE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        if ! git -C "$WORKSPACE" check-ignore -q -- "$file"; then
            echo "Refusing to use $file: it is not git-ignored in $WORKSPACE." >&2
            echo "Add it to .gitignore before storing secrets in it." >&2
            exit 1
        fi
    fi
}

SECRETS_FILE="$WORKSPACE/.env.podman-sandbox-secrets"
SSH_KEY_NAME=".podman-sandbox-ssh-key"
SSH_KEY_FILE="$WORKSPACE/$SSH_KEY_NAME"
# Must match workspaceFolder in the project's devcontainer.json.
CONTAINER_WORKSPACE="/workspace"
EXEC_ARGS=()

if [ -e "$SECRETS_FILE" ]; then
    require_private_file "$SECRETS_FILE"
    echo "Found secrets file ($SECRETS_FILE) — injecting its entries for this session only."
    EXEC_ARGS+=(--env-file "$SECRETS_FILE")
fi

if [ -e "$SSH_KEY_FILE" ]; then
    require_private_file "$SSH_KEY_FILE"
    echo "Found SSH key ($SSH_KEY_FILE) — using it for git over SSH this session."
    # A path, not a secret, so it's fine on the command line.
    EXEC_ARGS+=(--env "GIT_SSH_COMMAND=ssh -i $CONTAINER_WORKSPACE/$SSH_KEY_NAME -o IdentitiesOnly=yes")
fi

if [ "$SHELL_MODE" = true ]; then
    CMD=(zsh)
else
    # Bare `claude` with no login falls into the default first-run login, which can't
    # complete inside the container. Stop and point at the flow that works instead.
    # Fails open: only an explicit "loggedIn": false blocks, so an unexpected output
    # format never locks you out.
    AUTH_STATUS="$(podman exec "$CONTAINER_ID" claude auth status 2>&1 || true)"
    if printf '%s' "$AUTH_STATUS" | grep -Eq '"loggedIn"[[:space:]]*:[[:space:]]*false'; then
        echo "Claude Code isn't logged in inside this sandbox yet. Log in once with:" >&2
        echo "  podman-sandbox-start --shell" >&2
        echo "  claude auth login --claudeai    # approve in the browser, paste the code back" >&2
        echo "  exit" >&2
        echo "then run podman-sandbox-start again." >&2
        exit 1
    fi
    CMD=(claude --permission-mode auto "$@")
fi

# ${ARR[@]+...} rather than "${ARR[@]}": bash < 4.4 (macOS /bin/bash is 3.2) treats an
# empty array as unbound under set -u.
podman exec -it ${EXEC_ARGS[@]+"${EXEC_ARGS[@]}"} "$CONTAINER_ID" "${CMD[@]}"
