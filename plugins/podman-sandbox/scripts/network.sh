#!/bin/bash
# Turns a workspace's sandbox network restrictions off or on, persistently. Run on the
# host, not in the container.
#
# Usage: network.sh [--workspace <path>] {open|restrict|status}
#   open      Lift all restrictions now and on every later podman-sandbox-start,
#             including after a rebuild, until `restrict` is run.
#   restrict  Forget that choice and re-apply the restrictions now.
#   status    Show the saved choice and what the running container is doing.
#
# Defaults to the current directory. No rebuild needed for either direction.
#
# The choice is saved on the host, outside every workspace: the workspace is writable
# from inside the container, so a marker there would let container code lift its own
# restrictions.
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
WORKSPACE="$(pwd)"

if [ "${1:-}" = "--workspace" ]; then
    WORKSPACE="$(cd "$2" && pwd)"
    shift 2
fi
ACTION="${1:-}"

# One workspace path per line.
STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/podman-sandbox"
STATE_FILE="$STATE_DIR/network-open-workspaces"

is_open() {
    [ -f "$STATE_FILE" ] && grep -Fxq -- "$WORKSPACE" "$STATE_FILE"
}

require_sandbox() {
    if [ ! -f "$WORKSPACE/.devcontainer-podman-sandbox/devcontainer.json" ]; then
        echo "No sandbox config found under $WORKSPACE — run this from the project root or pass --workspace." >&2
        exit 1
    fi
}

# Separate from running_container, so an unreachable Podman can't be mistaken for "no
# sandbox running" while a real container keeps its old state.
require_podman() {
    if ! podman ps -q >/dev/null; then
        echo "Can't reach Podman, so nothing was changed. Is the machine running?" >&2
        exit 1
    fi
}

running_container() {
    "$SCRIPT_DIR/find-container.sh" --workspace "$WORKSPACE"
}

lift_restrictions() {
    podman exec --user root --workdir / "$1" sh -c '
        set -e
        for tool in iptables ip6tables; do
            for chain in INPUT OUTPUT FORWARD; do
                "$tool" -P "$chain" ACCEPT
            done
            "$tool" -F
        done
    '
}

warn_open() {
    echo "WARNING: network restrictions are OFF for $WORKSPACE." >&2
    echo "  Anything in this sandbox can send its tokens and files to any host." >&2
    echo "  Turn them back on with: podman-sandbox-network restrict" >&2
}

live_state() {
    local rules
    rules="$(podman exec --user root --workdir / "$1" iptables -S OUTPUT)"
    case "$rules" in
        *"-P OUTPUT DROP"*) echo "restricted" ;;
        *) echo "open" ;;
    esac
}

case "$ACTION" in
    open)
        require_sandbox
        require_podman
        if ! is_open; then
            mkdir -p "$STATE_DIR"
            printf '%s\n' "$WORKSPACE" >> "$STATE_FILE"
        fi
        if CONTAINER_ID="$(running_container)"; then
            lift_restrictions "$CONTAINER_ID"
        else
            echo "No running sandbox; this applies at the next podman-sandbox-start."
        fi
        warn_open
        ;;
    restrict)
        require_sandbox
        require_podman
        # Saved choice goes first, so a failure below can't leave it open.
        if is_open; then
            STATE_TMP="$(mktemp "$STATE_DIR/network-open-workspaces.XXXXXX")"
            grep -Fxv -- "$WORKSPACE" "$STATE_FILE" > "$STATE_TMP" || true
            mv "$STATE_TMP" "$STATE_FILE"
        fi
        if CONTAINER_ID="$(running_container)"; then
            podman exec --user root --workdir / "$CONTAINER_ID" /usr/local/bin/init-firewall.sh
            echo "Network restrictions are ON for $WORKSPACE."
        else
            echo "No running sandbox; restrictions apply when it next starts."
        fi
        ;;
    status)
        require_sandbox
        require_podman
        if is_open; then SAVED="open"; else SAVED="restricted"; fi
        echo "Saved choice: $SAVED"
        if CONTAINER_ID="$(running_container)"; then
            LIVE="$(live_state "$CONTAINER_ID")"
            echo "Running sandbox: $LIVE"
            if [ "$LIVE" != "$SAVED" ]; then
                echo "These differ. podman-sandbox-start re-applies an open choice; a bare" >&2
                echo "podman restart leaves no restrictions until the next podman-sandbox-start." >&2
            fi
        else
            echo "Running sandbox: none"
        fi
        ;;
    apply)
        # Internal: start.sh calls this after bringing the container up, because
        # postStartCommand has just re-applied the restrictions.
        is_open || exit 0
        CONTAINER_ID="$(running_container)"
        lift_restrictions "$CONTAINER_ID"
        warn_open
        ;;
    *)
        echo "Usage: network.sh [--workspace <path>] {open|restrict|status}" >&2
        exit 1
        ;;
esac
