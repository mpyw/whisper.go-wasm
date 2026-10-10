// The functions github.com/mpyw/whisper.go calls. ABI.md lists them.
// Pointers are offsets into the module's linear memory, and the host
// allocates them with gw_malloc.
#include <cstdlib>
#include <cstring>

#include "whisper.h"

#define GW_EXPORT(name) __attribute__((export_name(name)))

// gw_aborted reports whether the Go caller's context is done. ggml asks
// between the operations of a graph, so a canceled run stops within one.
__attribute__((import_module("env"), import_name("gw_aborted"))) int gw_aborted(void);

static bool gw_abort(void *) { return gw_aborted() != 0; }

static bool gw_encoder_begin(whisper_context *, whisper_state *, void *) { return gw_aborted() == 0; }

extern "C" {

GW_EXPORT("gw_malloc") void *gw_malloc(size_t n) { return malloc(n); }

GW_EXPORT("gw_free") void gw_free(void *p) { free(p); }

GW_EXPORT("gw_init")
whisper_context *gw_init(void *model, size_t size) {
	whisper_context_params cp = whisper_context_default_params();
	cp.use_gpu = false;
	return whisper_init_from_buffer_with_params(model, size, cp);
}

GW_EXPORT("gw_free_ctx") void gw_free_ctx(whisper_context *ctx) { whisper_free(ctx); }

// gw_full transcribes n samples of 16 kHz mono audio. An empty language
// detects it, except with an English-only model: detection would cost one
// more pass of the encoder there, for a known answer.
GW_EXPORT("gw_full")
int gw_full(whisper_context *ctx, const float *pcm, int n, int threads, const char *language) {
	whisper_full_params p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
	p.n_threads = threads;
	p.language = language[0] != '\0' ? language : whisper_is_multilingual(ctx) ? "auto" : "en";
	p.print_progress = false;
	p.print_realtime = false;
	p.print_timestamps = false;
	p.abort_callback = gw_abort;
	p.encoder_begin_callback = gw_encoder_begin;
	return whisper_full(ctx, p, pcm, n);
}

GW_EXPORT("gw_lang") const char *gw_lang(whisper_context *ctx) { return whisper_lang_str(whisper_full_lang_id(ctx)); }

GW_EXPORT("gw_n_segments") int gw_n_segments(whisper_context *ctx) { return whisper_full_n_segments(ctx); }

GW_EXPORT("gw_segment_text")
const char *gw_segment_text(whisper_context *ctx, int i) { return whisper_full_get_segment_text(ctx, i); }

GW_EXPORT("gw_segment_t0") long long gw_segment_t0(whisper_context *ctx, int i) { return whisper_full_get_segment_t0(ctx, i); }

GW_EXPORT("gw_segment_t1") long long gw_segment_t1(whisper_context *ctx, int i) { return whisper_full_get_segment_t1(ctx, i); }

// ggml can load backends from shared libraries. The CPU backend is linked
// in, so these only report that nothing can be loaded.
void *dlopen(const char *, int) { return nullptr; }

void *dlsym(void *, const char *) { return nullptr; }

int dlclose(void *) { return 0; }

char *dlerror(void) { return const_cast<char *>("dynamic loading is not supported"); }
}
