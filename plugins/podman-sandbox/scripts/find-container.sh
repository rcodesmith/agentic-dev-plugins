#!/bin/bash
# Prints the running sandbox container's ID for a given workspace, or exits 1 with
# nothing on stdout if none is running. Shared by the other scripts here — not meant
# to be run directly.
#
# Usage: find-container.sh [--workspace <path>]
# Defaults to the current directory. The per-workspace devcontainer config is always
# expected at <workspace>/.devcontainer-podman-sandbox/devcontainer.json (the
# convention this pattern installs into each project). Filters on BOTH that config
# file's path and the workspace folder, so two different projects using this same
# pattern don't collide if both have a sandbox running at once.
set -euo pipefail

WORKSPACE="$(pwd)"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --workspace)
            WORKSPACE="$(cd "$2" && pwd)"
            shift 2
            ;;
        *)
            echo "find-container.sh: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

CONFIG_FILE="$WORKSPACE/.devcontainer-podman-sandbox/devcontainer.json"

CONTAINER_ID="$(podman ps \
    --filter "label=devcontainer.config_file=${CONFIG_FILE}" \
    --filter "label=devcontainer.local_folder=${WORKSPACE}" \
    --format '{{.ID}}' | head -n1)"

if [ -z "$CONTAINER_ID" ]; then
    exit 1
fi

echo "$CONTAINER_ID"
