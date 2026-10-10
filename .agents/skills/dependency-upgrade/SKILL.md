---
name: dependency-upgrade
description: Update the toolchain or the translator that whisper.go-wasm builds with, wasi-sdk or wasm2go. Use when bumping WASI_SDK_VERSION or WASM2GO_VERSION in scripts/env.sh.
---

# Upgrade a dependency

Every version is pinned in `scripts/env.sh`.

## Where to find new versions

| Tool | Variable | Releases |
| --- | --- | --- |
| wasi-sdk | `WASI_SDK_VERSION` | https://github.com/WebAssembly/wasi-sdk/releases |
| wasm2go | `WASM2GO_VERSION` | https://github.com/ncruces/wasm2go/tags |

## Steps

1. Change the version in `scripts/env.sh`.
2. Build from scratch and test:

   ```sh
   scripts/fetch.sh && scripts/build.sh --reconfigure && go vet ./... && go test ./...
   ```

3. Check the tool's own changes:

   | Tool | What breaks |
   | --- | --- |
   | wasi-sdk | The `wasm32-wasip1-threads` sysroot, and the WASI functions wasi-libc imports. A new import makes `module.go`'s `Xwasi_snapshot_preview1` grow, and the ABI with it. |
   | wasm2go | The generated API: `New`'s parameters, the import interfaces, `Memory`. Whether `-unsafe` is still needed for atomics. |

4. Run `scripts/licenses.sh`. It takes wasi-libc's and LLVM's texts from the commits wasi-sdk pins. A license that changed shows in `git diff licenses/`.
5. Update README's "Versions inside" table.
6. Run whisper.go's tests against this checkout, then release (release skill): a patch version, or a minor one if a new WASI import changed the ABI.

## Rejected designs

| Idea | Why not |
| --- | --- |
| Pinning binaryen, as gophper-wasm does | clang runs any `wasm-opt` on PATH after linking, so the output depended on the machine. `scripts/build.sh` passes `--no-wasm-opt` instead. With tiny.en q5_1 and 8 threads, wasm-opt changed 3.03 s to 3.0 s, and it strips the names wasm2go uses for the Go methods. |
