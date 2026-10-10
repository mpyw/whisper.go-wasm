<div align="center">

<img src=".github/assets/icon.png" width="200" alt="A Go gopher in a glowing visor, cupping a paw to its ear, listening to sound waves">

# whisper.go-wasm

whisper.cpp, compiled to WebAssembly and translated to Go source, packaged as a Go module.

[![Build](https://github.com/mpyw/whisper.go-wasm/actions/workflows/build.yml/badge.svg)](https://github.com/mpyw/whisper.go-wasm/actions/workflows/build.yml)
[![Go Reference](https://pkg.go.dev/badge/github.com/mpyw/whisper.go-wasm.svg)](https://pkg.go.dev/github.com/mpyw/whisper.go-wasm)

</div>

[whisper.go](https://github.com/mpyw/whisper.go) runs this module.
That is how whisper.go transcribes speech from Go with no cgo.

> [!WARNING]
> This is an experiment. The ABI and the Go API will change.

> [!TIP]
> **To transcribe speech, use whisper.go, not this module.**
> This module only holds the translated code.
> You need it directly only to write your own host, or to rebuild it.

> [!CAUTION]
> **main and the other branches hold no generated code.** Only release tags, such as `v0.0.0`, carry it.
> Depend on a tag: `go get github.com/mpyw/whisper.go-wasm@latest`, or a version such as `@v0.0.0`.
> `@main` or a commit hash gets the sources alone, and the package does not build.
> To work from a branch, build the module first. See [Rebuild the module](#rebuild-the-module).

## In one table

| Question | Answer |
| --- | --- |
| What is inside? | whisper.cpp and ggml, built for `wasm32-wasip1-threads` with a few small patches. [wasm2go](https://github.com/ncruces/wasm2go) translated the module to Go. |
| Do I need a C compiler to use it? | No. Each release tag carries `module.go`, the translation. `go get` is enough. |
| Does it need a Wasm runtime? | No. `module.go` is plain Go. It needs a host for its imports. [ABI.md](ABI.md) lists them. |
| Which whisper.cpp version? | See [Versions inside](#versions-inside), or the constant `WhisperVersion`. |
| Does it use threads? | Yes, through wasi-threads. Each thread is a goroutine. |

## Use it from Go

```sh
go get github.com/mpyw/whisper.go-wasm
```

```go
import whisperwasm "github.com/mpyw/whisper.go-wasm"

m := whisperwasm.New(env, wasi, threads) // the host's three import modules
m.X_initialize()
```

| Name | Kind | What it is |
| --- | --- | --- |
| `New(env, wasi, threads)` | function | An instance of the module over the host's imports |
| `Module` | type | An instance. Its `Xgw_*` methods are the exports in [ABI.md](ABI.md). |
| `Xenv`, `Xwasi_snapshot_preview1`, `Xwasi`, `Memory` | interfaces | What the host implements |
| `WhisperVersion` | constant | The whisper.cpp release the module was built from |
| `InitialPages` | constant | The memory the module starts with, in 64 KiB pages |
| `Digest` | constant | Identifies the wasm that `module.go` was translated from |
| `ABIVersion` | constant | The version of the contract with the host |
| `Licenses` | `fs.FS` | The license of each component |

> [!IMPORTANT]
> A host must compare `ABIVersion` with the version it implements.
> If they differ, it must refuse to run the module.
> whisper.go does this.

### Versions inside

Every version is pinned in `scripts/env.sh`. This table follows it.

| Component | Version | In |
| --- | --- | --- |
| whisper.cpp, with ggml | 1.9.5 | `module.go` |
| wasi-sdk | 34.0 | The toolchain. wasi-libc and libc++ come from it. |
| wasm2go | v0.4.16 | The translator. Its helper functions are in `module.go`. |

## Releases

The module's version is not whisper.cpp's version. Read `WhisperVersion` for that.

| Change | Version bump |
| --- | --- |
| `ABIVersion` changes | Minor, while below v1 |
| Anything else, such as a new whisper.cpp release | Patch |

To release, run the `build` workflow on main by hand, with the version, such as `v0.0.0`.
It builds and tests from scratch.
Then it commits the sources and the generated code as an orphan commit, and pushes only its tag.

| Ref | Holds |
| --- | --- |
| `main` and other branches | The sources |
| A tag, such as `v0.0.0` | The sources and the generated code, in a commit of its own. Its message names the source commit. |

> [!NOTE]
> A release commit has no parent, and no branch contains it.
> A clone of main with `git clone --single-branch --no-tags` downloads no generated code.

## Rebuild the module

CI builds the module from scratch on every push, and tests it.
Build locally to try a change before you push it.
The build runs on macOS and Linux, in a checkout whose path has no spaces.

### Steps

```sh
brew install cmake           # macOS
sudo apt install cmake make  # Debian, Ubuntu
scripts/fetch.sh             # 1. download wasi-sdk and whisper.cpp, apply patches/
scripts/build.sh             # 2. build the module, write module.go and version.go
```

The outputs, `whisper.cpp/`, `.build/` and `.tools/` are ignored by Git.
Branches hold only the sources, so the Go package builds only after these steps.

| Script | What it does | Writes |
| --- | --- | --- |
| `scripts/env.sh` | Pins every version. The other scripts read it. | Nothing |
| `scripts/fetch.sh` | Downloads wasi-sdk, with the sysroot and builtins that every host shares, and checks their SHA-256. Clones whisper.cpp at its pinned commit. `--force` clones again. | `.tools/`, `whisper.cpp/` |
| `scripts/build.sh` | Builds whisper.cpp, links the module and translates it. `--reconfigure` runs CMake again. | `module.go`, `version.go` |
| `scripts/export-patches.sh` | Saves your changes in `whisper.cpp/` | `patches/` |
| `scripts/licenses.sh` | Collects the licenses of every component, after `scripts/fetch.sh` | `licenses/` |

### Changing whisper.cpp

1. Edit the files in `whisper.cpp/`.
2. Put a comment with `WHISPERGO:` next to each change.
3. Run `scripts/export-patches.sh`.

> [!WARNING]
> `scripts/export-patches.sh` refuses a change without a `WHISPERGO:` marker.
> The marker lets you find every change with `grep WHISPERGO:`.

## How the build works

whisper.cpp is built with [wasi-sdk](https://github.com/WebAssembly/wasi-sdk), for `wasm32-wasip1-threads`, with exceptions off.
wasm2go then translates the linked module to one Go file.
The matrix products that take most of ggml's time are left to the host, which can run them as SIMD.
Two directories hold every difference from whisper.cpp.

### patches/

| Patch | What it changes |
| --- | --- |
| `0001-ggml-cpu-threads-and-tiles.patch` | ggml runs a graph on several threads when built with `-pthread`. It used one thread on any WASI target. Its spinning threads yield to the host's scheduler once every 4096 spins. Its matrix products of F16, Q4_0, Q4_1, Q5_0, Q5_1 and Q8_0 call the host once per block, of chunks of 32 rows by 64 columns. F16 rows take float32 columns as they are. Activations are quantized on the host. See [ABI.md](ABI.md#kernels). |
| `0002-whisper-without-exceptions-with-abort.patch` | whisper.cpp's `throw`s become `GGML_ABORT`, and its `try` blocks plain blocks. wasm2go has no exception handling. It also hands `abort_callback` to ggml, so a canceled run stops between two operations. A failed rebuild of the KV cache keeps the state, rather than freeing it under `ctx`, and builds the cache of one decoder again. The mel buffer is freed before it grows again. Its threads check for a cancel too, and pad the samples as they read them, with no copy, clipped to [-1, 1]. Detection's pass of the encoder serves the first window too. |
| `0003-gguf-without-exceptions.patch` | The same for ggml's GGUF reader |
| `0004-backend-registry-without-exceptions.patch` | The same for ggml's backend registry |
| `0005-ggml-cpu-softmax-on-the-host.patch` | ggml's softmax of a row goes to the host's `gw_soft_max`, unless it has attention sinks. |

### compat/

| File | What it provides |
| --- | --- |
| `whisper_go.cpp` | The exports in [ABI.md](ABI.md), over whisper.cpp's C API. It turns flash attention off, and stubs `dlopen` and friends, since the CPU backend is linked in. |

## License

This repository's own code (`compat/`, `scripts/`, `patches/` and the Go files) is under the [MIT License](LICENSE).
`module.go` contains other software, under their own licenses.
Their texts are in [licenses/](licenses), and in Go as `whisperwasm.Licenses`.

| Component | License | Text |
| --- | --- | --- |
| whisper.cpp and ggml | MIT | `whisper.cpp.txt` |
| ggml's YaRN RoPE code | MIT, by its own authors | `yarn.txt` |
| wasi-libc | Apache 2.0 with LLVM exceptions, Apache 2.0, or MIT | `wasi-libc.txt`, `wasi-libc-apache-llvm.txt`, `wasi-libc-mit.txt` |
| musl, in wasi-libc | MIT | `musl.txt` |
| cloudlibc, in wasi-libc | BSD 2-Clause | `cloudlibc.txt` |
| dlmalloc, in wasi-libc | CC0 | `dlmalloc.txt` |
| libc++, libc++abi, compiler-rt | Apache 2.0 with LLVM exceptions | `llvm.txt` |
| wasm2go's helper functions | MIT | `wasm2go.txt` |

The mascot is the Go gopher, designed by Renée French, under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
