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
| `gw_init` | `(model, size i32)` | A `ctx`, or `0` if the bytes are not a model, or if memory has no room for it. The model bytes may be freed after. |
| `gw_free_ctx` | `(ctx i32)` | Nothing |
| `gw_full` | `(ctx, pcm, n, threads, language i32)` | `0`, or an error: `-100` for an unknown language, `-101` for no room for the audio, `-102` for `n` below `1`, or `whisper_full()`'s. Samples outside [-1, 1] are clipped, and NaN reads as `0`. |
| `gw_lang` | `(ctx i32)` | The language of the last `gw_full`, as given or detected, as a NUL-terminated string. It is empty when below 1640 samples left nothing to detect. Valid only after a `gw_full` that returned `0`. |
| `gw_n_segments` | `(ctx i32)` | The number of segments of the last `gw_full` |
| `gw_segment_text` | `(ctx, i i32)` | Segment `i`'s text, a NUL-terminated string |
| `gw_segment_t0`, `gw_segment_t1` | `(ctx, i i32)` | Segment `i`'s start and end, as an i64 in units of 10 ms |

`gw_full` takes `n` float32 samples at `pcm`: mono, 16 kHz, in [-1, 1].
It runs on `threads` threads, 1 to 32. Each takes an 8 MiB stack from the memory.
`language` points to a NUL-terminated code such as `en`.
An empty one, or `auto`, detects the language with a multilingual model, and means `en` with an English-only one.

> [!WARNING]
> A file with a valid header but damaged sizes may trap in `gw_init`, rather than return `0`.
> whisper.cpp caught the failed allocation there, which `patches/0002` turns into a trap.

> [!IMPORTANT]
> A module holds one `ctx` at a time, and it runs one `gw_full` at a time.
> `gw_lang` keeps the given language in the module, not in the `ctx`.
> The strings that `gw_lang` and `gw_segment_text` return live until the next `gw_full` or `gw_free_ctx`.

## Imports

### `env`

| Import | Type | Meaning |
| --- | --- | --- |
| `memory` | Shared memory, at least `InitialPages` pages, at most 65536 | The linear memory every thread shares |
| `gw_aborted` | `() i32` | `1` once the host wants the run to stop, else `0` |
| `gw_mul_mat_tile` | `(type, ytype, n, nr0, nr1, xs, bx, ys, ds i32)` | Nothing. See [Kernels](#kernels). |
| `gw_quantize_row` | `(type, x, y, k i32)` | Nothing. See [Kernels](#kernels). |
| `gw_soft_max` | `(n, dst, src, mask, mask_f16 i32, scale, slope f32)` | Nothing. See [Kernels](#kernels). |

> [!CAUTION]
> The memory must never move while the module runs.
> Other threads read it at the same time.
> A host reserves the whole address space up front, and grows within it.

ggml calls `gw_aborted` between the operations of a graph, from the graph's first thread only.
whisper.cpp also calls it before each pass of the encoder, and from the mel spectrogram's threads, every 4096 frames.

> [!IMPORTANT]
> After a `1`, `gw_full` may still return `0`, with part of the result.
> A `1` before a pass of the encoder makes whisper.cpp stop there, with success or with an error.
> The host decides by its own cancel state, not by `gw_full`'s result.

### Kernels

ggml spends most of its time in matrix products, softmax and the quantization of activations. The host runs them as Go code, with SIMD where it has it.

`patches/0001` sends each block of a matrix product to `gw_mul_mat_tile`, for these types of `x` and `y`:

| `type` | `ytype` | `x`, a row | `y`, a column |
| --- | --- | --- | --- |
| `1`, F16 | `1`, F16 | `n` float16 | `n` float16 |
| `1`, F16 | `0`, F32 | `n` float16 | `n` float32 |
| `2`, Q4_0 | `8`, Q8_0 | `n/32` q4_0 blocks, 18 bytes each | `n/32` q8_0 blocks, 34 bytes each |
| `3`, Q4_1 | `9`, Q8_1 | `n/32` q4_1 blocks, 20 bytes each | `n/32` q8_1 blocks, 36 bytes each |
| `6`, Q5_0 | `8`, Q8_0 | `n/32` q5_0 blocks, 22 bytes each | `n/32` q8_0 blocks, 34 bytes each |
| `7`, Q5_1 | `9`, Q8_1 | `n/32` q5_1 blocks, 24 bytes each | `n/32` q8_1 blocks, 36 bytes each |
| `8`, Q8_0 | `8`, Q8_0 | `n/32` q8_0 blocks, 34 bytes each | `n/32` q8_0 blocks, 34 bytes each |

`xs`, `ys` and `ds` each point to `nr1` pointers, one per column.
`nr1` is at most 64.
`nr0` is the rows of a thread's chunk of the product, and has no limit.
For column `c` and row `r`, the host writes a float32 to `ds[c] + 4*r`.
It is the dot product of `n` values: of the row at `xs[c] + r*bx`, and of the column at `ys[c]`.
Columns of the same matrix have the same `xs[c]`, so the host can unpack each row once for them.
Q8_0 and Q8_1 columns all come from `gw_quantize_row`, since whisper.cpp never multiplies by a quantized tensor from the model.
Their values are within ±127, never -128, and a host may count on it, as whisper.go's int16 sums do.

The blocks are ggml's, in `ggml/src/ggml-common.h`.
A host may sum in any order, as ggml's own SIMD code does.
Every thread calls it, at the same time.

`gw_quantize_row` quantizes the `k` float32 values at `x` into `k/32` blocks at `y`, of `type` `8` (Q8_0) or `9` (Q8_1).
It must give ggml's `quantize_row_q8_0_ref` and `quantize_row_q8_1_ref` to the bit: `roundf`, and float16 rounded to nearest even.
`k` is a multiple of 32.

`gw_soft_max` writes the softmax of a row of `n` float32 values to `dst`: of `src*scale + slope*mask`.
`mask` is `n` float16 values if `mask_f16` is `1`, else float32 values, or none if it is `0`.
`dst` may be `src`.
ggml's own code, `ggml_compute_forward_soft_max_f32` (`patches/0005`), runs it for a row with attention sinks.

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
