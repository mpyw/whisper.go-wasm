# ABI

The contract between this module and its Go host, [whisper.go](https://github.com/mpyw/whisper.go).
`whisperwasm.ABIVersion` numbers it.

> [!IMPORTANT]
> Change `ABIVersion` whenever anything on this page changes.
> Then update the host to match. It refuses a module with another `ABIVersion`.

## The module

`whisper.wasm` is a `wasm32-wasip1-threads` reactor. `module.go` is its translation by wasm2go.

| In Go | Wasm |
| --- | --- |
| `New(env, wasi, threads)` | Instantiates the module over its three import modules |
| `(*Module).X_initialize()` | `_initialize`. Runs the C++ constructors. Call it once, on the first instance. |
| `(*Module).Xgw_*` | The exports below |
| `(*Module).Xwasi_thread_start(id, arg)` | `wasi_thread_start`. Runs a thread that `thread-spawn` asked for. |

## Exports

`compat/whisper_go.cpp` defines them. Pointers are i32 offsets into the memory.
`ctx` is a `whisper_context *`.

| Function | Signature | Returns |
| --- | --- | --- |
| `gw_malloc` | `(n i32)` | A pointer, or `0` |
| `gw_free` | `(p i32)` | Nothing |
| `gw_init` | `(model, size i32)` | A `ctx`, or `0` if the bytes are not a model. The model bytes may be freed after. |
| `gw_free_ctx` | `(ctx i32)` | Nothing |
| `gw_full` | `(ctx, pcm, n, threads, language i32)` | `0`, or `whisper_full()`'s error |
| `gw_lang` | `(ctx i32)` | The language of the last `gw_full`, a NUL-terminated string |
| `gw_n_segments` | `(ctx i32)` | The number of segments of the last `gw_full` |
| `gw_segment_text` | `(ctx, i i32)` | Segment `i`'s text, a NUL-terminated string |
| `gw_segment_t0`, `gw_segment_t1` | `(ctx, i i32)` | Segment `i`'s start and end, as an i64 in units of 10 ms |

`gw_full` takes `n` float32 samples at `pcm`: mono, 16 kHz, in [-1, 1].
`language` points to a NUL-terminated code such as `en`.
An empty one detects the language with a multilingual model, and means `en` with an English-only one.

> [!IMPORTANT]
> One `ctx` runs one `gw_full` at a time.
> The strings that `gw_lang` and `gw_segment_text` return live until the next `gw_full` or `gw_free_ctx`.

## Imports

### `env`

| Import | Type | Meaning |
| --- | --- | --- |
| `memory` | Shared memory, at least `InitialPages` pages, at most 65536 | The linear memory every thread shares |
| `gw_aborted` | `() i32` | `1` once the host wants the run to stop, else `0` |

> [!CAUTION]
> The memory must never move while the module runs.
> Other threads read it at the same time.
> A host reserves the whole address space up front, and grows within it.

ggml calls `gw_aborted` between the operations of a graph, from the graph's first thread only.
whisper.cpp also calls it before each pass of the encoder.
After a `1`, `gw_full` returns an error.

### `wasi_snapshot_preview1`

whisper.cpp needs no file system, arguments or environment.
These are what wasi-libc reaches:

| Function | What whisper.cpp needs from it |
| --- | --- |
| `fd_write` | Its log, on fd 1 and 2 |
| `clock_time_get` | The realtime and monotonic clocks. ggml also reads the CPU-time clocks, for its timings. |
| `sched_yield` | ggml's threads call it while they wait |
| `fd_close`, `fd_fdstat_get`, `fd_fdstat_set_flags`, `fd_prestat_get`, `fd_prestat_dir_name`, `fd_read`, `fd_seek`, `path_open`, `environ_get`, `environ_sizes_get` | Nothing. wasi-libc calls them at startup, or never. An error such as `EBADF` will do. |
| `proc_exit` | Nothing. A reactor never calls `exit()`. |

### `wasi`

| Function | Signature | Returns |
| --- | --- | --- |
| `thread-spawn` | `(arg i32)` | A thread ID above `0`, or a negative errno |

The host makes a new instance with `New`, over the same imports.
On a goroutine of its own, it calls that instance's `Xwasi_thread_start(id, arg)`.
It must not call `X_initialize` on that instance.

## Traps

`GGML_ABORT` and the rewritten `throw`s of `patches/0002` to `0004` trap.
In Go, a trap is a panic in the goroutine that runs the instance.

> [!WARNING]
> After a trap, the memory may hold half-done state.
> The host must not call the module again.
> A trap on a thread leaves the others waiting for it, so the host cannot recover it there.
