---
name: whisper-cpp-patch
description: Change whisper.cpp for whisper.go-wasm, through patches/. Use before editing anything under whisper.cpp/, adding or fixing a patch, or when a patch stops applying.
---

# Patch whisper.cpp

`whisper.cpp/` is a clone, ignored by Git. `patches/` holds the changes, one patch per whisper.cpp file.

> [!IMPORTANT]
> Prefer `compat/`. Patch whisper.cpp only for what compat cannot reach: its own logic, such as a `throw`, or ggml's thread count.

## Steps

1. Edit the file in `whisper.cpp/`. Mark the change with a comment that contains `WHISPERGO:` and says why.
2. A file without a patch yet needs a name: add it to `patch_name()` in `scripts/export-patches.sh`, with the next number.
3. Run `scripts/export-patches.sh`. It writes every patch again and refuses a change without a `WHISPERGO:` marker.
4. Build: `scripts/build.sh`. A change to a `CMakeLists.txt` needs `scripts/build.sh --reconfigure`.
5. Check that the patches apply to a fresh clone: `scripts/fetch.sh --force`, then build again.
6. Add the patch to README's patches/ table.

## Rejected designs

| Idea | Why not |
| --- | --- |
| Building with exceptions, `-fwasm-exceptions` | wasm2go has no exception handling. Every `try` and `throw` in the files built is rewritten instead. They are all on error paths. |
| `-Dtry=if(true)` and `-Dcatch(x)=if(false)` | A `catch` body that uses its exception, such as `e.what()`, does not compile then. |
| Targeting `wasm32-wasip1`, without threads | wasi-libc has no `pthread` there, and ggml ran every graph on one thread: 32.5 s for 11 s of audio with tiny.en. With wasi-threads and 8 threads, 4.2 s. |
| Leaving ggml's `__wasi__` thread check as is (`patches/0001`) | It forces one thread on any WASI target, wasi-threads too. The check now applies only without `-pthread`. |
| `-pthread` in the toolchain file's `CMAKE_C_FLAGS_INIT` | CMake ignores it when `CMAKE_C_FLAGS` is given. `_REENTRANT` was then undefined, and ggml stayed on one thread. `scripts/build.sh` passes it in `CMAKE_C_FLAGS`. |
| Leaving `abort_callback` to whisper.cpp alone | It checked it only after each pass of the encoder or the decoder. A canceled run with one thread went on for 21 s. `patches/0002` hands it to ggml's CPU backend too, which checks it between the operations of a graph. |
| Flash attention, whisper.cpp's default | It stays in the module, as scalar code: 46% of the time with tiny.en q5_1 and 8 threads. Without it, attention is matrix products, whose dot products run on the host. `compat/whisper_go.cpp` turns it off: 3.0 s became 2.6 s for 11 s of audio, before the host had SIMD. |
| Moving all of ggml's kernels to the host | The matrix products took 82% of the time once flash attention was off. Move another only when a profile shows it. Each import is ABI, and each kernel is code on both sides. |
| One host call per dot product, for matrix products | The host converted or unpacked the same row of `x` and column of `y` for each dot product. A block of 16 by 16 per call (`gw_mul_mat_tile`) unpacks each once. With SIMD, 1.10 s became 0.76 s. Taking 4 columns at a time made it 0.64 s. |
| F16's `vec_dot_type` as F32, to keep activations float32 | whisper.cpp also multiplies two F16 matrices, such as im2col's output. ggml's CPU backend then refuses the node, since it converts `src1` from F32 only. The tile converts each column once instead. |
| ggml's empty `ggml_thread_cpu_relax` on WASI | Its barrier spun without a call out. A thread with no CPU of its own then waited for Go's preemption at every barrier. With one busy goroutine, a run took 5.42 s instead of 1.15 s. `patches/0001` calls `sched_yield`, the host's `Gosched`, once every 4096 spins: 1.57 s then. |
| `sched_yield` on every spin, or every 1024 | Each `Gosched` wakes another OS thread (`wakep`). Every spin cost about 0.12 s of 0.8 s with 8 threads. Every 1024 spins still cost 16 to 19% with 8 or 12 threads. Every 4096 costs nothing measurable, and is as fast under load. |
| Blocks of 16 rows for `gw_mul_mat_tile` | A single column, as in the decoder, was converted again for each 16 rows. A block is now all the rows of a thread's chunk. |
| Sending ggml's single dot products to the host too | Once the matrix products went through `gw_mul_mat_tile`, the imports for `ggml_vec_dot_f16`, `q5_1_q8_1` and `q8_0_q8_0` were called 0 times with F16, q5_1 and q8_0 models. They were dropped before ABI 2 shipped. |
| Letting an allocation fail inside whisper.cpp | With `-fno-exceptions`, a failed `new` aborts, which traps and closes the model. `compat/whisper_go.cpp` checks for room first, with `gw_room`, and returns an error. Its pointer must be `volatile`: clang dropped a `malloc` whose memory was never used, and took it to have succeeded. |
| Room for 6 bytes a sample in `gw_full` | Too little. The mel spectrogram has 128 bands with large-v3. A fallback to sampling builds the KV cache 7 times as large. Each thread takes an 8 MiB stack. `gw_full_room` counts all of them from the model's sizes. |
| whisper.cpp's `whisper_free_state` when the KV cache cannot be rebuilt | `ctx` still held the freed state: the next call used it, and `whisper_free` freed it again. `patches/0002` keeps the state, and builds the cache of one decoder again at once. Language detection on the next call decodes before the decoders would rebuild it. |
| whisper.cpp's padded copy of the samples, for the mel spectrogram | It took 4 bytes a sample beside the host's own copy, in memory that never shrinks: about 230 MB an hour. `patches/0002` pads the samples as the workers read them (`whisper_go_padded`). |
| Detecting the language of audio under 100 ms | whisper.cpp detects before it returns early for such audio. That cost a pass of the encoder, named a language from almost nothing, and failed below 41 samples. `gw_full` gives such audio a language, and `gw_lang` returns an empty one. |
| Clearing the KV cache before language detection, after a NaN | It costs a memset of up to the 7x cache on every call. The NaN came from a sample out of range, so `whisper_go_padded` clips the samples instead. |
| Encoding the first window again after detection | Detection encodes it with the same mel spectrogram, and its decode leaves the cross-attention cache as it was. The second pass took a third of the time of a short call. |
| Chunks of 16 by 16, ggml's own, with blocks of 16 columns | Each row of a chunk was unpacked once per 16 columns, and each column once per 16 rows. Blocks of up to 64 columns took q5_1 from 2.89 s to 2.50 s with one thread. Chunks of 32 took it to 2.28 s. Chunks of 32 rows by 64 columns convert each row once per 64 columns: 1 to 4.5% faster again. |
| Chunks of 64 by 64 | The threads could not share so few chunks evenly. q5_1 with 8 threads took 0.48 s, and 0.39 s with 32. Chunks of 64 columns were slower with 16 or 24 rows than with 32. |
| Converting F16's float32 columns to float16 for the host | ggml did it in scalar code, and the host converted them back. `gw_f32_columns` passes them as they are. The host's copy must be vector code: a scalar one took 35% of the time. |
| Leaving softmax and the quantization of activations in the module | They were 15% and 7% of the time, in scalar code. `gw_soft_max` and `gw_quantize_row` run them on the host. The quantization must match ggml's to the bit, since its results feed every quantized product. |
