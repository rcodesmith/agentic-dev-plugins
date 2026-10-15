#!/bin/bash
# Removes stopped containers created by this pattern, across ALL projects using it
# (matched by the devcontainer-config filename convention, not any one project's
# path) — never touches stopped containers from unrelated devcontainer setups.
# Removing a stopped container is safe regardless of project: its named volumes
# (auth, MCP servers, plugins) persist independently and aren't touched by this.
set -euo pipefail

STOPPED="$(podman ps -a --filter "status=exited" --format '{{.ID}} {{.Labels}} {{.Names}}' \
    | awk '$0 ~ /devcontainer\.config_file=.*\.devcontainer-podman-sandbox\/devcontainer\.json/')"

if [ -z "$STOPPED" ]; then
    echo "No stopped sandbox containers to clean up."
    exit 0
fi

echo "Removing stopped sandbox containers:"
echo "$STOPPED"
echo "$STOPPED" | awk '{print $1}' | xargs podman rm
