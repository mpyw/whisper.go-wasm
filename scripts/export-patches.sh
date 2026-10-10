#!/usr/bin/env bash
# Write the whisper.cpp working tree changes back to patches/, one file per patched source.
# Every change must carry a "WHISPERGO:" marker comment.
set -euo pipefail

. "$(dirname "$0")/env.sh"
cd "$WHISPER_SRC"

patch_name() {
  case "$1" in
    ggml/src/ggml-cpu/ggml-cpu.c) echo 0001-ggml-threads-on-wasi-threads ;;
    src/whisper.cpp) echo 0002-whisper-without-exceptions-with-abort ;;
    ggml/src/gguf.cpp) echo 0003-gguf-without-exceptions ;;
    ggml/src/ggml-backend-reg.cpp) echo 0004-backend-registry-without-exceptions ;;
  esac
}

for file in $(git diff --name-only); do
  name="$(patch_name "$file")"
  if [[ -z "$name" ]]; then
    echo "no patch name for $file; add it to scripts/export-patches.sh" >&2
    exit 1
  fi
  if ! git diff -- "$file" | grep -q 'WHISPERGO:'; then
    echo "$file: change has no WHISPERGO: marker" >&2
    exit 1
  fi
  git diff -- "$file" > "$ROOT/patches/$name.patch"
  echo "wrote patches/$name.patch"
done
