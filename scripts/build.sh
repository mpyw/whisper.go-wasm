#!/usr/bin/env bash
# Build whisper.cpp for wasm32-wasip1-threads, link it with compat/, and
# translate the module to Go: module.go, with version.go beside it.
# Usage: scripts/build.sh [--reconfigure]   (--reconfigure runs CMake again)
set -euo pipefail

. "$(dirname "$0")/env.sh"
[[ -d "$WHISPER_SRC" && -f "$WASI_SDK/.whispergo" ]] || { echo "run scripts/fetch.sh first" >&2; exit 1; }

# The clone must be patches/ applied to the pinned tag: fetch.sh keeps an
# existing one, which a pull may have left behind.
[[ "$(git -C "$WHISPER_SRC" describe --tags --exact-match 2>/dev/null)" == "$WHISPER_CPP_TAG" ]] ||
  { echo "whisper.cpp/ is not at $WHISPER_CPP_TAG: run scripts/fetch.sh --force" >&2; exit 1; }
patched=()
for p in "$ROOT"/patches/*.patch; do
  file="$(patch_file "$p")"
  [[ " ${patched[*]} " != *" $file "* ]] ||
    { echo "two patches change whisper.cpp/$file: run scripts/export-patches.sh" >&2; exit 1; }
  patched+=("$file")
  diff -q <(patch_diff -- "$file") "$p" > /dev/null ||
    { echo "whisper.cpp/$file differs from $(basename "$p"): run scripts/export-patches.sh, or scripts/fetch.sh --force" >&2; exit 1; }
done
for file in $(patch_diff --name-only); do
  [[ " ${patched[*]} " == *" $file "* ]] ||
    { echo "whisper.cpp/$file has changes no patch holds: run scripts/export-patches.sh" >&2; exit 1; }
done

# CMake drops a toolchain file's CMAKE_C_FLAGS_INIT when CMAKE_C_FLAGS is
# given, so -pthread is in FLAGS. Without it _REENTRANT is undefined, and
# patches/0001 leaves ggml on one thread.
# -ffile-prefix-map: GGML_ABORT names its file, and the path of the clone
# would end up in module.go. Then no two machines would build the same.
# CMake takes the flags as one string, so the path must have no spaces.
PREFIX_MAP="-ffile-prefix-map=$ROOT=."
FLAGS="-pthread $PREFIX_MAP -D_WASI_EMULATED_MMAN -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS"
CMAKE_ARGS=(
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=OFF
  -DGGML_NATIVE=OFF
  -DGGML_OPENMP=OFF
  -DGGML_BACKEND_DL=OFF
  -DGGML_CPU_ALL_VARIANTS=OFF
  -DGGML_LLAMAFILE=OFF
  -DWHISPER_BUILD_TESTS=OFF
  -DWHISPER_BUILD_EXAMPLES=OFF
  -DWHISPER_BUILD_SERVER=OFF
  -DWHISPER_SDL2=OFF
  -DWHISPER_CURL=OFF
)
CMAKE="$BUILD/cmake"
mkdir -p "$BUILD"
TOOLCHAIN="set(CMAKE_SYSTEM_NAME WASI)
set(CMAKE_SYSTEM_VERSION 1)
set(CMAKE_SYSTEM_PROCESSOR wasm32)
set(CMAKE_C_COMPILER $WASI_SDK/bin/clang)
set(CMAKE_CXX_COMPILER $WASI_SDK/bin/clang++)
set(CMAKE_AR $WASI_SDK/bin/llvm-ar)
set(CMAKE_RANLIB $WASI_SDK/bin/llvm-ranlib)
set(CMAKE_C_COMPILER_TARGET wasm32-wasip1-threads)
set(CMAKE_CXX_COMPILER_TARGET wasm32-wasip1-threads)
set(CMAKE_SYSROOT $WASI_SDK/share/wasi-sysroot)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)"
# Exceptions are off: wasm2go has no exception handling. patches/0002 to
# 0004 take the try and throw out of the files built.
CONFIGURE=(
  cmake -S "$WHISPER_SRC" -B "$CMAKE" -G "Unix Makefiles" -Wno-dev
  -DCMAKE_TOOLCHAIN_FILE="$BUILD/toolchain.cmake"
  -DCMAKE_C_FLAGS="$FLAGS"
  -DCMAKE_CXX_FLAGS="-fno-exceptions $FLAGS"
  "${CMAKE_ARGS[@]}"
)
# CMake keeps the flags and the compiler of its first run. A change of
# either configures again: the stamp hashes env.sh, the toolchain and the
# whole configure command, which names WASI_SDK's path.
stamp="$({ cat "$ROOT/scripts/env.sh"; echo "$TOOLCHAIN"; printf '%s\0' "${CONFIGURE[@]}"; } | shasum -a 256 | cut -c1-16)"
if [[ "${1:-}" == "--reconfigure" || "$(cat "$CMAKE/.stamp" 2>/dev/null)" != "$stamp" ]]; then
  rm -rf "$CMAKE"
fi
if [[ ! -f "$CMAKE/CMakeCache.txt" ]]; then
  echo "$TOOLCHAIN" > "$BUILD/toolchain.cmake"
  # From .build: CMake's check of the linker leaves an a.out where it runs.
  (cd "$BUILD" && "${CONFIGURE[@]}") > "$BUILD/cmake.log" 2>&1 || {
    # A failed configure leaves a cache that the next run would trust.
    tail -30 "$BUILD/cmake.log" >&2
    rm -rf "$CMAKE"
    exit 1
  }
  echo "$stamp" > "$CMAKE/.stamp"
fi
make -C "$CMAKE" -j"$NPROC" whisper > "$BUILD/make.log" 2>&1 || { tail -30 "$BUILD/make.log" >&2; exit 1; }

# A reactor: no main, and _initialize runs the constructors. The memory is
# imported and shared, for wasi-threads. --no-wasm-opt: clang would run any
# wasm-opt on PATH, which made the output depend on the machine. It also
# strips the names that wasm2go gives the Go methods.
"$WASI_SDK/bin/clang++" --target=wasm32-wasip1-threads --sysroot="$WASI_SDK/share/wasi-sysroot" \
  -pthread -O2 -fno-exceptions -mexec-model=reactor --no-wasm-opt "$PREFIX_MAP" \
  -I"$WHISPER_SRC/include" -I"$WHISPER_SRC/ggml/include" \
  "$ROOT/compat/whisper_go.cpp" \
  "$CMAKE/src/libwhisper.a" "$CMAKE/ggml/src/libggml.a" "$CMAKE/ggml/src/libggml-cpu.a" "$CMAKE/ggml/src/libggml-base.a" \
  -lwasi-emulated-mman -lwasi-emulated-signal -lwasi-emulated-process-clocks \
  -Wl,--import-memory,--export-memory \
  -Wl,--initial-memory="$INITIAL_MEMORY",--max-memory=4294967296 \
  -Wl,-z,stack-size="$STACK_SIZE" \
  -o "$BUILD/whisper.wasm"

# -unsafe: wasm2go needs it for the atomics of threads.
go run "github.com/ncruces/wasm2go@$WASM2GO_VERSION" -unsafe -pkg whisperwasm \
  -o "$ROOT/module.go" "$BUILD/whisper.wasm"

cat > "$ROOT/version.go" <<GO
// Code generated by scripts/build.sh. DO NOT EDIT.

package whisperwasm

// WhisperVersion is the whisper.cpp release the module is built from.
const WhisperVersion = "${WHISPER_CPP_TAG#v}"

// InitialPages is the size of the memory the module starts with, in 64 KiB
// pages. The memory a host gives New must hold at least that many.
const InitialPages = $((INITIAL_MEMORY / 65536))

// Digest identifies the module, the wasm that module.go was translated from.
const Digest = "$(shasum -a 256 "$BUILD/whisper.wasm" | cut -c1-16)"
GO
ls -lh "$BUILD/whisper.wasm" "$ROOT/module.go"
