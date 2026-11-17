// Ponte com o Godot (GDExtension em C puro): classe X4Core só com métodos estáticos.
//   X4Core.start(disco: PackedByteArray, ambiente: String) -> int
//   X4Core.frame(botoes: int) -> int
//   X4Core.prims() -> PackedInt32Array      ([n, palavras...] por primitiva)
//   X4Core.vram() -> PackedByteArray        (vazio se não mudou desde a última vez)
//   X4Core.log() -> String
#include "gdext/gdextension_interface.h"
#include "x4core.h"
#ifndef GDEXT_CLASS
#define GDEXT_CLASS "X4Core"
#endif
#ifndef GDEXT_ENTRY
#define GDEXT_ENTRY x4core_init
#endif
#include <string.h>

typedef struct { unsigned char b[8]; } SName;
typedef struct { unsigned char b[8]; } GStr;
typedef struct { unsigned char b[16]; } GPacked;

static GDExtensionInterfaceGetProcAddress gpa;
static GDExtensionClassLibraryPtr lib;
static GDExtensionInterfaceStringNameNewWithLatin1Chars sn_new;
static GDExtensionInterfaceStringNewWithUtf8Chars str_new;
static GDExtensionInterfaceVariantGetPtrConstructor get_ctor;
static GDExtensionInterfaceVariantGetPtrDestructor get_dtor;
static GDExtensionInterfaceVariantGetPtrBuiltinMethod get_bmethod;
static GDExtensionInterfaceGetVariantFromTypeConstructor get_from_type;
static GDExtensionInterfaceGetVariantToTypeConstructor get_to_type;
static GDExtensionInterfacePackedByteArrayOperatorIndex pba_index;
static GDExtensionInterfacePackedByteArrayOperatorIndexConst pba_index_c;
static GDExtensionInterfacePackedInt32ArrayOperatorIndex pia_index;
static GDExtensionInterfacePackedVector2ArrayOperatorIndex pv2_index;
static GDExtensionInterfaceMemAlloc mem_alloc;
static GDExtensionInterfaceVariantDestroy var_destroy;

static GDExtensionVariantFromTypeConstructorFunc int_to_var, pba_to_var, pia_to_var, str_to_var, pv2_to_var;
static GDExtensionTypeFromVariantConstructorFunc var_to_int, var_to_pba, var_to_str;
static GDExtensionPtrConstructor pba_ctor, pia_ctor, pv2_ctor;
static GDExtensionPtrDestructor pba_dtor, pia_dtor, str_dtor, pv2_dtor;
static GDExtensionPtrBuiltInMethod pba_size, pba_resize, pia_resize, str_to_utf8, pv2_resize;

static SName sname(const char* s)
{
    SName n;
    memset(&n, 0, sizeof(n));
    sn_new(&n, s, 1);
    return n;
}

// ------------------------------------------------------------------ métodos
static unsigned char* disc_copy;
static long long disc_len;

static long long m_start(GDExtensionConstVariantPtr a0, GDExtensionConstVariantPtr a1)
{
    GPacked arr; GPacked env8; GStr env;
    var_to_pba(&arr, (GDExtensionVariantPtr)a0);
    long long n = 0;
    pba_size(&arr, 0, &n, 0);
    if (n > 0) {
        disc_copy = mem_alloc((size_t)n);
        memcpy(disc_copy, pba_index_c(&arr, 0), (size_t)n);
        disc_len = n;
    }
    pba_dtor(&arr);
    // ambiente: String -> utf8
    char envc[2048];
    envc[0] = 0;
    var_to_str(&env, (GDExtensionVariantPtr)a1);
    memset(&env8, 0, sizeof(env8));
    str_to_utf8(&env, 0, &env8, 0);
    long long en = 0;
    pba_size(&env8, 0, &en, 0);
    if (en > 0 && en < (long long)sizeof(envc)) {
        memcpy(envc, pba_index_c(&env8, 0), (size_t)en);
        envc[en] = 0;
    }
    pba_dtor(&env8);
    str_dtor(&env);
    return x4_start(disc_copy, (size_t)disc_len, envc);
}

