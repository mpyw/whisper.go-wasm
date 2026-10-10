#!/usr/bin/env bash
# Write the whisper.cpp working tree changes back to patches/, one file per patched source.
# Every change must carry a "WHISPERGO:" marker comment.
set -euo pipefail

. "$(dirname "$0")/env.sh"
cd "$WHISPER_SRC"

patch_name() {
  case "$1" in
    ggml/src/ggml-cpu/ggml-cpu.c) echo 0001-ggml-cpu-threads-and-tiles ;;
    src/whisper.cpp) echo 0002-whisper-without-exceptions-with-abort ;;
    ggml/src/gguf.cpp) echo 0003-gguf-without-exceptions ;;
    ggml/src/ggml-backend-reg.cpp) echo 0004-backend-registry-without-exceptions ;;
    ggml/src/ggml-cpu/ops.cpp) echo 0005-ggml-cpu-softmax-on-the-host ;;
  esac
}

# A patch whose change was reverted goes, and so does one of an old name.
for p in "$ROOT"/patches/*.patch; do
  file="$(patch_file "$p")"
  if [[ -z "$(patch_diff -- "$file")" || "$(patch_name "$file")" != "$(basename "$p" .patch)" ]]; then
    rm "$p"
    echo "removed patches/$(basename "$p")"
  fi
done

for file in $(patch_diff --name-only); do
  name="$(patch_name "$file")"
  if [[ -z "$name" ]]; then
    echo "no patch name for $file; add it to scripts/export-patches.sh" >&2
    exit 1
  fi
  # Every hunk carries a marker on a line it adds. A hunk that only deletes
  # has one on a line around it instead.
  unmarked="$(patch_diff -- "$file" | awk '
    function check() { if (hunk != "" && !marked && !(deletes && !adds && near)) print hunk }
    /^@@/ { check(); hunk = $0; marked = adds = deletes = near = 0; next }
    hunk == "" { next }
    /^\+/ { adds = 1; if (/WHISPERGO:/) marked = 1; next }
    /^-/ { deletes = 1; next }
    /WHISPERGO:/ { near = 1 }
    END { check() }')"
  if [[ -n "$unmarked" ]]; then
    echo "$file: a change has no WHISPERGO: marker, in" >&2
    echo "$unmarked" >&2
    exit 1
  fi
  patch_diff -- "$file" > "$ROOT/patches/$name.patch"
  echo "wrote patches/$name.patch"
done
