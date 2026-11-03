# podman-sandbox: design decisions

Reasons behind choices that `SKILL.md` and the templates state without explanation.

## Git uses HTTPS in the container, including for SSH-form remotes

`templates/devcontainer.json` sets a credential helper and `insteadOf` rewrites through
`GIT_CONFIG_*`, so one `GH_TOKEN` serves `origin`, private dependencies and `gh`.

- **A token beats deploy keys:** the sandbox gets no personal SSH keys, and a GitHub
  deploy key reaches one repo. A project with a private dependency would need one key
  per repo plus SSH config, on top of the token `gh` needs anyway.
- **`containerEnv` beats the alternatives:** `gh auth setup-git` writes `~/.gitconfig`,
  which is lost on rebuild. A per-command prefix stops commands matching `Bash(uv sync *)`
  style allow rules. Writing to the repo's `.git/config` would change the host's git too.
- **The token isn't in `containerEnv`:** `start.sh` injects it per session, and `gh`
  reads it when git calls the helper.

Host config can hide problems here. A `url.git@github.com:.insteadOf` rule in a host
`~/.gitconfig` makes `git+https` dependencies use SSH on the host, while the container
uses HTTPS. Test git behaviour inside the container.

## `podman-sandbox-network` keeps its choice outside the workspace

`scripts/network.sh` saves open workspaces in
`${XDG_CONFIG_HOME:-~/.config}/podman-sandbox/network-open-workspaces`. The workspace is
writable from inside the container, so a marker there would let container code lift its own
restrictions. `postStartCommand` re-applies the firewall on start, so `start.sh` calls
`network.sh apply` straight after `devcontainer up` to re-open it.

The command is named for network restrictions rather than the firewall, so it can outlive the
mechanism. Any new restriction must also be lifted in `lift_restrictions`, and reflected in
`live_state`. `rebuild.sh --no-attach` stays restricted until the next `start.sh`.

## Git test record

Tested 2026-11-01 with one-off `podman exec --env` flags in a running sandbox:
`git ls-remote` worked for an SSH-form `origin` and a private dependency, and `origin`
failed without the config. Not yet tested: a container built from the template, and
`git push`.
