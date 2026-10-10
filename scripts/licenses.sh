#!/usr/bin/env bash
# Collect the licenses of everything in module.go into licenses/.
# Run it after scripts/fetch.sh, when a version in env.sh changes.
set -euo pipefail

. "$(dirname "$0")/env.sh"
OUT="$ROOT/licenses"
rm -rf "$OUT"
mkdir -p "$OUT"

copy() { # name file
  cp "$2" "$OUT/$1.txt"
}
fetch() { # name url
  curl -fsSL -o "$OUT/$1.txt" "$2"
}
# The commit of a wasi-sdk submodule at our wasi-sdk release, so that each
# text is the one of the code linked in.
submodule() { # path
  curl -fsSL "https://api.github.com/repos/WebAssembly/wasi-sdk/contents/$1?ref=wasi-sdk-${WASI_SDK_VERSION%%.*}" |
    sed -n 's/^ *"sha": "\([0-9a-f]*\)".*/\1/p' | head -1
}

copy whisper.cpp "$WHISPER_SRC/LICENSE"
# ggml's YaRN RoPE code in ggml-cpu/ops.cpp names its own authors. The
# translation drops comments, so the notice is kept here.
{
  echo "ggml/src/ggml-cpu/ops.cpp, the YaRN RoPE functions:"
  echo
  grep -m1 'Copyright (c) 2023 Jeffrey Quesnelle and Bowen Peng' "$WHISPER_SRC/ggml/src/ggml-cpu/ops.cpp" | sed 's|^// *||'
  echo
  sed -n '/^Permission is hereby granted/,$p' "$WHISPER_SRC/LICENSE"
} > "$OUT/yarn.txt"

libc="$(submodule src/wasi-libc)"
llvm="$(submodule src/llvm-project)"
for v in libc llvm; do
  [[ -n "${!v}" ]] || { echo "cannot find wasi-sdk's $v commit" >&2; exit 1; }
done
base="https://raw.githubusercontent.com/WebAssembly/wasi-libc/$libc"
fetch wasi-libc "$base/LICENSE"
fetch wasi-libc-mit "$base/LICENSE-MIT"
fetch wasi-libc-apache-llvm "$base/LICENSE-APACHE-LLVM"
fetch musl "$base/libc-top-half/musl/COPYRIGHT"
fetch cloudlibc "$base/libc-bottom-half/cloudlibc/LICENSE"
# dlmalloc is CC0, and says so in its source.
printf '%s\n' "dlmalloc, wasi-libc's malloc, is CC0. See the notice in $base/dlmalloc/src/malloc.c" > "$OUT/dlmalloc.txt"
fetch llvm "https://raw.githubusercontent.com/llvm/llvm-project/$llvm/libcxx/LICENSE.TXT"
# module.go carries helper functions of wasm2go's own.
fetch wasm2go "https://raw.githubusercontent.com/ncruces/wasm2go/$WASM2GO_VERSION/LICENSE"

ls "$OUT"
