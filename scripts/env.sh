# Source this to get the wasi-sdk cross toolchain environment.
# Versions are pinned here.
WHISPER_CPP_TAG="v1.9.5"
WASI_SDK_VERSION="34.0"
# wasm2go translates the linked module to Go. Its version shapes module.go.
WASM2GO_VERSION="v0.4.16"
# The linear memory the module starts with: its data segments and its 8 MiB
# stack. version.go's InitialPages is the same size in 64 KiB pages.
INITIAL_MEMORY=16777216
STACK_SIZE=8388608

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Work directories, all ignored by Git.
WHISPER_SRC="$ROOT/whisper.cpp"
BUILD="$ROOT/.build"
case "$(uname -m)" in
  arm64 | aarch64) WASI_SDK_ARCH=arm64 ;;
  *) WASI_SDK_ARCH=x86_64 ;;
esac
case "$(uname -s)" in
  Darwin) WASI_SDK_OS=macos ;;
  *) WASI_SDK_OS=linux ;;
esac
export WASI_SDK="$ROOT/.tools/wasi-sdk-$WASI_SDK_VERSION-$WASI_SDK_ARCH-$WASI_SDK_OS"
NPROC="$(getconf _NPROCESSORS_ONLN)"
