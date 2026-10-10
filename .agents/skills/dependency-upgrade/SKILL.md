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
6. Run whisper.go's tests against this checkout, then release as a patch version (release skill).
