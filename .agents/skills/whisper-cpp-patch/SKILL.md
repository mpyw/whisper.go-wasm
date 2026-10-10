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
| Leaving ggml's `__wasi__` check as is (`patches/0001`) | It forces one thread on any WASI target, wasi-threads too. The check now applies only without `-pthread`. |
| `-pthread` in the toolchain file's `CMAKE_C_FLAGS_INIT` | CMake ignores it when `CMAKE_C_FLAGS` is given. `_REENTRANT` was then undefined, and ggml stayed on one thread. `scripts/build.sh` passes it in `CMAKE_C_FLAGS`. |
| Leaving `abort_callback` to whisper.cpp alone | It checked it only after each pass of the encoder or the decoder. A canceled run with one thread went on for 21 s. `patches/0002` hands it to ggml's CPU backend too, which checks it between the operations of a graph. |
