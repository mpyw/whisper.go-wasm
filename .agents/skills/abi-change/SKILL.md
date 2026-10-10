---
name: abi-change
description: Change the contract between whisper.go-wasm's module and the whisper.go host - add, remove or change an export of compat/whisper_go.cpp, an import, the memory, or a shared constant. Use before editing ABI.md or compat/.
---

# Change the ABI

ABI.md is the whole contract. `whisperwasm.ABIVersion` numbers it, and whisper.go refuses a module with another one.

## Steps

1. Change ABI.md first: the function's signature, what it returns, and what the host must do.
2. Bump `ABIVersion` in `whisperwasm.go`.
3. Export it from `compat/whisper_go.cpp` with `GW_EXPORT("gw_name")`, as the other functions do. An import from the host is declared with `import_module("env")` and `import_name`, as `gw_aborted` is.
4. `whisperwasm_test.go` implements every import. A new import makes it fail to compile until the test host has it.
5. Implement the host side in whisper.go, and set its `hostABIVersion` to the same number (whisper.go's `whisper.go-wasm-upgrade` skill).
6. Release as a minor version (release skill).

## Rejected designs

| Idea | Why not |
| --- | --- |
| Reading the initial memory size from the wasm in the host | `version.go`'s `InitialPages` carries it. `scripts/build.sh` writes it from the same `INITIAL_MEMORY` it links with. |
| Letting whisper.cpp's language detection run with an English-only model | It costs one more pass of the encoder, for a known answer. `gw_full` passes `en` for such a model when the language is empty. |
