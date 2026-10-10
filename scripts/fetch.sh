#!/usr/bin/env bash
# Download wasi-sdk and whisper.cpp, then apply patches/.
# Usage: scripts/fetch.sh [--force]   (--force re-clones whisper.cpp)
set -euo pipefail

. "$(dirname "$0")/env.sh"

for cmd in git curl cmake make go; do
  command -v "$cmd" >/dev/null || { echo "missing: $cmd (macOS: brew install cmake. Debian: apt install cmake make)" >&2; exit 1; }
done

# download NAME SHA256 DIR: fetch a wasi-sdk release asset, check it, and
# unpack it in DIR.
download() {
  local url="https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK_VERSION%%.*}/$1"
  local tmp="$ROOT/.tools/$1.part"
  echo "downloading $url"
  curl -fsSL -o "$tmp" "$url"
  if [[ "$(shasum -a 256 "$tmp" | cut -d' ' -f1)" != "$2" ]]; then
    rm -f "$tmp"
    echo "$1: SHA-256 is not $2" >&2
    exit 1
  fi
  tar xzf "$tmp" -C "$3"
  rm -f "$tmp"
}

# The stamp marks a wasi-sdk with the host-independent sysroot and
# builtins in place of its own.
if [[ ! -f "$WASI_SDK/.whispergo" ]]; then
  sum="WASI_SDK_SHA256_${WASI_SDK_ARCH}_$WASI_SDK_OS"
  [[ -n "${!sum:-}" ]] || { echo "no wasi-sdk SHA-256 for $WASI_SDK_ARCH-$WASI_SDK_OS in scripts/env.sh" >&2; exit 1; }
  rm -rf "$WASI_SDK"
  mkdir -p "$ROOT/.tools"
  download "$(basename "$WASI_SDK").tar.gz" "${!sum}" "$ROOT/.tools"
  rm -rf "$WASI_SDK/share/wasi-sysroot"
  download "wasi-sysroot-$WASI_SDK_VERSION.tar.gz" "$WASI_SYSROOT_SHA256" "$WASI_SDK/share"
  mv "$WASI_SDK/share/wasi-sysroot-$WASI_SDK_VERSION" "$WASI_SDK/share/wasi-sysroot"
  rt="$(echo "$WASI_SDK"/lib/clang/*/lib)"
  rm -rf "$rt"
  download "libclang_rt-$WASI_SDK_VERSION.tar.gz" "$WASI_LIBCLANG_RT_SHA256" "${rt%/lib}"
  mv "${rt%/lib}/libclang_rt-$WASI_SDK_VERSION" "$rt"
  [[ "$(uname -s)" == Darwin ]] && xattr -dr com.apple.quarantine "$WASI_SDK" 2>/dev/null || true
  touch "$WASI_SDK/.whispergo"
fi

if [[ "${1:-}" == "--force" ]]; then
  rm -rf "$WHISPER_SRC"
fi
if [[ -d "$WHISPER_SRC" ]]; then
  echo "whisper.cpp already exists; use --force to re-clone" >&2
  exit 0
fi

git -c advice.detachedHead=false clone -q --depth 1 --branch "$WHISPER_CPP_TAG" https://github.com/ggml-org/whisper.cpp.git "$WHISPER_SRC"
if [[ "$(git -C "$WHISPER_SRC" rev-parse HEAD)" != "$WHISPER_CPP_COMMIT" ]]; then
  echo "$WHISPER_CPP_TAG is not $WHISPER_CPP_COMMIT: the tag moved" >&2
  rm -rf "$WHISPER_SRC"
  exit 1
fi
for p in "$ROOT"/patches/*.patch; do
  echo "applying $(basename "$p")"
  git -C "$WHISPER_SRC" apply --whitespace=nowarn "$p"
done
