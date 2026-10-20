#!/bin/bash
# Rebuilds the sandbox image and recreates the container for a project, then attaches
# via start.sh. Use after editing anything baked into the image — the Dockerfile,
# init-firewall.sh (e.g. EXTRA_DOMAINS), or web-research-toggle.sh. start.sh alone
# won't pick those up: `devcontainer up` reuses an existing container, and restarting
# it just re-runs the old copy of init-firewall.sh that was COPYed in at build time.
#
# Usage: rebuild.sh [--workspace <path>] [--no-cache] [--no-attach] [start.sh args...]
# --no-cache rebuilds every layer (e.g. to pick up a newer Claude Code release);
# otherwise the build cache is used and only layers from the first changed one on are
# rebuilt. --no-attach stops after the rebuild instead of handing off to start.sh.
# Remaining args are passed through to start.sh (e.g. --shell, --continue).
#
# Named volumes (auth, MCP servers, plugins, shell history) are independent of the
# container and survive the recreate — no need to log in again.
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
WORKSPACE="$(pwd)"
NO_CACHE=false
ATTACH=true

while [ "$#" -gt 0 ]; do
    case "$1" in
        --workspace)
            WORKSPACE="$(cd "$2" && pwd)"
            shift 2
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --no-attach)
            ATTACH=false
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

UP_ARGS=(--workspace-folder "$WORKSPACE" --config "$CONFIG" --docker-path podman --remove-existing-container)
if [ "$NO_CACHE" = true ]; then
    UP_ARGS+=(--build-no-cache)
fi

echo "Rebuilding the sandbox image and recreating the container (any session running in it will end)..."
devcontainer up "${UP_ARGS[@]}"

if [ "$ATTACH" = true ]; then
    # start.sh's own `devcontainer up` just reuses the container created above.
    exec "$SCRIPT_DIR/start.sh" --workspace "$WORKSPACE" "$@"
fi