static void ret_int(GDExtensionVariantPtr r, long long v)
{
    var_destroy(r);
    int_to_var(r, &v);
}

static void call_start(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e)
{
    (void)ud; (void)in;
    if (n < 2) { e->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; e->expected = 2; return; }
    e->error = GDEXTENSION_CALL_OK;
    ret_int(r, m_start(a[0], a[1]));
}
static void ptr_start(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r)
{
    (void)ud; (void)in;
    ret_int(r, m_start(a[0], a[1]));
}

static long long m_frame(GDExtensionConstVariantPtr a0)
{
    long long b = 0;
    var_to_int(&b, (GDExtensionVariantPtr)a0);
    return x4_frame((unsigned)b);
}
static void call_frame(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e)
{
    (void)ud; (void)in;
    if (n < 1) { e->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; e->expected = 1; return; }
    e->error = GDEXTENSION_CALL_OK;
    ret_int(r, m_frame(a[0]));
}
static void ptr_frame(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r)
{
    (void)ud; (void)in;
    ret_int(r, m_frame(a[0]));
}

static void m_prims(GDExtensionVariantPtr r)
{
    int n = 0;
    const unsigned int* p = x4_prims(&n);
    GPacked arr;
    pia_ctor(&arr, 0);
    long long len = n;
    const GDExtensionConstTypePtr args[1] = { &len };
    long long rr = 0;
    pia_resize(&arr, args, &rr, 1);
    if (n > 0) memcpy(pia_index(&arr, 0), p, (size_t)n * 4);
    var_destroy(r);
    pia_to_var(r, &arr);
    pia_dtor(&arr);
}
static void m_vram(GDExtensionVariantPtr r)
{
    int dirty = 0;
    const unsigned short* v = x4_vram(&dirty);
    GPacked arr;
    pba_ctor(&arr, 0);
    if (dirty) {
        long long len = 1024 * 512 * 2;
        const GDExtensionConstTypePtr args[1] = { &len };
        long long rr = 0;
        pba_resize(&arr, args, &rr, 1);
        memcpy(pba_index(&arr, 0), v, (size_t)len);
    }
    var_destroy(r);
    pba_to_var(r, &arr);
    pba_dtor(&arr);
}
static void m_log(GDExtensionVariantPtr r)
{
    GStr s;
    memset(&s, 0, sizeof(s));
    str_new(&s, x4_log());
    x4_log_clear();
    var_destroy(r);
    str_to_var(r, &s);
    str_dtor(&s);
}
#define NOARG(name, fn) \
    static void call_##name(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e) \
    { (void)ud; (void)in; (void)a; (void)n; e->error = GDEXTENSION_CALL_OK; fn(r); } \
    static void ptr_##name(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r) \
    { (void)ud; (void)in; (void)a; fn(r); }
// som
static long long m_xa_need(void) { return x4_xa_need(); }
static void m_xa_feed(GDExtensionConstVariantPtr a0)
{
    GPacked arr;
    var_to_pba(&arr, (GDExtensionVariantPtr)a0);
    long long n = 0;
    pba_size(&arr, 0, &n, 0);
    if (n > 0) x4_xa_feed(pba_index_c(&arr, 0), (int)n);
    pba_dtor(&arr);
}
static void m_audio(GDExtensionConstVariantPtr a0, GDExtensionVariantPtr r)
{
    long long frames = 0;
    var_to_int(&frames, (GDExtensionVariantPtr)a0);
    if (frames < 0) frames = 0;
    if (frames > 4096) frames = 4096;
    const short* s = x4_audio((int)frames);
    GPacked arr;
    pv2_ctor(&arr, 0);
    const GDExtensionConstTypePtr args[1] = { &frames };
    long long rr = 0;
    pv2_resize(&arr, args, &rr, 1);
    if (frames > 0) {
        float* f = (float*)pv2_index(&arr, 0);
        for (long long i = 0; i < frames * 2; i++) f[i] = s[i] * (1.0f / 32768.0f);
    }
    var_destroy(r);
    pv2_to_var(r, &arr);
    pv2_dtor(&arr);
}
static void call_xa_need(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e)
{ (void)ud; (void)in; (void)a; (void)n; e->error = GDEXTENSION_CALL_OK; ret_int(r, m_xa_need()); }
static void ptr_xa_need(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r)
{ (void)ud; (void)in; (void)a; ret_int(r, m_xa_need()); }
static void call_xa_feed(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e)
{ (void)ud; (void)in; if (n < 1) { e->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; e->expected = 1; return; } e->error = GDEXTENSION_CALL_OK; m_xa_feed(a[0]); ret_int(r, 0); }
static void ptr_xa_feed(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r)
{ (void)ud; (void)in; m_xa_feed(a[0]); ret_int(r, 0); }
static void call_audio(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e)
{ (void)ud; (void)in; if (n < 1) { e->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; e->expected = 1; return; } e->error = GDEXTENSION_CALL_OK; m_audio(a[0], r); }
static void ptr_audio(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r)
{ (void)ud; (void)in; m_audio(a[0], r); }

