#!/usr/bin/env bash
# Download wasi-sdk and whisper.cpp, then apply patches/.
# Usage: scripts/fetch.sh [--force]   (--force re-clones whisper.cpp)
set -euo pipefail

. "$(dirname "$0")/env.sh"

for cmd in git curl cmake make go; do
  command -v "$cmd" >/dev/null || { echo "missing: $cmd (macOS: brew install cmake. Debian: apt install cmake make)" >&2; exit 1; }
done

if [[ ! -x "$WASI_SDK/bin/clang" ]]; then
  mkdir -p "$ROOT/.tools"
  major="${WASI_SDK_VERSION%%.*}"
  url="https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-$major/$(basename "$WASI_SDK").tar.gz"
  echo "downloading $url"
  curl -fsSL "$url" | tar xz -C "$ROOT/.tools"
  [[ "$(uname -s)" == Darwin ]] && xattr -dr com.apple.quarantine "$WASI_SDK" 2>/dev/null || true
fi

if [[ "${1:-}" == "--force" ]]; then
  rm -rf "$WHISPER_SRC"
fi
if [[ -d "$WHISPER_SRC" ]]; then
  echo "whisper.cpp already exists; use --force to re-clone" >&2
  exit 0
fi

git -c advice.detachedHead=false clone -q --depth 1 --branch "$WHISPER_CPP_TAG" https://github.com/ggml-org/whisper.cpp.git "$WHISPER_SRC"
for p in "$ROOT"/patches/*.patch; do
  echo "applying $(basename "$p")"
  git -C "$WHISPER_SRC" apply --whitespace=nowarn "$p"
done
