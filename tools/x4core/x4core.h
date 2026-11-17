#ifndef X4CORE_H
#define X4CORE_H
#include <stddef.h>
#ifdef _WIN32
#define X4API __declspec(dllexport)
#else
#define X4API __attribute__((visibility("default")))
#endif
void x4_fail(const char* msg);
X4API int x4_start(const unsigned char* disc, size_t size, const char* env);
X4API int x4_frame(unsigned buttons);
X4API const unsigned int* x4_prims(int* n);
X4API const unsigned short* x4_vram(int* dirty);
X4API const char* x4_log(void);
X4API void x4_log_clear(void);
X4API int x4_xa_need(void);
X4API void x4_xa_feed(const unsigned char* sec, int len);
X4API const short* x4_audio(int frames);
X4API void x4_card_set(int port, const unsigned char* data, int len);
X4API const unsigned char* x4_card_get(int port, int* dirty);
X4API int x4_movie_request(void);
X4API void x4_movie_done(void);
X4API long long x4_mem(unsigned addr, long long value, int size);
#ifdef RECOMP
const unsigned char* x4_state_save(size_t* n);
int x4_state_load(const unsigned char* d, size_t n);
const unsigned char* recomp_screen(int* w, int* h);
int recomp_audio_available(void);
void recomp_hide_cluts(const unsigned short* c, int n);
int recomp_hidden_hits(short box[4]);
int recomp_hidden_boxes(int* out, int max);
int recomp_set_parts(int on, int legs, int arms, int body, int helmet, int giga, int high, int mods);
#endif
#endif
