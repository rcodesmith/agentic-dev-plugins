# Go pack

Defaults for a new project. An existing repo keeps its tools and maps them onto the same recipe names (rule CMD-4). The versions below are starting points; bootstrap resolves each to an exact version (rule TOOL-1).

## Tools

The Go toolchain, golangci-lint v2 (format + lint, including `govet`), `go test`.

```toml
# mise.toml
[tools]
go = "1.27"
golangci-lint = "2.15"
just = "1.59"
lefthook = "2.2"
gitleaks = "8.30"
```

Set the `go` directive in `go.mod` to the same version.

## New project

```sh
go mod init github.com/<owner>/<repo>
```

Add a `main.go` (or a package with one test) so `build` and `test` have something to run.

## justfile

```just
set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

setup:
    go mod download
    lefthook install

fmt:
    golangci-lint fmt

fmt-check:
    golangci-lint fmt --diff

lint:
    golangci-lint run

typecheck:
    go build ./...

test:
    go test -race ./...

build:
    go build -o bin/ ./...

secrets:
    gitleaks git --redact --no-banner

check: fmt-check lint typecheck test secrets
```

Services add `run` (`go run ./cmd/<name>`), `package` and `deploy`. Go libraries are published by the tag itself (the module proxy fetches it), so `publish VERSION` only verifies the tag and can be a no-op.

## Lint config

```yaml
# .golangci.yml
version: "2"
formatters:
  enable: [gofumpt, goimports]
linters:
  default: standard
  enable: [errorlint, gocritic, revive, bodyclose]
```

## Runtime (services)

Config from env with no default for required values (rule RUN-2); fail at startup. Structured logs via `log/slog` with `slog.NewJSONHandler(os.Stdout, nil)`.

## .gitignore additions

`bin/`, `*.test`, `coverage.out`

## Dependabot

`package-ecosystem: gomod`

## Sandbox

Dockerfile `CUSTOMIZE HERE`: install the Go tarball from `go.dev/dl` and the golangci-lint release binary at the versions in `mise.toml`.

`EXTRA_DOMAINS`: `proxy.golang.org`, `sum.golang.org`, `storage.googleapis.com`. The module proxy redirects zip downloads to `storage.googleapis.com`, so it is required. **It is also a wide opening**: it reaches every public Google Cloud Storage bucket, which a compromised dependency could use to send data out, and the firewall allows by IP, so other Google front-end traffic gets through too. Tell the user before adding it. Private modules also need their host and a `GOPRIVATE` entry.
