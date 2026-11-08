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

## Trees mount several projects so one package store can hard link across them

Hard links and clones can't cross a mount boundary, even on one disk. A store on its own volume
or host folder therefore forces symlinks, and those failed: `pnpm`'s `enableGlobalVirtualStore`
moves packages out of the project, so TypeScript can't find `@types`, which gave 77 errors in a
real build. `uv`'s symlink mode is also documented as discouraged. A store on the same mount as
the projects lets both tools use their normal hard links.

`scripts/tree.sh` adds the mount with `devcontainer up --mount` and sets the store in `podman exec`
so per-project `devcontainer.json` files stay unchanged, and projects outside a tree are unaffected.
The original `/workspace` mount still exists in tree containers, as a second path to the project.
Tree membership lives in a host file because a marker in a mount could be changed by a sandbox.

Tested 2026-11-03 with `start.sh` and `rebuild.sh` on two trees, using a real Python and pnpm
project without private dependencies:

- The same files shared one inode across two projects and a worktree. About 1.9 GB on disk, where
  three full copies would take about 5 GB. Inode numbers can change between checks.
- `pnpm build`, unit tests and Python imports passed everywhere.
- Installs in two containers at once passed: 52 s for `uv sync` and 57 s for `pnpm install`, cold.
- A worktree install with a warm store took 18 s and 21 s, so linking over the mount isn't instant.
- A rebuild kept everything working offline.

Also confirmed 2026-11-03 in a real project with a nested path in a tree: login, `git ls-remote` over
HTTPS, a private git dependency, `pnpm build` and unit tests, all from a `--shell` session.

Not yet tested: a working Claude session in a tree, more than one real project in a tree, browser
Playwright tests, or a Python test suite. Secrets files and sandbox config remain readable and writable
across a tree (issue #6).

## Tool plugins are fetched at build time

`tflint --init` and similar first-use downloads come from GitHub release assets, which the
runtime firewall doesn't cover. Doing them in the Dockerfile avoids an allowlist entry and a
GitHub API rate limit, and pins the plugin with the image. The Terraform example writes a
throwaway `.tflint.hcl` for the build, because the project's own file isn't in the build
context. Its version must therefore match the project's `.tflint.hcl`.

Tested 2026-11-08 on arm64 with podman, building the example on `node:24`: checksums passed,
and `tflint` as `node` with `--network=none` loaded the AWS ruleset and flagged an invalid
instance type. Not yet tested: amd64, or a full build of the template with the example
uncommented.

## Git test record

Tested 2026-11-01 with one-off `podman exec --env` flags in a running sandbox:
`git ls-remote` worked for an SSH-form `origin` and a private dependency, and `origin`
failed without the config. Not yet tested: a container built from the template, and
`git push`.
