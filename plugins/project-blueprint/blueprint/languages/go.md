# Go pack

Defaults for a new project. An existing repo keeps its tools and maps them onto the same recipe names (rule CMD-4). The versions below are starting points; bootstrap resolves each to an exact version (rule TOOL-1).

## Tools

The Go toolchain, golangci-lint v2 (format + lint, including `govet`), `go test`.

## Pins

- **Go**: the `go` line in `go.mod`, at an exact version (`go 1.27.3`; `go mod init` writes the installed one). Go downloads that toolchain itself when the local one is older.
- **golangci-lint**: a `tool` directive in a separate `tools/go.mod`, so its dependencies stay out of the project's module graph, and Dependabot updates it like any other dependency. The recipes run it with `go tool -modfile=tools/go.mod golangci-lint`.

## New project

```sh
go mod init github.com/<owner>/<repo>
mkdir tools && (cd tools && go mod init tools && go get -tool github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.15.0)
```

Add a `main.go` (or a package with one test) so `build` and `test` have something to run.

## justfile

```just
set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

setup:
    go mod download
    go mod download -modfile=tools/go.mod
    [ -n "${CI:-}" ] || lefthook install

fmt:
    go tool -modfile=tools/go.mod golangci-lint fmt

fmt-check:
    go tool -modfile=tools/go.mod golangci-lint fmt --diff

lint:
    go tool -modfile=tools/go.mod golangci-lint run

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

`package-ecosystem: gomod`, with `directories: ["/", "/tools"]` so the linter is updated too.

## CI setup

Add to `.github/actions/setup/action.yml`:

```yaml
    - uses: actions/setup-go@v7
      with:
        go-version-file: go.mod
```

## Podman sandbox (optional)

Only when the project uses the `podman-sandbox` plugin. Dockerfile `CUSTOMIZE HERE`: install the Go tarball from `go.dev/dl` at the `go.mod` version. golangci-lint comes through `go tool`, so it needs no install.

`EXTRA_DOMAINS`: `proxy.golang.org`, `sum.golang.org`, `storage.googleapis.com`. The module proxy redirects zip downloads to `storage.googleapis.com`, so it is required. **It is also a wide opening**: it reaches every public Google Cloud Storage bucket, which a compromised dependency could use to send data out, and the firewall allows by IP, so other Google front-end traffic gets through too. Tell the user before adding it. Private modules also need their host and a `GOPRIVATE` entry.
