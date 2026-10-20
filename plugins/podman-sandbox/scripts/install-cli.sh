#!/bin/bash
# Creates/refreshes stable command-name symlinks in ~/.local/bin pointing at this
# plugin's scripts — run this once after installing the plugin, and again any time
# the plugin updates (the plugin's own install path is versioned, so these symlinks
# are what gives you a stable, version-independent set of commands).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

# Plain indexed array of "name=script" pairs, not an associative array — macOS ships
# bash 3.2 as /bin/bash (Apple hasn't shipped a GPLv3 bash since), and `declare -A`
# requires bash 4+.
COMMANDS=(
    "podman-sandbox-start=start.sh"
    "podman-sandbox-rebuild=rebuild.sh"
    "podman-sandbox-research-on=research-on.sh"
    "podman-sandbox-research-off=research-off.sh"
    "podman-sandbox-cleanup=cleanup.sh"
)

for entry in "${COMMANDS[@]}"; do
    name="${entry%%=*}"
    script="${entry#*=}"
    ln -sfn "$SCRIPT_DIR/$script" "$BIN_DIR/$name"
    echo "Linked $BIN_DIR/$name -> $SCRIPT_DIR/$script"
done

case ":$PATH:" in
    *":$BIN_DIR:"*)
        echo "$BIN_DIR is already on PATH."
        ;;
    *)
        echo
        echo "$BIN_DIR is NOT on your PATH yet. Add this to your shell profile (~/.zshrc, ~/.bashrc):"
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        ;;
esac
