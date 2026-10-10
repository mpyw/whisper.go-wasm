# Source this to get the wasi-sdk cross toolchain environment.
# Versions are pinned here.
WHISPER_CPP_TAG="v1.9.5"
# The commit the tag names: a tag can move, and the clone checks this.
WHISPER_CPP_COMMIT="d1be6fde11ac6e0407606b4e42fe72d34add8037"
WASI_SDK_VERSION="34.0"
# SHA-256 of each wasi-sdk download, from the release's asset digests. The
# compiler is the host's. Its sysroot and builtins differ between hosts,
# with build paths inside, so every host links against the same ones from
# the host-independent downloads instead.
WASI_SDK_SHA256_arm64_macos="9c59398106b417f8f14913380fdf0097a8cc0ff4af9eb3ce0065a859e88d49e9"
WASI_SDK_SHA256_x86_64_macos="87d27fa8adc68dee59bfbf2e22a6d34ef717c34d6bf1d8af2a56fc929d9ce0eb"
WASI_SDK_SHA256_arm64_linux="f7e243dff54d60bcc576e94d6166b69f410f2500ae4a9ceef34315be10e77971"
WASI_SDK_SHA256_x86_64_linux="b761e3a0721dbae9c09a0059e5fdb2bf917d1b4a8a7b430fb3b5aafb0984b2c4"
WASI_SYSROOT_SHA256="9d813544eeebe38b7b8f2244ed591de46b6db812c6dd1a257ff9f0d2a905a2be"
WASI_LIBCLANG_RT_SHA256="eee3e634dcf71aa22b1333391623cf5c9965a637dc428a27b1a858c026c587f1"
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

# patch_diff [FILE...] diffs whisper.cpp/ against its tag, staged changes
# too, in the one format of patches/: the flags override any git config.
patch_diff() {
  git -C "$WHISPER_SRC" -c core.abbrev=7 diff --no-color --no-ext-diff --no-textconv \
    --src-prefix=a/ --dst-prefix=b/ -U3 --diff-algorithm=myers --indent-heuristic HEAD "$@"
}

# patch_file PATCH is the source file a patch of patches/ changes.
patch_file() { sed -n 's|^diff --git a/\(.*\) b/.*|\1|p' "$1" | head -1; }
