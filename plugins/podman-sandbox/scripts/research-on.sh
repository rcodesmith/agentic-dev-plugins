#!/bin/bash
# Turns on unrestricted outbound HTTP/HTTPS in the running sandbox container (see
# web-research-toggle.sh). Remember to turn it back off with research-off.sh when done.
#
# Usage: research-on.sh [--workspace <path>]  (defaults to the current directory)
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

CONTAINER_ID="$("$SCRIPT_DIR/find-container.sh" "$@")" || {
    echo "No running sandbox container found for that workspace. Start one with start.sh first." >&2
    exit 1
}

podman exec "$CONTAINER_ID" sudo web-research-toggle.sh on
