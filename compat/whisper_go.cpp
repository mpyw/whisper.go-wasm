// The functions github.com/mpyw/whisper.go calls. ABI.md lists them.
// Pointers are offsets into the module's linear memory, and the host
// allocates them with gw_malloc.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "whisper.h"

#define GW_EXPORT(name) __attribute__((export_name(name)))

// gw_aborted reports whether the Go caller's context is done. ggml asks
// between the operations of a graph, so a canceled run stops within one.
__attribute__((import_module("env"), import_name("gw_aborted"))) int gw_aborted(void);

static bool gw_abort(void *) { return gw_aborted() != 0; }

static bool gw_encoder_begin(whisper_context *, whisper_state *, void *) { return gw_aborted() == 0; }

// gw_room reports whether bytes more of memory can be allocated now. With
// -fno-exceptions, whisper.cpp aborts when an allocation fails, which
// traps: so the callers check first, and fail instead.
//
// The pointer is volatile: clang may drop a malloc whose memory is never
// used, and take it to have succeeded.
static bool gw_room(uint64_t bytes) {
	if (bytes > SIZE_MAX) {
		return false;
	}
	void *volatile p = malloc((size_t) bytes);
	const bool ok = p != nullptr;
	free(p);
	return ok;
}

// GW_MAX_THREADS bounds the threads of a run. Each takes an 8 MiB stack,
// the module's STACK_SIZE, from memory that never shrinks.
#define GW_MAX_THREADS 32
#define GW_STACK (8u << 20)

extern "C" {

GW_EXPORT("gw_malloc") void *gw_malloc(size_t n) { return malloc(n); }

GW_EXPORT("gw_free") void gw_free(void *p) { free(p); }

GW_EXPORT("gw_init")
whisper_context *gw_init(void *model, size_t size) {
	whisper_context_params cp = whisper_context_default_params();
	cp.use_gpu = false;
	// Flash attention runs in the module, as wasm2go translated it. Without
	// it, attention is matrix products, whose dot products run on the host.
	cp.flash_attn = false;
	// The tensors take about the model's size, and whisper.cpp's vectors
	// some hundred MB. The rest of the state comes from ggml, which returns
	// NULL rather than trap when there is no room, and so does gw_init then.
	if (!gw_room((uint64_t) size + (256u << 20))) {
		fprintf(stderr, "gw_init: no room in the module's memory for a model of %zu bytes\n", size);
		return nullptr;
	}
	return whisper_init_from_buffer_with_params(model, size, cp);
}

GW_EXPORT("gw_free_ctx") void gw_free_ctx(whisper_context *ctx) { whisper_free(ctx); }

// gw_full transcribes n samples of 16 kHz mono audio. An empty language,
// or "auto", detects it, except with an English-only model: there,
// detection would cost one more pass of the encoder, and would read tokens
// that are not languages in its vocabulary. An unknown language
// returns GW_UNKNOWN_LANGUAGE: whisper_full would run with a malformed
// prompt, and gw_lang would return NULL. Audio that whisper.cpp has no
// room for returns GW_NO_ROOM. See gw_full_room.
#define GW_UNKNOWN_LANGUAGE (-100)
#define GW_NO_ROOM (-101)
// No samples return GW_NO_SAMPLES: whisper.cpp would decode the mel
// spectrogram of the last call.
#define GW_NO_SAMPLES (-102)

// gw_full_room is what whisper_full allocates at most for n samples. First
// it makes their mel spectrogram on its threads, which stays for the
// encoder; patches/0002 pads the samples in place. Then, on a fallback to
// sampling, it builds the decoders' KV cache 7 times as large: k and v,
// float16, for each layer and token. A cache still there from an earlier
// call is counted again: the check errs on the side of refusing.
static uint64_t gw_full_room(whisper_context *ctx, int n, int threads) {
	const uint64_t mel = 4 * (uint64_t) whisper_model_n_mels(ctx) * (((uint64_t) n + 480000) / 160 + 1);
	const uint64_t tokens = ((uint64_t) whisper_model_n_text_ctx(ctx) + 255) / 256 * 256;
	const uint64_t kv = 7 * 2 * 2 * (uint64_t) whisper_model_n_text_state(ctx) * whisper_model_n_text_layer(ctx) * tokens;
	const uint64_t stacks = (uint64_t) (threads - 1) * (GW_STACK + (64u << 10));
	return mel + kv + stacks + (8u << 20);
}

// GW_TOO_SHORT is the fewest samples whisper.cpp transcribes: a mel
// spectrogram of 10 frames, 100 ms. Below it, whisper_full returns no
// segments, but detects the language first. That costs a pass of the
// encoder, names a language heard in nothing, and fails below 41 samples.
#define GW_TOO_SHORT 1640

// gw_lang_given is the language gw_full was given, -1 when whisper.cpp
// detects it, or -2 when there was too little audio to detect from.
// whisper.cpp sets its own record of an explicit language only after it
// returns early for input under 100 ms, so gw_lang reads this one first. A
// module has one ctx, and runs one gw_full at a time.
static int gw_lang_given = -1;

GW_EXPORT("gw_full")
int gw_full(whisper_context *ctx, const float *pcm, int n, int threads, const char *language) {
	threads = threads < 1 ? 1 : threads > GW_MAX_THREADS ? GW_MAX_THREADS : threads;
	const bool detect = language[0] == '\0' || strcmp(language, "auto") == 0;
	if (!detect && whisper_lang_id(language) < 0) {
		return GW_UNKNOWN_LANGUAGE;
	}
	if (n <= 0) {
		return GW_NO_SAMPLES;
	}
	if (!gw_room(gw_full_room(ctx, n, threads))) {
		return GW_NO_ROOM;
	}
	whisper_full_params p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
	p.n_threads = threads;
	p.language = !detect ? language : whisper_is_multilingual(ctx) ? "auto" : "en";
	// An English-only model transcribes English, whatever it was given.
	gw_lang_given = !whisper_is_multilingual(ctx)          ? whisper_lang_id("en")
	                : strcmp(p.language, "auto") != 0 ? whisper_lang_id(p.language)
	                                                  : -1;
	if (gw_lang_given == -1 && n < GW_TOO_SHORT) {
		// Any language makes whisper_full clear the results and return.
		p.language = "en";
		gw_lang_given = -2;
	}
	p.print_progress = false;
	p.print_realtime = false;
	p.print_timestamps = false;
	p.abort_callback = gw_abort;
	p.encoder_begin_callback = gw_encoder_begin;
	return whisper_full(ctx, p, pcm, n);
}

GW_EXPORT("gw_lang")
const char *gw_lang(whisper_context *ctx) {
	if (gw_lang_given == -2) {
		return "";
	}
	const char *lang = whisper_lang_str(gw_lang_given >= 0 ? gw_lang_given : whisper_full_lang_id(ctx));
	return lang != nullptr ? lang : "";
}

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
