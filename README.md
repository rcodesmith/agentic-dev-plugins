# agentic-dev-plugins

Public Claude Code plugins for agentic development workflows.

## Install

```
/plugin marketplace add rcodesmith/agentic-dev-plugins
/plugin install podman-sandbox@agentic-dev-plugins
```

## Plugins

- **podman-sandbox** — Run Claude Code in `--permission-mode auto` inside a Podman
  devcontainer, using a default-deny egress firewall as the real security boundary
  instead of per-directory prompts. The safety classifier stays active and can still
  refuse risky actions; what's relaxed is just the directory-scope restriction that
  would otherwise prompt on every path outside the workspace or shell commands where
  the auto mode classifier cannot determine the path. Ships a skill that walks
  through installing the pattern into a new project (adapting a Dockerfile/firewall
  allowlist for that project's toolchain) plus a `templates/` folder of starter files
  and a set of `podman-sandbox-*` CLI commands for day-to-day use.

## Alternatives to podman-sandbox

No open source project we found covers everything a local sandbox for coding agents needs,
so podman-sandbox may not be the right choice for you. It has known open security issues:
[#5](https://github.com/rcodesmith/agentic-dev-plugins/issues/5) and
[#6](https://github.com/rcodesmith/agentic-dev-plugins/issues/6).

This comparison focuses on local use on Apple Silicon Macs. It's based on project docs and
repos as of 2026-11-03, not hands-on testing, and this field changes quickly, so check the
details before relying on them.

| | [sandbox-runtime](https://github.com/anthropics/sandbox-runtime) (`srt`) | [nono](https://github.com/nolabs-ai/nono) | [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) (`sbx`) | [microsandbox](https://github.com/superradcompany/microsandbox) | [agent-sandbox](https://github.com/mattolson/agent-sandbox) |
|---|---|---|---|---|---|
| **License** | Apache-2.0 | Apache-2.0 | Proprietary | Apache-2.0 | MIT |
| **Isolation** | OS-level (Seatbelt, bubblewrap) | OS-level | microVM | microVM | Container |
| **Network filtering** | Hostname proxy outside the sandbox | Hostname proxy | Host-side domain policy | DNS, SNI and Host checks; allows public internet by default | mitmproxy sidecar, deny by default |
| **Credentials** | Environment variables can be denied or masked; masking is experimental | Placeholder tokens through the proxy | Kept out of the VM, with injection for GitHub | Placeholder tokens; needs TLS interception | Proxy injects tokens, with repo scoping |
| **Files** | Native | Native | Passthrough with virtiofs, or a private clone | virtiofs or named volumes | Bind mount |
| **Status** | Beta research preview | Pre-1.0 | Active; needs a Docker account | Beta; several recent Critical and High advisories | Early stage; not a hard isolation boundary, per its own security policy |

### Choosing one

- **Lightest setup:** `srt` wraps the whole Claude Code process, with no image or VM. There's no
  Mac and Linux conflict over `.venv` or `node_modules`, and no file-sharing slowdown. The
  trade-offs are no separate kernel, no Linux parity, and no Docker inside the sandbox. Anthropic
  [documents it for unattended use](https://code.claude.com/docs/en/sandbox-environments) but
  recommends a dedicated VM for untrusted repositories.
- **Strongest boundary, without needing open source:** `sbx` gives each sandbox a microVM, with
  network policy and credentials handled outside it.
- **Open source with a microVM:** microsandbox has a promising design, but review its
  [security advisories](https://github.com/superradcompany/microsandbox/security/advisories) first.
- **Linux parity on your own terms:** a container like podman-sandbox keeps a Linux toolchain and
  stays fully under your control, but you maintain the image, scripts and firewall yourself.

### Things to check with `srt`

- **Reads are allowed by default.** Writes and network are denied by default, but reads must be
  closed with `denyRead`, such as `/Users`, and reopened with `allowRead`. Paths outside what you
  deny stay readable.
- **Claude's own config can persist changes.** Writable `~/.claude` paths can hold hooks that run
  unsandboxed at the next launch, so add `denyWrite` rules.
- **SSH git fails under Seatbelt on macOS,** so remotes need to use HTTPS.
- **The built-in `sandbox.enabled` setting is different.** It covers shell commands, while file
  tools, MCP servers and hooks run outside it, so
  [Anthropic says](https://code.claude.com/docs/en/sandbox-environments) it isn't sufficient for
  fully unattended runs.

### Other projects reviewed

| Project | Why it isn't listed above |
|---|---|
| [Anthropic's reference devcontainer](https://code.claude.com/docs/en/devcontainer) | The starting point for podman-sandbox; also uses an iptables firewall |
| [Apple `container`](https://github.com/apple/container), [Lima](https://lima-vm.io/docs/examples/ai/), [Colima](https://github.com/abiosoft/colima) | Good runtimes, but you'd build network filtering yourself |
| [E2B](https://github.com/e2b-dev/infra), [Firecracker](https://github.com/firecracker-microvm/firecracker), [gVisor](https://gvisor.dev/docs/user_guide/install/), [Kata Containers](https://github.com/kata-containers/kata-containers) | Need a Linux host, or don't state macOS host support |
| [Daytona](https://github.com/daytonaio/daytona) | Repository archived |
| [Arrakis](https://github.com/abshkbh/arrakis), [DevPod](https://github.com/loft-sh/devpod) | No recent activity; DevPod also has no egress or credential features of its own |
| [Coder](https://coder.com/docs/ai-coder/agent-boundaries) | Agent firewall needs a Premium license and Linux kernel features |
| [Tart](https://github.com/cirruslabs/tart), [OrbStack](https://orbstack.dev/pricing) | Not open source, with no egress or credential layer |
| [Gitpod/Ona](https://github.com/gitpod-io/gitpod) | Now a managed, agent-first product |
| [Dagger container-use](https://github.com/dagger/container-use) | Experimental, with no network control mentioned |
| [Matchlock](https://github.com/jingkaihe/matchlock) | No host-directory mounts |

Newer projects to watch: [smolvm](https://github.com/smol-machines/smolvm) and
[Shuru](https://github.com/superhq-ai/shuru).