// cartão de memória
static void m_card_set(GDExtensionConstVariantPtr a0, GDExtensionConstVariantPtr a1)
{
    long long port = 0;
    var_to_int(&port, (GDExtensionVariantPtr)a0);
    GPacked arr;
    var_to_pba(&arr, (GDExtensionVariantPtr)a1);
    long long n = 0;
    pba_size(&arr, 0, &n, 0);
    if (n > 0) x4_card_set((int)port, pba_index_c(&arr, 0), (int)n);
    pba_dtor(&arr);
}
static void m_card_get(GDExtensionConstVariantPtr a0, GDExtensionVariantPtr r)
{
    long long port = 0;
    var_to_int(&port, (GDExtensionVariantPtr)a0);
    int dirty = 0;
    const unsigned char* d = x4_card_get((int)port, &dirty);
    GPacked arr;
    pba_ctor(&arr, 0);
    if (dirty) {
        long long len = 0x20000;
        const GDExtensionConstTypePtr args[1] = { &len };
        long long rr = 0;
        pba_resize(&arr, args, &rr, 1);
        memcpy(pba_index(&arr, 0), d, (size_t)len);
    }
    var_destroy(r);
    pba_to_var(r, &arr);
    pba_dtor(&arr);
}
static void call_card_set(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e)
{ (void)ud; (void)in; if (n < 2) { e->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; e->expected = 2; return; } e->error = GDEXTENSION_CALL_OK; m_card_set(a[0], a[1]); ret_int(r, 0); }
static void ptr_card_set(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r)
{ (void)ud; (void)in; m_card_set(a[0], a[1]); ret_int(r, 0); }
static void call_card_get(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e)
{ (void)ud; (void)in; if (n < 1) { e->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; e->expected = 1; return; } e->error = GDEXTENSION_CALL_OK; m_card_get(a[0], r); }
static void ptr_card_get(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r)
{ (void)ud; (void)in; m_card_get(a[0], r); }

static void call_movie_req(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e)
{ (void)ud; (void)in; (void)a; (void)n; e->error = GDEXTENSION_CALL_OK; ret_int(r, x4_movie_request()); }
static void ptr_movie_req(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r)
{ (void)ud; (void)in; (void)a; ret_int(r, x4_movie_request()); }
static void call_movie_done(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e)
{ (void)ud; (void)in; (void)a; (void)n; e->error = GDEXTENSION_CALL_OK; x4_movie_done(); ret_int(r, 0); }
static void ptr_movie_done(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r)
{ (void)ud; (void)in; (void)a; x4_movie_done(); ret_int(r, 0); }

