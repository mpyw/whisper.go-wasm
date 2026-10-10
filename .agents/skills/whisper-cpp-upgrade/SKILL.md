---
name: whisper-cpp-upgrade
description: Move whisper.go-wasm to a new whisper.cpp release, such as v1.9.5 to v1.9.6. Use when WHISPER_CPP_TAG in scripts/env.sh changes, or when asked to update whisper.cpp itself.
---

# Upgrade whisper.cpp

## Steps

1. Set `WHISPER_CPP_TAG` in `scripts/env.sh`, such as `v1.9.6`. Releases are listed at https://github.com/ggml-org/whisper.cpp/releases.
2. Clone it again and apply `patches/`:

   ```sh
   scripts/fetch.sh --force
   ```

   A patch that no longer applies stops the script. Apply the rest by hand, in order, with `git -C whisper.cpp apply --reject`. Fix the rejected parts in `whisper.cpp/`, keep each `WHISPERGO:` marker, then run `scripts/export-patches.sh`. Read the whisper-cpp-patch skill first.
3. Build from scratch. A new release may change CMake's options, so reconfigure:

   ```sh
   scripts/build.sh --reconfigure
   ```

4. Check what whisper.cpp's own changes may break:

   | Where | What to check |
   | --- | --- |
   | `try`, `catch` and `throw` in the files built | A new one fails the build under `-fno-exceptions`. Rewrite it as `patches/0002` does: `grep -rnE '\b(try\|catch\|throw)\b' whisper.cpp/src whisper.cpp/ggml/src` |
   | `ggml/src/ggml-cpu/ggml-cpu.c` (`patches/0001`) | Whether ggml still forces one thread on `__wasi__` |
   | `ggml_graph_compute_helper` in `src/whisper.cpp` (`patches/0002`) | Whether every graph still gets `abort_callback`. whisper.go's `TestTranscribeCanceled` fails if not. |
   | `include/whisper.h` | The functions `compat/whisper_go.cpp` calls. A changed signature changes the ABI. |
   | `.build/make.log` | New warnings about atomics or threads |
   | A new third-party file under `src/` or `ggml/src/` | Its license. See the dependency-upgrade skill. |

5. Run `scripts/licenses.sh`. A license that changed shows in `git diff licenses/`.
6. Test: `go vet ./... && go test ./...` here, then whisper.go's whole suite against this checkout (whisper.go's `whisper.go-wasm-upgrade` skill, "Before a release").
7. Update whisper.cpp's row in README's "Versions inside" table.
8. Release as a patch version (release skill).
