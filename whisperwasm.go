// Package whisperwasm holds whisper.cpp compiled to WebAssembly
// (wasm32-wasip1-threads) and translated to Go source by wasm2go, for
// github.com/mpyw/whisper.go.
//
// module.go is the translation: New instantiates the module over the host's
// imports. Release tags commit it, so that using this package needs only Go.
// scripts/ rebuilds it from whisper.cpp, patches/ and compat/.
package whisperwasm

import (
	"embed"
	"io/fs"
)

// ABIVersion numbers the contract between this module and its Go host: the
// functions it exports and imports, its memory, and the constants both
// sides share. ABI.md lists them. It changes whenever any of them does, and
// the host refuses a module with another ABIVersion.
const ABIVersion = 1

// Licenses holds the license of each component of module.go, as
// <component>.txt. Whoever distributes it must pass these on. README.md
// lists which applies to what.
var Licenses fs.FS = mustSub(licenseFiles, "licenses")

//go:embed licenses/*.txt
var licenseFiles embed.FS

func mustSub(f fs.FS, dir string) fs.FS {
	sub, err := fs.Sub(f, dir)
	if err != nil {
		panic(err)
	}
	return sub
}