// mem(endereço, valor, tamanho): tamanho 1/2/4 lê; -1/-2/-4 escreve o valor. Devolve o valor lido.
static long long m_mem(GDExtensionConstVariantPtr a0, GDExtensionConstVariantPtr a1, GDExtensionConstVariantPtr a2)
{
    GDExtensionInt ad = 0, v = 0, sz = 0;
    var_to_int(&ad, (GDExtensionVariantPtr)a0); var_to_int(&v, (GDExtensionVariantPtr)a1); var_to_int(&sz, (GDExtensionVariantPtr)a2);
    return x4_mem((unsigned)ad, (long long)v, (int)sz);
}
static void call_mem(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e)
{ (void)ud; (void)in; if (n < 3) { e->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; e->expected = 3; return; } e->error = GDEXTENSION_CALL_OK; ret_int(r, m_mem(a[0], a[1], a[2])); }
static void ptr_mem(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r)
{ (void)ud; (void)in; ret_int(r, m_mem(a[0], a[1], a[2])); }

// ---- estado completo do núcleo (só no núcleo de PS1): todas as variáveis entre marca_inicio.o e marca_fim.o ----
extern char x4_data_ini[], x4_data_fim[], x4_bss_ini[], x4_bss_fim[];
#ifdef PSXCORE
extern void psx_after_state_load(void);
#endif
// O estado começa com 16 bytes: endereço onde as variáveis estavam (o .so/.dll pode carregar em outro lugar
// na próxima vez; ponteiros guardados dentro do estado são corrigidos pela diferença).
static void m_state_save(GDExtensionVariantPtr r)
{
    GPacked arr; pba_ctor(&arr, 0);
#ifdef PSXCORE
    long long dn = x4_data_fim - x4_data_ini, bn = x4_bss_fim - x4_bss_ini, len = 16 + dn + bn;
    const GDExtensionConstTypePtr args[1] = { &len }; long long rr = 0;
    pba_resize(&arr, args, &rr, 1);
    unsigned char* o = pba_index(&arr, 0);
    unsigned long long base = (unsigned long long)(unsigned long long)(uintptr_t)x4_data_ini, bss = (unsigned long long)(uintptr_t)x4_bss_ini;
    memcpy(o, &base, 8); memcpy(o + 8, &bss, 8);
    memcpy(o + 16, x4_data_ini, (size_t)dn); memcpy(o + 16 + dn, x4_bss_ini, (size_t)bn);
#elif defined(RECOMP)
    size_t sn = 0; const unsigned char* sd = x4_state_save(&sn);
    if (sd && sn) {
        long long len = (long long)sn;
        const GDExtensionConstTypePtr args[1] = { &len }; long long rr = 0;
        pba_resize(&arr, args, &rr, 1);
        memcpy(pba_index(&arr, 0), sd, sn);
    }
#endif
    var_destroy(r); pba_to_var(r, &arr); pba_dtor(&arr);
}
static long long m_state_load(GDExtensionConstVariantPtr a0)
{
#ifdef PSXCORE
    GPacked arr; var_to_pba(&arr, (GDExtensionVariantPtr)a0);
    long long n = 0; pba_size(&arr, 0, &n, 0);
    long long dn = x4_data_fim - x4_data_ini, bn = x4_bss_fim - x4_bss_ini;
    if (n != 16 + dn + bn) { pba_dtor(&arr); return -1; }
    const unsigned char* d = pba_index_c(&arr, 0);
    unsigned long long old_base, old_bss;
    memcpy(&old_base, d, 8); memcpy(&old_bss, d + 8, 8);
    unsigned long long new_base = (unsigned long long)(uintptr_t)x4_data_ini;
    if ((long long)(new_base - old_base) != (long long)((unsigned long long)(uintptr_t)x4_bss_ini - old_bss)) { pba_dtor(&arr); return -1; }
    memcpy(x4_data_ini, d + 16, (size_t)dn); memcpy(x4_bss_ini, d + 16 + dn, (size_t)bn);
    pba_dtor(&arr);
    long long delta = (long long)(new_base - old_base);
    if (delta != 0) {
        // ponteiros para dentro do próprio módulo (código perto dos dados, dados e bss)
        unsigned long long lo = old_base - 0x400000, hi = old_bss + (unsigned long long)bn + 0x1000;
        unsigned char* areas[2] = { (unsigned char*)x4_data_ini, (unsigned char*)x4_bss_ini };
        long long sizes[2] = { dn, bn };
        for (int k = 0; k < 2; k++) {
            unsigned char* p0 = areas[k];
            unsigned char* p = (unsigned char*)(((uintptr_t)p0 + 7) & ~(uintptr_t)7);
            for (; p + 8 <= p0 + sizes[k]; p += 8) {
                unsigned long long w; memcpy(&w, p, 8);
                if (w >= lo && w < hi) { w += (unsigned long long)delta; memcpy(p, &w, 8); }
            }
        }
    }
    psx_after_state_load();
    return 0;
#elif defined(RECOMP)
    GPacked arr; var_to_pba(&arr, (GDExtensionVariantPtr)a0);
    long long n = 0; pba_size(&arr, 0, &n, 0);
    int r = n > 0 ? x4_state_load(pba_index_c(&arr, 0), (size_t)n) : -1;
    pba_dtor(&arr);
    return r;
#else
    (void)a0; return -1;
#endif
}
#ifdef RECOMP
// screen(): imagem da tela do PS1 em RGB8, com 4 bytes na frente (largura e altura, 16 bits cada)
static void m_screen(GDExtensionVariantPtr r)
{
    GPacked arr; pba_ctor(&arr, 0);
    int w = 0, h = 0; const unsigned char* px = recomp_screen(&w, &h);
    if (px && w > 0 && h > 0) {
        long long len = 4 + (long long)w * h * 3;
        const GDExtensionConstTypePtr args[1] = { &len }; long long rr = 0;
        pba_resize(&arr, args, &rr, 1);
        unsigned char* o = pba_index(&arr, 0);
        o[0] = (unsigned char)w; o[1] = (unsigned char)(w >> 8); o[2] = (unsigned char)h; o[3] = (unsigned char)(h >> 8);
        memcpy(o + 4, px, (size_t)w * h * 3);
    }
    var_destroy(r); pba_to_var(r, &arr); pba_dtor(&arr);
}
static void call_screen(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e)
{ (void)ud; (void)in; (void)a; (void)n; e->error = GDEXTENSION_CALL_OK; m_screen(r); }
static void ptr_screen(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r)
{ (void)ud; (void)in; (void)a; m_screen(r); }
// hide_cluts(PackedByteArray com u16): paletas que o GPU da recompilação não desenha
static void call_hide_cluts(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e)
{
    (void)ud; (void)in;
    if (n < 1) { e->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; e->expected = 1; return; }
    e->error = GDEXTENSION_CALL_OK;
    GPacked arr; var_to_pba(&arr, (GDExtensionVariantPtr)a[0]);
    long long sz = 0; pba_size(&arr, 0, &sz, 0);
    unsigned short c[64]; int k = 0;
    const unsigned char* d = sz > 0 ? pba_index_c(&arr, 0) : 0;
    for (long long i = 0; i + 1 < sz && k < 64; i += 2) c[k++] = (unsigned short)(d[i] | (d[i + 1] << 8));
    pba_dtor(&arr);
    recomp_hide_cluts(c, k);
    ret_int(r, k);
}
static void ptr_hide_cluts(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r)
{ (void)ud; (void)in; (void)a; ret_int(r, 0); }
// set_parts(PackedByteArray [ligado, pernas, braço, corpo, capacete, giga, pulo alto, mods]): armadura de cada peça (X5/X6)
static void call_set_parts(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e)
{
    (void)ud; (void)in;
    if (n < 1) { e->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; e->expected = 1; return; }
    e->error = GDEXTENSION_CALL_OK;
    GPacked arr; var_to_pba(&arr, (GDExtensionVariantPtr)a[0]);
    long long sz = 0; pba_size(&arr, 0, &sz, 0);
    int v[8] = {0, 0, 0, 0, 0, 0, 0, 0};
    const unsigned char* d = sz > 0 ? pba_index_c(&arr, 0) : 0;
    for (long long i = 0; i < sz && i < 8; i++) v[i] = d[i];
    if (sz < 6) v[5] = v[2];   /* sem o Giga: segue o braço */
    if (sz < 7) v[6] = v[1];   /* sem o pulo alto: segue as pernas */
    pba_dtor(&arr);
    ret_int(r, recomp_set_parts(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]));
}
static void ptr_set_parts(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r)
{ (void)ud; (void)in; (void)a; ret_int(r, 0); }
// hidden_hits(): quantos sprites escondidos o jogo desenhou no último quadro (0 = o X piscou/sumiu)
static void call_hidden_hits(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e)
{ (void)ud; (void)in; (void)a; (void)n; e->error = GDEXTENSION_CALL_OK; short b[4]; ret_int(r, recomp_hidden_hits(b)); }
static void ptr_hidden_hits(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r)
{ (void)ud; (void)in; (void)a; short b[4]; ret_int(r, recomp_hidden_hits(b)); }
// hidden_boxes(): PackedByteArray com int32 [n, x0, y0, x1, y1] por paleta escondida (último quadro desenhado)
static void m_hidden_boxes(GDExtensionVariantPtr r)
{
    int b[64 * 5]; int n = recomp_hidden_boxes(b, 64);
    GPacked arr; pba_ctor(&arr, 0);
    long long len = (long long)n * 5 * 4;
    if (len > 0) {
        const GDExtensionConstTypePtr args[1] = { &len }; long long rr = 0;
        pba_resize(&arr, args, &rr, 1);
        memcpy(pba_index(&arr, 0), b, (size_t)len);
    }
    var_destroy(r); pba_to_var(r, &arr); pba_dtor(&arr);
}
static void call_hidden_boxes(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e)
{ (void)ud; (void)in; (void)a; (void)n; e->error = GDEXTENSION_CALL_OK; m_hidden_boxes(r); }
static void ptr_hidden_boxes(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r)
{ (void)ud; (void)in; (void)a; m_hidden_boxes(r); }
static void call_audio_avail(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e)
{ (void)ud; (void)in; (void)a; (void)n; e->error = GDEXTENSION_CALL_OK; ret_int(r, recomp_audio_available()); }
static void ptr_audio_avail(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r)
{ (void)ud; (void)in; (void)a; ret_int(r, recomp_audio_available()); }
#endif
static void call_state_save(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e)
{ (void)ud; (void)in; (void)a; (void)n; e->error = GDEXTENSION_CALL_OK; m_state_save(r); }
static void ptr_state_save(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r)
{ (void)ud; (void)in; (void)a; m_state_save(r); }
static void call_state_load(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstVariantPtr* a, GDExtensionInt n, GDExtensionVariantPtr r, GDExtensionCallError* e)
{ (void)ud; (void)in; if (n < 1) { e->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; e->expected = 1; return; } e->error = GDEXTENSION_CALL_OK; ret_int(r, m_state_load(a[0])); }
static void ptr_state_load(void* ud, GDExtensionClassInstancePtr in, const GDExtensionConstTypePtr* a, GDExtensionTypePtr r)
{ (void)ud; (void)in; ret_int(r, m_state_load(a[0])); }

