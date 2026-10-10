# whisper.go-wasm

whisper.cpp compiled to wasm32-wasip1-threads and translated to Go by wasm2go, for whisper.go. See README.md for the layout and ABI.md for the host contract.

## Rules

- Do not commit `whisper.cpp/`. Change it there, then run `scripts/export-patches.sh`.
- Every whisper.cpp change carries a `WHISPERGO:` marker comment. The export script refuses changes without one.
- Prefer `compat/` over patching whisper.cpp. A missing symbol belongs in `compat/`.
- `module.go` and `version.go` are build outputs, ignored on branches. Only a release tag carries them, so the Go package builds only after `scripts/` ran.
- Release only through the `build` workflow. Never tag by hand, and never move, delete or reuse a pushed tag. The module proxy and the checksum database keep every version forever.
- For now main is one commit. Fold each change into it with `git commit --amend` and `git push --force`.
- Any change to ABI.md bumps `ABIVersion`, and whisper.go's `hostABIVersion` must follow.
- A change of what goes into `module.go` reruns `scripts/licenses.sh`, and updates README's license table.

## Skills

Read the matching one in `.agents/skills/` before you start. Each lists the designs already rejected in its area, and why.

| Skill | When |
| --- | --- |
| `release` | Releasing a version |
| `whisper-cpp-upgrade` | Moving to a new whisper.cpp release |
| `dependency-upgrade` | Updating wasi-sdk or wasm2go |
| `whisper-cpp-patch` | Changing whisper.cpp, or a patch that stopped applying |
| `abi-change` | An export, an import, the memory, or a shared constant |

## Before you finish

```sh
scripts/build.sh && go vet ./... && go test ./...
```

Then run whisper.go's tests against this checkout, through a `go.work` that uses both.

## Rejected designs

| Idea | Why not |
| --- | --- |
| Transpile whisper.cpp to Go with ccgo (modernc style) | ccgo is C only. whisper.cpp and most of ggml are C++. |
| Commit `module.go` to main | It is 8.5 MB and 276,000 lines, and nearly every line changes with each rebuild. A release tag carries it instead, on an orphan commit. |

## Known caveats

- wasm2go has no SIMD. ggml runs its scalar code, 14 to 23 times slower than native whisper.cpp with 8 threads on an M2 Pro, with tiny.en.
- whisper.cpp's errors that threw now trap (`patches/0002` to `0004`). A trap closes the model on the host.
