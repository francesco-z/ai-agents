---
name: go-development
description: Conventions and troubleshooting for writing and building Go code — module/dependency management, build and vet errors, test patterns, and idiomatic style. Use when writing or debugging Go (.go files, go.mod) projects.
when_to_use: go build/vet/test errors, go.mod/go.sum issues, module resolution, writing idiomatic Go, build tags
allowed-tools: Bash(go *) Bash(gofmt *)
---

# Go development & troubleshooting

## Build/diagnose loop
- `go build ./...` then `go vet ./...` then `go test ./...`. Read the first error.
- `gofmt -l .` to find unformatted files; format what you write.

## Modules & dependencies
- `go.mod` declares the module path and Go version; `go.sum` pins checksums.
- **`missing go.sum entry` / checksum mismatch** → run `go mod tidy` to reconcile; commit both files.
- **`cannot find module` / import path mismatch** → import path must match the module path in `go.mod`; check for a typo or a moved package.
- **Version conflicts** → inspect with `go mod graph`; pin with `require`/`replace` deliberately, avoid silent major bumps.
- Keep `go mod tidy` results committed so CI matches local.

## Idiomatic style (match the repo, but default to)
- Return errors, wrap with `fmt.Errorf("...: %w", err)`; don't panic in libraries.
- Accept interfaces, return concrete types. Keep zero values useful.
- Table-driven tests with subtests (`t.Run`); use `t.Helper()` in helpers.
- Use `context.Context` as the first arg for anything that blocks or crosses a boundary.
- Guard concurrency with the race detector: `go test -race ./...`.

## Build tags / cross-compile
Failures from `//go:build` constraints or `GOOS/GOARCH` — confirm the tags and target match the files being compiled.
