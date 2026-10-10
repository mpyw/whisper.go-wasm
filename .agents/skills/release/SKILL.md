---
name: release
description: Release a new whisper.go-wasm version, then move whisper.go to it. Use when asked to release, tag, or publish the module, or when whisper.go needs a module built from newer sources.
---

# Release

Only the `build` workflow releases. It builds and tests from scratch, makes an **orphan commit** of the sources and the generated Go, and pushes only its tag. Branches never hold `module.go`.

## Steps

1. Push the sources to main, as ordinary commits or a merged pull request.
2. Pick the version. The workflow also publishes a GitHub release titled `vX.Y.Z (whisper.cpp x.y.z)`. Never reuse one that was pushed.

   | Change since the last release | Bump |
   | --- | --- |
   | `ABIVersion` | Minor, while below v1 |
   | Anything else, such as a whisper.cpp or wasi-sdk update | Patch |

3. Run the release and wait for it:

   ```sh
   gh workflow run build.yml -R mpyw/whisper.go-wasm --ref main -f version=vX.Y.Z
   gh run watch -R mpyw/whisper.go-wasm "$(gh run list -R mpyw/whisper.go-wasm -L 1 --json databaseId -q '.[0].databaseId')" --exit-status
   ```

   It fails before building if the version is malformed or exists already.
4. In whisper.go, follow its `whisper.go-wasm-upgrade` skill.

> [!CAUTION]
> A pushed tag is permanent. The first `go get` puts the version in proxy.golang.org and sum.golang.org, which keep it forever, and every Go module cache keeps it too.
> Never move, delete or reuse one. A broken release is fixed by the next version.

## Rejected designs

| Idea | Why not |
| --- | --- |
| `module.go` built on a developer's Mac and committed by hand | Nothing would prove it came from the committed sources. CI builds it instead. |
| Committing `module.go` to main on every push | About 10 MB, and nearly every line changes with each rebuild, so each change would add over 1 MB compressed. A release tag carries it instead, on an orphan commit. |
| Release tags on commits that main contains | A clone would still fetch every release's `module.go` through main's history. Orphan commits keep it out of branches. |
| A separate generator run by `go generate` in whisper.go | `go install` and `go get` never run it, so users would need wasi-sdk, CMake and wasm2go. |
| Keeping main at one commit, amended and force-pushed | It saved nothing: `module.go` is never on a branch, so main's history is small anyway. It also broke as soon as a pull request was merged. |