NOARG(prims, m_prims)
NOARG(vram, m_vram)
NOARG(log, m_log)

// ------------------------------------------------------------------ registro
static SName cls_name, empty_name;
static GStr empty_str;

static void add_method(const char* name, GDExtensionClassMethodCall c, GDExtensionClassMethodPtrCall p, int argc, const char** argn)
{
    static SName names[32];
    static int nn;
    SName mname = sname(name);
    GDExtensionPropertyInfo ret = { GDEXTENSION_VARIANT_TYPE_NIL, &empty_name, &empty_name, 0, &empty_str, 6 | 131072 };
    GDExtensionPropertyInfo args[4];
    GDExtensionClassMethodArgumentMetadata meta[4];
    for (int i = 0; i < argc; i++) {
        names[nn] = sname(argn[i]);
        GDExtensionPropertyInfo pi = { GDEXTENSION_VARIANT_TYPE_NIL, &names[nn], &empty_name, 0, &empty_str, 6 | 131072 };
        nn++;
        args[i] = pi;
        meta[i] = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
    }
    GDExtensionClassMethodInfo mi;
    memset(&mi, 0, sizeof(mi));
    mi.name = &mname;
    mi.call_func = c;
    mi.ptrcall_func = p;
    mi.method_flags = GDEXTENSION_METHOD_FLAGS_DEFAULT | GDEXTENSION_METHOD_FLAG_STATIC;
    mi.has_return_value = 1;
    mi.return_value_info = &ret;
    mi.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
    mi.argument_count = argc;
    mi.arguments_info = argc ? args : 0;
    mi.arguments_metadata = argc ? meta : 0;
    ((GDExtensionInterfaceClassdbRegisterExtensionClassMethod)gpa("classdb_register_extension_class_method"))(lib, &cls_name, &mi);
}

