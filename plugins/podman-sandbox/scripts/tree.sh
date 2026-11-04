# Sourced by start.sh and rebuild.sh, which set WORKSPACE first. Not meant to be run.
#
# A tree is a host folder holding several projects that share one mount and one package
# store. Trees are listed in a host file, one path per line, outside anything a container
# can write:
#   ${XDG_CONFIG_HOME:-~/.config}/podman-sandbox/trees
#
# A workspace under a listed tree mounts the whole tree at /workspaces. Any other workspace
# behaves as before. Sets:
#   TREE_ROOT          the tree's host path, or empty
#   TREE_CONTAINER_WS  this project's path in the container, or empty
#   TREE_UP_ARGS       extra `devcontainer up` arguments
#   TREE_EXEC_ARGS     extra `podman exec` arguments

TREE_CONTAINER_ROOT="/workspaces"
TREE_STORE="$TREE_CONTAINER_ROOT/.packages"
TREES_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/podman-sandbox/trees"
TREE_ROOT=""
TREE_CONTAINER_WS=""
TREE_UP_ARGS=()
TREE_EXEC_ARGS=()

resolve_tree() {
    [ -f "$TREES_FILE" ] || return 0
    local workspace_real line root
    workspace_real="$(cd "$WORKSPACE" && pwd -P)"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ""|\#*) continue ;;
            "~/"*) line="$HOME/${line#\~/}" ;;
        esac
        if ! root="$(cd "$line" 2>/dev/null && pwd -P)"; then
            echo "Warning: tree $line in $TREES_FILE doesn't exist; ignoring it." >&2
            continue
        fi
        if [ "$workspace_real" = "$root" ]; then
            echo "$WORKSPACE is a tree, not a project. Run this from a project inside it." >&2
            exit 1
        fi
        case "$workspace_real/" in
            "$root/"*)
                TREE_ROOT="$root"
                TREE_CONTAINER_WS="$TREE_CONTAINER_ROOT/${workspace_real#"$root"/}"
                TREE_UP_ARGS=(--mount "type=bind,source=$root,target=$TREE_CONTAINER_ROOT")
                # The store shares the tree's mount so tools can hard link from it, which
                # can't cross a mount boundary. Session-scoped because devcontainer.json
                # is per project and stays unaware of trees.
                TREE_EXEC_ARGS=(
                    --workdir "$TREE_CONTAINER_WS"
                    --env "UV_CACHE_DIR=$TREE_STORE/uv"
                    --env "UV_PYTHON_INSTALL_DIR=$TREE_STORE/python"
                    --env "COREPACK_HOME=$TREE_STORE/corepack"
                    --env "COREPACK_ENABLE_DOWNLOAD_PROMPT=0"
                    --env "npm_config_store_dir=$TREE_STORE/pnpm"
                )
                return 0
                ;;
        esac
    done < "$TREES_FILE"
}

resolve_tree
