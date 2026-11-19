#include <dlfcn.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct retro_game_info { const char *path; const void *data; size_t size; const char *meta; };
struct retro_system_timing { double fps; double sample_rate; };
struct retro_game_geometry { unsigned base_width, base_height, max_width, max_height; float aspect_ratio; };
struct retro_system_av_info { struct retro_game_geometry geometry; struct retro_system_timing timing; };
struct retro_log_callback { void (*log)(int level, const char *fmt, ...); };

static FILE *wav;
static long samples;
static long frame;
static int verbose;
static int peak;
static const void *last_video;
static unsigned last_w, last_h;
static size_t last_pitch;
static int coin_at = 700, start_at = 800;

static void log_cb(int level, const char *fmt, ...) {
    if (!verbose) return;
    va_list ap; va_start(ap, fmt); vfprintf(stderr, fmt, ap); va_end(ap);
}
static bool environment(unsigned cmd, void *data) {
    cmd &= 0xffff;
    if (cmd == 9 || cmd == 31) { *(const char **)data = "."; return true; }
    if (cmd == 10) return true;
    if (cmd == 27) { ((struct retro_log_callback *)data)->log = log_cb; return true; }
    return false;
}
static void video(const void *data, unsigned w, unsigned h, size_t pitch) {
    if (data) { last_video = data; last_w = w; last_h = h; last_pitch = pitch; }
}
static void input_poll(void) {}
static int16_t input_state(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (port != 0 || device != 1) return 0;
    if (id == 1 && frame >= coin_at && frame < coin_at + 8) return 1;
    if (id == 3 && frame >= start_at && frame < start_at + 8) return 1;
    if (id == 0 && frame > start_at + 400 && (frame / 20) % 2) return 1;
    if (id == 7 && frame > start_at + 400) return 1;
    return 0;
}
static void audio_sample(int16_t l, int16_t r) {
    int16_t s[2] = { l, r }; fwrite(s, 2, 2, wav); samples++;
    if (abs(l) > peak) peak = abs(l);
}
static size_t audio_batch(const int16_t *data, size_t frames) {
    fwrite(data, 4, frames, wav); samples += frames;
    for (size_t i = 0; i < frames * 2; i++) if (abs(data[i]) > peak) peak = abs(data[i]);
    return frames;
}
static void put32(FILE *f, uint32_t v) { fwrite(&v, 4, 1, f); }
static void put16(FILE *f, uint16_t v) { fwrite(&v, 2, 1, f); }

int main(int argc, char **argv) {
    if (argc < 5) { fprintf(stderr, "usage: run_core core.dylib rom frames out.wav [out.ppm] [coin_frame start_frame]\n"); return 2; }
    long frames = atol(argv[3]);
    if (argc > 7) { coin_at = atoi(argv[6]); start_at = atoi(argv[7]); }
    verbose = getenv("CORE_LOG") != NULL;
    void *core = dlopen(argv[1], RTLD_NOW);
    if (!core) { fprintf(stderr, "%s\n", dlerror()); return 1; }
#define SYM(type, name) __typeof__(type) name = (__typeof__(type))dlsym(core, #name)
    SYM(void (*)(bool (*)(unsigned, void *)), retro_set_environment);
    SYM(void (*)(void (*)(const void *, unsigned, unsigned, size_t)), retro_set_video_refresh);
    SYM(void (*)(void (*)(int16_t, int16_t)), retro_set_audio_sample);
    SYM(void (*)(size_t (*)(const int16_t *, size_t)), retro_set_audio_sample_batch);
    SYM(void (*)(void (*)(void)), retro_set_input_poll);
    SYM(void (*)(int16_t (*)(unsigned, unsigned, unsigned, unsigned)), retro_set_input_state);
    SYM(void (*)(void), retro_init);
    SYM(bool (*)(const struct retro_game_info *), retro_load_game);
    SYM(void (*)(struct retro_system_av_info *), retro_get_system_av_info);
    SYM(void (*)(void), retro_run);
    retro_set_environment(environment);
    retro_set_video_refresh(video);
    retro_set_audio_sample(audio_sample);
    retro_set_audio_sample_batch(audio_batch);
    retro_set_input_poll(input_poll);
    retro_set_input_state(input_state);
    retro_init();
    FILE *f = fopen(argv[2], "rb");
    if (!f) { perror(argv[2]); return 1; }
    fseek(f, 0, SEEK_END); long size = ftell(f); fseek(f, 0, SEEK_SET);
    void *rom = malloc(size); fread(rom, 1, size, f); fclose(f);
    struct retro_game_info info = { argv[2], rom, (size_t)size, NULL };
    if (!retro_load_game(&info)) { fprintf(stderr, "core refused the ROM\n"); return 1; }
    struct retro_system_av_info av; retro_get_system_av_info(&av);
    wav = fopen(argv[4], "wb");
    for (int i = 0; i < 44; i++) fputc(0, wav);
    for (frame = 0; frame < frames; frame++) {
        retro_run();
        if (frame % 300 == 299) { printf("frame %5ld  peak %5d\n", frame + 1, peak); peak = 0; }
    }
    uint32_t rate = (uint32_t)(av.timing.sample_rate + 0.5);
    fseek(wav, 0, SEEK_SET);
    fwrite("RIFF", 1, 4, wav); put32(wav, 36 + samples * 4); fwrite("WAVEfmt ", 1, 8, wav);
    put32(wav, 16); put16(wav, 1); put16(wav, 2); put32(wav, rate); put32(wav, rate * 4); put16(wav, 4); put16(wav, 16);
    fwrite("data", 1, 4, wav); put32(wav, samples * 4);
    fclose(wav);
    printf("%.2f frames a second, %u Hz, %ld samples\n", av.timing.fps, rate, samples);
    if (argc > 5 && last_video) {
        FILE *p = fopen(argv[5], "wb");
        fprintf(p, "P6 %u %u 255\n", last_w, last_h);
        for (unsigned y = 0; y < last_h; y++) {
            const uint16_t *row = (const uint16_t *)((const uint8_t *)last_video + y * last_pitch);
            for (unsigned x = 0; x < last_w; x++) {
                uint16_t c = row[x];
                fputc((c >> 11) << 3, p); fputc(((c >> 5) & 63) << 2, p); fputc((c & 31) << 3, p);
            }
        }
        fclose(p);
    }
    return 0;
}