static void free_instance(void* ud, GDExtensionClassInstancePtr p) { (void)ud; (void)p; }

static void initialize(void* ud, GDExtensionInitializationLevel level)
{
    (void)ud;
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    sn_new = (void*)gpa("string_name_new_with_latin1_chars");
    str_new = (void*)gpa("string_new_with_utf8_chars");
    get_ctor = (void*)gpa("variant_get_ptr_constructor");
    get_dtor = (void*)gpa("variant_get_ptr_destructor");
    get_bmethod = (void*)gpa("variant_get_ptr_builtin_method");
    get_from_type = (void*)gpa("get_variant_from_type_constructor");
    get_to_type = (void*)gpa("get_variant_to_type_constructor");
    pba_index = (void*)gpa("packed_byte_array_operator_index");
    pba_index_c = (void*)gpa("packed_byte_array_operator_index_const");
    pia_index = (void*)gpa("packed_int32_array_operator_index");
    pv2_index = (void*)gpa("packed_vector2_array_operator_index");
    mem_alloc = (void*)gpa("mem_alloc");
    var_destroy = (void*)gpa("variant_destroy");

    int_to_var = get_from_type(GDEXTENSION_VARIANT_TYPE_INT);
    pba_to_var = get_from_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
    pia_to_var = get_from_type(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
    str_to_var = get_from_type(GDEXTENSION_VARIANT_TYPE_STRING);
    pv2_to_var = get_from_type(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY);
    pv2_ctor = get_ctor(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY, 0);
    pv2_dtor = get_dtor(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY);
    var_to_int = get_to_type(GDEXTENSION_VARIANT_TYPE_INT);
    var_to_pba = get_to_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
    var_to_str = get_to_type(GDEXTENSION_VARIANT_TYPE_STRING);
    pba_ctor = get_ctor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, 0);
    pia_ctor = get_ctor(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, 0);
    pba_dtor = get_dtor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
    pia_dtor = get_dtor(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
    str_dtor = get_dtor(GDEXTENSION_VARIANT_TYPE_STRING);
    SName n_size = sname("size"), n_resize = sname("resize"), n_utf8 = sname("to_utf8_buffer");
    pba_size = get_bmethod(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &n_size, 3173160232u);
    pba_resize = get_bmethod(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &n_resize, 848867239u);
    pia_resize = get_bmethod(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, &n_resize, 848867239u);
    pv2_resize = get_bmethod(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY, &n_resize, 848867239u);
    str_to_utf8 = get_bmethod(GDEXTENSION_VARIANT_TYPE_STRING, &n_utf8, 247621236u);

    cls_name = sname(GDEXT_CLASS);
    empty_name = sname("");
    memset(&empty_str, 0, sizeof(empty_str));
    str_new(&empty_str, "");
    SName parent = sname("Object");
    GDExtensionClassCreationInfo6 ci;
    memset(&ci, 0, sizeof(ci));
    ci.is_abstract = 1;
    ci.is_exposed = 1;
    ci.free_instance_func = free_instance;
    ((GDExtensionInterfaceClassdbRegisterExtensionClass6)gpa("classdb_register_extension_class6"))(lib, &cls_name, &parent, &ci);

    static const char* a_start[] = { "disco", "ambiente" };
    static const char* a_frame[] = { "botoes" };
    add_method("start", call_start, ptr_start, 2, a_start);
    add_method("frame", call_frame, ptr_frame, 1, a_frame);
    add_method("prims", call_prims, ptr_prims, 0, 0);
    add_method("vram", call_vram, ptr_vram, 0, 0);
    add_method("log", call_log, ptr_log, 0, 0);
    static const char* a_feed[] = { "setor" };
    static const char* a_audio[] = { "quadros" };
    add_method("xa_need", call_xa_need, ptr_xa_need, 0, 0);
    add_method("xa_feed", call_xa_feed, ptr_xa_feed, 1, a_feed);
    add_method("audio", call_audio, ptr_audio, 1, a_audio);
    static const char* a_cset[] = { "porta", "dados" };
    static const char* a_cget[] = { "porta" };
    add_method("card_set", call_card_set, ptr_card_set, 2, a_cset);
    add_method("card_get", call_card_get, ptr_card_get, 1, a_cget);
    add_method("movie_request", call_movie_req, ptr_movie_req, 0, 0);
    add_method("movie_done", call_movie_done, ptr_movie_done, 0, 0);
    static const char* a_mem[] = { "endereco", "valor", "tamanho" };
    add_method("mem", call_mem, ptr_mem, 3, a_mem);
    add_method("state_save", call_state_save, ptr_state_save, 0, 0);
    static const char* a_sload[] = { "estado" };
    add_method("state_load", call_state_load, ptr_state_load, 1, a_sload);
#ifdef RECOMP
    add_method("screen", call_screen, ptr_screen, 0, 0);
    add_method("audio_available", call_audio_avail, ptr_audio_avail, 0, 0);
    static const char* a_hide[] = { "paletas" };
    add_method("hide_cluts", call_hide_cluts, ptr_hide_cluts, 1, a_hide);
    add_method("hidden_hits", call_hidden_hits, ptr_hidden_hits, 0, 0);
    add_method("hidden_boxes", call_hidden_boxes, ptr_hidden_boxes, 0, 0);
    static const char* a_parts[] = { "pecas" };
    add_method("set_parts", call_set_parts, ptr_set_parts, 1, a_parts);
#endif
}
static void deinitialize(void* ud, GDExtensionInitializationLevel level) { (void)ud; (void)level; }

X4API GDExtensionBool GDEXT_ENTRY(GDExtensionInterfaceGetProcAddress p, GDExtensionClassLibraryPtr l, GDExtensionInitialization* r)
{
    gpa = p;
    lib = l;
    r->initialize = initialize;
    r->deinitialize = deinitialize;
    r->userdata = 0;
    r->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    return 1;
}

#if !defined(PSXCORE) && !defined(RECOMP)
// ---- reinício do jogo sem reabrir o programa ----
// As variáveis do jogo ficam entre marca_inicio.o e marca_fim.o (ordem do link). Este arquivo vem antes de
// tudo, então a cópia abaixo não é apagada. No 1º início guarda os dados iniciais; nos seguintes, restaura.
extern char x4_data_ini[], x4_data_fim[], x4_bss_ini[], x4_bss_fim[];
#define X4_BACKUP_MAX (8 << 20)
static unsigned char x4_backup[X4_BACKUP_MAX];
static long x4_backup_n = -1;
int x4_state_reset(void)
{
    long dn = x4_data_fim - x4_data_ini, bn = x4_bss_fim - x4_bss_ini;
    if (dn <= 0 || dn > X4_BACKUP_MAX || bn <= 0) return -1;
    if (x4_backup_n < 0) {   // primeiro início: guarda
        for (long i = 0; i < dn; i++) x4_backup[i] = (unsigned char)x4_data_ini[i];
        x4_backup_n = dn;
        return 0;
    }
    for (long i = 0; i < dn; i++) x4_data_ini[i] = (char)x4_backup[i];
    for (long i = 0; i < bn; i++) x4_bss_ini[i] = 0;
    return 1;
}
#endif
