# Rust pack

Defaults for a new project. An existing repo keeps its tools and maps them onto the same recipe names (rule CMD-4). The versions below are starting points; bootstrap resolves each to an exact version (rule TOOL-1).

## Tools

rustup + cargo, rustfmt (format), Clippy (lint), `cargo test`.

## Pins

- **Rust**: `rust-toolchain.toml`, at an exact version. rustup reads it in every cargo call, on any machine, and installs that toolchain and its components when missing.

```toml
# rust-toolchain.toml
[toolchain]
channel = "1.99.1"
components = ["rustfmt", "clippy"]
```

Commit `Cargo.lock` for libraries as well as binaries; `--locked` fails without it.

## New project

```sh
cargo init           # or `cargo init --lib` for a library
```

Then write `rust-toolchain.toml` and run `cargo generate-lockfile`.

## justfile

```just
set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

setup:
    cargo fetch --locked
    [ -n "${CI:-}" ] || lefthook install

fmt:
    cargo fmt --all

fmt-check:
    cargo fmt --all --check

lint:
    cargo clippy --all-targets --all-features --locked -- -D warnings

typecheck:
    cargo check --all-targets --all-features --locked

test:
    cargo test --all-features --locked

build:
    cargo build --release --locked

secrets:
    gitleaks git --redact --no-banner

check: fmt-check lint typecheck test secrets
```

`-D warnings` turns every Clippy and compiler warning into a failure, so `check` is red on anything Clippy reports.

Services add `run` (`cargo run`), `package` and `deploy`. Libraries add `publish VERSION` (`cargo publish --locked`, after checking VERSION against `Cargo.toml`; crates.io supports trusted publishing from GitHub Actions).

## Lint config

```toml
# Cargo.toml
[lints.rust]
unsafe_code = "forbid"

[lints.clippy]
all = { level = "warn", priority = -1 }
```

A crate that needs `unsafe` changes `forbid` to `deny` and allows it per module, with a `// SAFETY:` comment on each block.

## Runtime (services)

Config from env, parsed at startup into a struct with no default for required values (rule RUN-2). Structured logs via `tracing` with `tracing-subscriber`'s JSON formatter.

## .gitignore additions

`target/`

## Dependabot

`package-ecosystem: cargo`

## CI setup

Add to `.github/actions/setup/action.yml`:

```yaml
    - shell: bash
      run: rustup toolchain install
```

GitHub's Ubuntu runners ship rustup; with no arguments it installs the toolchain `rust-toolchain.toml` names.

## Podman sandbox (optional)

Only when the project uses the `podman-sandbox` plugin. Dockerfile `CUSTOMIZE HERE` runs as root: install rustup (the pinned `rustup-init` binary from `static.rust-lang.org`, not `curl | sh`) with `RUSTUP_HOME=/opt/rustup` and `CARGO_HOME=/opt/cargo`, then the `rust-toolchain.toml` version with its components, and `chmod -R a+rX` both. Set `devcontainer.json` `containerEnv` `"CARGO_HOME": "/home/node/.cargo"` so the `node` user's registry cache is writable, with `/opt/cargo/bin` on `PATH`, and `"CARGO_TARGET_DIR": "/home/node/.cargo-target"`. The workspace is bind-mounted from the host, so without it the container's Linux build output and a macOS host's share `target/`, and each side keeps invalidating the other's.

`EXTRA_DOMAINS`: `index.crates.io`, `static.crates.io` (crate index and downloads). Add `static.rust-lang.org` only if the toolchain may change without rebuilding the image; rustup downloads toolchains from it.
