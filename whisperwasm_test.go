package whisperwasm_test

import (
	"io/fs"
	"sync"
	"testing"

	whisperwasm "github.com/mpyw/whisper.go-wasm"
)

// testMemory never moves: its whole capacity is allocated up front.
type testMemory struct {
	buf     []byte
	waiters sync.Map
}

func (m *testMemory) Slice() *[]byte     { return &m.buf }
func (m *testMemory) Waiters() *sync.Map { return &m.waiters }

func (m *testMemory) Grow(delta, _ int64) int64 {
	old := int64(len(m.buf) >> 16)
	n := (old + delta) << 16
	if n > int64(cap(m.buf)) {
		return -1
	}
	m.buf = m.buf[:n]
	return old
}

type testEnv struct{ mem *testMemory }

func (e testEnv) Xmemory() whisperwasm.Memory { return e.mem }
func (e testEnv) Xgw_aborted() int32         { return 0 }

// testWASI fails every call. Loading a model that is not one reaches none
// of them but the clock and the log.
type testWASI struct{ t *testing.T }

func (w testWASI) Xclock_time_get(int32, int64, int32) int32 { return 0 }
func (w testWASI) Xenviron_get(int32, int32) int32           { return 0 }
func (w testWASI) Xenviron_sizes_get(int32, int32) int32     { return 0 }
func (w testWASI) Xfd_close(int32) int32                     { return 8 }
func (w testWASI) Xfd_fdstat_get(int32, int32) int32         { return 8 }
func (w testWASI) Xfd_fdstat_set_flags(int32, int32) int32   { return 8 }
func (w testWASI) Xfd_prestat_dir_name(int32, int32, int32) int32 {
	return 8
}
func (w testWASI) Xfd_prestat_get(int32, int32) int32         { return 8 }
func (w testWASI) Xfd_read(int32, int32, int32, int32) int32  { return 8 }
func (w testWASI) Xfd_seek(int32, int64, int32, int32) int32  { return 8 }
func (w testWASI) Xfd_write(int32, int32, int32, int32) int32 { return 8 }
func (w testWASI) Xpath_open(int32, int32, int32, int32, int32, int64, int64, int32, int32) int32 {
	return 8
}
func (w testWASI) Xproc_exit(code int32) { w.t.Fatalf("proc_exit(%d)", code) }
func (w testWASI) Xsched_yield() int32   { return 0 }

type testThreads struct{ t *testing.T }

func (th testThreads) Xthread_spawn_6s4jie(int32) int32 {
	th.t.Error("no thread is needed to reject a model")
	return -1
}

// TestModule loads bytes that are not a model. whisper.cpp must refuse
// them, and the module must keep working.
func TestModule(t *testing.T) {
	mem := &testMemory{buf: make([]byte, 0, 512<<20)}
	if mem.Grow(whisperwasm.InitialPages, 0) != 0 {
		t.Fatal("cannot grow the test memory")
	}
	m := whisperwasm.New(testEnv{mem}, testWASI{t}, testThreads{t})
	m.X_initialize()

	junk := []byte("not a ggml model")
	for range 2 {
		p := m.Xgw_malloc(int32(len(junk)))
		if p == 0 {
			t.Fatal("gw_malloc failed")
		}
		copy(mem.buf[p:], junk)
		if ctx := m.Xgw_init(p, int32(len(junk))); ctx != 0 {
			t.Errorf("gw_init accepted junk: %#x", ctx)
		}
		m.Xgw_free(p)
	}
}

func TestLicenses(t *testing.T) {
	for _, name := range []string{"whisper.cpp.txt", "yarn.txt", "wasi-libc.txt", "llvm.txt", "wasm2go.txt"} {
		if b, err := fs.ReadFile(whisperwasm.Licenses, name); err != nil || len(b) == 0 {
			t.Errorf("%s: %v", name, err)
		}
	}
}

func TestVersion(t *testing.T) {
	if whisperwasm.WhisperVersion == "" || len(whisperwasm.Digest) != 16 {
		t.Errorf("version.go: %q %q", whisperwasm.WhisperVersion, whisperwasm.Digest)
	}
}
