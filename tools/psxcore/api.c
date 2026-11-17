// Ligação do núcleo de PS1 com o Godot: disco, quadros, som XA, mensagens.
// Exporta as mesmas funções que a x4core (x4_*), para reaproveitar a ponte gdext.c.
#include "psx.h"
#include <stdarg.h>

// ------------------------------------------------------------------ libc mínima
typedef u64 __attribute__((may_alias, aligned(1))) u64u;
__attribute__((no_builtin("memcpy"))) void* memcpy(void* d, const void* s, size_t n)
{
    u8* a = d; const u8* b = s;
    while (n >= 8) { *(u64u*)a = *(const u64u*)b; a += 8; b += 8; n -= 8; }
    while (n--) *a++ = *b++;
    return d;
}
__attribute__((no_builtin("memset"))) void* memset(void* d, int v, size_t n)
{
    u8* a = d; u64 w = (u8)v; w |= w << 8; w |= w << 16; w |= w << 32;
    while (n >= 8) { *(u64u*)a = w; a += 8; n -= 8; }
    while (n--) *a++ = (u8)v;
    return d;
}
void* memmove(void* d, const void* s, size_t n)
{
    u8* a = d; const u8* b = s;
    if (a < b) { while (n--) *a++ = *b++; } else { a += n; b += n; while (n--) *--a = *--b; }
    return d;
}
int memcmp(const void* x, const void* y, size_t n) { const u8 *a = x, *b = y; for (; n; n--, a++, b++) if (*a != *b) return *a - *b; return 0; }
size_t strlen(const char* s) { size_t n = 0; while (s[n]) n++; return n; }
#ifdef _WIN32
int _fltused = 0;
#endif

static char log_buf[32768];
static size_t log_len;
static void log_str(const char* s) { while (*s && log_len < sizeof(log_buf) - 1) log_buf[log_len++] = *s++; log_buf[log_len] = 0; }
static void log_num(unsigned long long v, int base)
{
    char t[24]; int i = 0;
    do { t[i++] = "0123456789abcdef"[v % base]; v /= base; } while (v && i < 23);
    char o[25]; int j = 0; while (i) o[j++] = t[--i]; o[j] = 0; log_str(o);
}
void psx_log(const char* fmt, ...)
{
    va_list ap; va_start(ap, fmt);
    for (const char* p = fmt; *p; p++) {
        if (*p != '%') { char c[2] = { *p, 0 }; log_str(c); continue; }
        p++;
        while (*p >= '0' && *p <= '9') p++;
        switch (*p) {
        case 's': log_str(va_arg(ap, const char*)); break;
        case 'd': { int v = va_arg(ap, int); if (v < 0) { log_str("-"); v = -v; } log_num((unsigned)v, 10); break; }
        case 'u': log_num(va_arg(ap, unsigned), 10); break;
        case 'x': log_num(va_arg(ap, unsigned), 16); break;
        default: break;
        }
    }
    va_end(ap);
}
void psyz_log(unsigned int level, const char* file, unsigned int line, const char* func, const char* fmt, ...) { (void)level; (void)file; (void)line; (void)func; (void)fmt; }
void Psyz_RcntAdd(int n) { (void)n; }

// ------------------------------------------------------------------ disco (arquivo .bin, setores de 2352 bytes)
int disc_sectors;
#ifdef _WIN32
typedef void* HANDLE;
__declspec(dllimport) HANDLE __stdcall CreateFileW(const unsigned short*, u32, u32, void*, u32, u32, HANDLE);
__declspec(dllimport) int __stdcall MultiByteToWideChar(u32, u32, const char*, int, unsigned short*, int);
__declspec(dllimport) int __stdcall ReadFile(HANDLE, void*, u32, u32*, void*);
__declspec(dllimport) int __stdcall SetFilePointerEx(HANDLE, s64, s64*, u32);
__declspec(dllimport) int __stdcall GetFileSizeEx(HANDLE, s64*);
static HANDLE disc_h;
static int disc_open(const char* path)
{
    // o caminho vem em UTF-8 (pastas com acento, ex.: "Área de Trabalho"): abre pela versão larga do Windows
    static unsigned short wpath[4096];
    if (MultiByteToWideChar(65001, 0, path, -1, wpath, 4096) <= 0) return -1;
    disc_h = CreateFileW(wpath, 0x80000000u, 1, 0, 3, 0x80, 0);
    if (disc_h == (HANDLE)(intptr_t)-1) { disc_h = 0; return -1; }
    s64 sz = 0; GetFileSizeEx(disc_h, &sz);
    disc_sectors = (int)(sz / 2352);
    return 0;
}
int disc_read_sector(int lba, u8* out)
{
    if (!disc_h || lba < 0 || lba >= disc_sectors) { memset(out, 0, 2352); return -1; }
    s64 p = 0; SetFilePointerEx(disc_h, (s64)lba * 2352, &p, 0);
    u32 got = 0; ReadFile(disc_h, out, 2352, &got, 0);
    return got == 2352 ? 0 : -1;
}
#else
int open(const char*, int, ...);
long pread(int, void*, unsigned long, long);
long lseek(int, long, int);
static int disc_fd = -1;
static int disc_open(const char* path)
{
    disc_fd = open(path, 0);
    if (disc_fd < 0) return -1;
    long sz = lseek(disc_fd, 0, 2);
    disc_sectors = (int)(sz / 2352);
    return 0;
}
int disc_read_sector(int lba, u8* out)
{
    if (disc_fd < 0 || lba < 0 || lba >= disc_sectors) { memset(out, 0, 2352); return -1; }
    return pread(disc_fd, out, 2352, (long)lba * 2352) == 2352 ? 0 : -1;
}
#endif

// ------------------------------------------------------------------ XA (música/voz do CD) -> entrada de CD da SPU
#define XA_RING 65536
static s16 xa_ring[XA_RING * 2];
static u32 xa_rd, xa_cnt;
static s32 xa_h[4];
static u32 xa_phase;
static s16 xa_cur[2], xa_prev[2];
int xa_active;
// fase inicial do reamostrador a cada ReadN/ReadS (16.16, em amostras de 37800 Hz); 0 no jogo.
// A captura muda isto (XA_FASE) para refazer músicas gravadas com outra fase (ex.: x6_selecao.ogg)
unsigned xa_fase_inicial;
void xa_reset_stream(void)
{
    xa_rd = xa_cnt = 0; xa_phase = xa_fase_inicial & 0xFFFF;
    xa_h[0] = xa_h[1] = xa_h[2] = xa_h[3] = 0;
    xa_cur[0] = xa_cur[1] = xa_prev[0] = xa_prev[1] = 0;
}
static s16 clamp16x(s32 v) { return v > 32767 ? 32767 : v < -32768 ? -32768 : (s16)v; }
static const int K0[4] = { 0, 60, 115, 98 }, K1[4] = { 0, 0, -52, -55 };
static void dec28(const u8* blk, int sub, int nib, s16* dst, int stride, s32* p1, s32* p2)
{
    u8 h = blk[4 + sub * 2 + nib];
    int sh = (h & 15) > 12 ? 9 : 12 - (h & 15);
    int f = (h >> 4) & 3;
    for (int j = 0; j < 28; j++) {
        int t = (blk[16 + sub + j * 4] >> (nib * 4)) & 15;
        if (t & 8) t -= 16;
        s32 v = (t << sh) + ((*p1 * K0[f] + *p2 * K1[f] + 32) / 64);
        dst[j * stride] = clamp16x(v);
        *p2 = *p1; *p1 = v;
    }
}
static void xa_push(s16 l, s16 r)
{
    if (xa_cnt >= XA_RING) return;
    u32 w = (xa_rd + xa_cnt) & (XA_RING - 1);
    xa_ring[w * 2] = l; xa_ring[w * 2 + 1] = r; xa_cnt++;
}
int xa_feed_sector(const u8* sec)
{
    u8 ci = sec[0x13];
    const u8* u = sec + 0x18;
    static s16 tmp[4032 * 2];
    int n = 0;
    if ((ci & 3) == 1) {
        for (int i = 0; i < 18; i++)
            for (int s = 0; s < 4; s++) {
                dec28(u + i * 128, s, 0, &tmp[n * 2], 2, &xa_h[0], &xa_h[1]);
                dec28(u + i * 128, s, 1, &tmp[n * 2 + 1], 2, &xa_h[2], &xa_h[3]);
                n += 28;
            }
    } else {
        static s16 mono[4032];
        for (int i = 0; i < 18; i++)
            for (int s = 0; s < 4; s++) {
                dec28(u + i * 128, s, 0, &mono[n], 1, &xa_h[0], &xa_h[1]); n += 28;
                dec28(u + i * 128, s, 1, &mono[n], 1, &xa_h[0], &xa_h[1]); n += 28;
            }
        for (int i = 0; i < n; i++) { tmp[i * 2] = mono[i]; tmp[i * 2 + 1] = mono[i]; }
    }
    int half = (ci & 4) != 0;
    for (int i = 0; i < n; i++) {
        xa_push(tmp[i * 2], tmp[i * 2 + 1]);
        if (half) xa_push(tmp[i * 2], tmp[i * 2 + 1]);
    }
    xa_active = 1;
    return n;
}
size_t Psyz_CdPullSamples(short* out, size_t frames)
{
    size_t w = 0;
    const u32 step = (37800u << 16) / 44100u;
    while (w < frames) {
        while (xa_phase >= 0x10000) {
            if (xa_cnt == 0) return w;
            xa_prev[0] = xa_cur[0]; xa_prev[1] = xa_cur[1];
            xa_cur[0] = xa_ring[xa_rd * 2]; xa_cur[1] = xa_ring[xa_rd * 2 + 1];
            xa_rd = (xa_rd + 1) & (XA_RING - 1); xa_cnt--;
            xa_phase -= 0x10000;
        }
        int f = (int)(xa_phase & 0xFFFF);
        out[w * 2] = (short)(xa_prev[0] + (((xa_cur[0] - xa_prev[0]) * f) >> 16));
        out[w * 2 + 1] = (short)(xa_prev[1] + (((xa_cur[1] - xa_prev[1]) * f) >> 16));
        xa_phase += step;
        w++;
    }
    return w;
}

// ------------------------------------------------------------------ BIOS: chamadas de texto (para o registro)
// ------------------------------------------------------------------ partida rápida: quando a BIOS chega no shell, carrega o EXE do CD
static int iso_find(int dir_lba, int dir_size, const char* name, int* lba, int* size)
{
    u8 sec[2352];
    size_t nl = strlen(name);
    for (int s = 0; s < (dir_size + 2047) / 2048; s++) {
        disc_read_sector(dir_lba + s, sec);
        const u8* d = sec + 24;
        int off = 0;
        while (off < 2048 && d[off]) {
            const u8* r = d + off;
            int ln = r[32];
            const char* nm = (const char*)r + 33;
            int ok = 1;
            for (size_t i = 0; i < nl; i++) {
                char a = nm[i], b = name[i];
                if (a >= 'a' && a <= 'z') a -= 32;
                if (b >= 'a' && b <= 'z') b -= 32;
                if (i >= (size_t)ln || a != b) { ok = 0; break; }
            }
            if (ok && (ln == (int)nl || nm[nl] == ';')) {
                *lba = r[2] | r[3] << 8 | r[4] << 16 | r[5] << 24;
                *size = r[10] | r[11] << 8 | r[12] << 16 | r[13] << 24;
                return 0;
            }
            off += r[0];
        }
    }
    return -1;
}
static int fast_booted;
static void fast_boot(void)
{
    u8 sec[2352];
    disc_read_sector(16, sec);
    const u8* root = sec + 24 + 156;
    int rl = root[2] | root[3] << 8 | root[4] << 16 | root[5] << 24;
    int rs = root[10] | root[11] << 8 | root[12] << 16 | root[13] << 24;
    int lba, size;
    if (iso_find(rl, rs, "SYSTEM.CNF", &lba, &size)) { psx_log("SYSTEM.CNF não achado\n"); return; }
    disc_read_sector(lba, sec);
    char cnf[2049]; memcpy(cnf, sec + 24, 2048); cnf[2048] = 0;
    char* b = cnf;
    while (*b && !(b[0] == 'B' && b[1] == 'O' && b[2] == 'O' && b[3] == 'T')) b++;
    while (*b && *b != '\\' && *b != ':') b++;
    if (*b == ':') b++;
    if (*b == '\\') b++;
    char name[64]; int n = 0;
    while (*b && *b != ';' && *b != '\r' && *b != '\n' && n < 63) name[n++] = *b++;
    name[n] = 0;
    if (iso_find(rl, rs, name, &lba, &size)) { psx_log("EXE não achado: %s\n", name); return; }
    disc_read_sector(lba, sec);
    const u8* h = sec + 24;
    u32 pc0 = h[0x10] | h[0x11] << 8 | h[0x12] << 16 | (u32)h[0x13] << 24;
    u32 gp = h[0x14] | h[0x15] << 8 | h[0x16] << 16 | (u32)h[0x17] << 24;
    u32 ta = h[0x18] | h[0x19] << 8 | h[0x1A] << 16 | (u32)h[0x1B] << 24;
    u32 ts = h[0x1C] | h[0x1D] << 8 | h[0x1E] << 16 | (u32)h[0x1F] << 24;
    u32 sa = h[0x30] | h[0x31] << 8 | h[0x32] << 16 | (u32)h[0x33] << 24;
    u32 ss = h[0x34] | h[0x35] << 8 | h[0x36] << 16 | (u32)h[0x37] << 24;
    for (u32 i = 0; i < ts; i += 2048) {
        disc_read_sector(lba + 1 + i / 2048, sec);
        u32 c = ts - i < 2048 ? ts - i : 2048;
        memcpy(psx_ram + ((ta + i) & 0x1FFFFF), sec + 24, c);
    }
    cpu.r[28] = gp;
    if (sa) { cpu.r[29] = sa + ss; cpu.r[30] = sa + ss; }
    cpu.pc = pc0; cpu.next_pc = pc0 + 4;
    fast_booted = 1;
    psx_log("partida: %s pc=%x\n", name, pc0);
}

int bios_trace;
void psx_hook_pc(u32 pc)
{
    if (pc == 0x80030000 && !fast_booted) { fast_boot(); return; }
    if (bios_trace && (pc == 0xA0 || pc == 0xB0 || pc == 0xC0)) psx_log("[%x:%x a0=%x ra=%x]\n", pc, cpu.r[9], cpu.r[4], cpu.r[31]);
    if (pc == 0xA0 || pc == 0xB0) {
        u32 fn = cpu.r[9];
        if ((pc == 0xA0 && fn == 0x3C) || (pc == 0xB0 && fn == 0x3D)) { char c[2] = { (char)cpu.r[4], 0 }; psx_log("%s", c); }
    }
}

// ------------------------------------------------------------------ quadros
unsigned pad_buttons;
extern int gpu_drew;
static u32 shown[1 << 18];
static int shown_len;
static u64 frame_end;
static int started;
static char env_buf[2048];
static const char* env_get(const char* k)
{
    size_t n = strlen(k);
    for (char* p = env_buf; *p; p += strlen(p) + 1)
        if (memcmp(p, k, n) == 0 && p[n] == '=') return p + n + 1;
    return 0;
}
extern void Psyz_SpuInit(void);
extern void Psyz_SpuPullSamples(short* out, int n);

static int movie_n, movie_lba[16], movie_len[16];
static int movie_req = -1, movie_wait;
void movie_scan(void);
extern u8 card_data[0x20000];
extern int card_dirty;
extern void card_format(void);
static int card_loaded;

PSXAPI int x4_start(const u8* bios, size_t size, const char* env)
{
    size_t n = 0;
    for (const char* p = env; p && *p && n < sizeof(env_buf) - 2; p++) env_buf[n++] = *p == ';' ? 0 : *p;
    env_buf[n++] = 0; env_buf[n] = 0;
    if (size > sizeof(psx_bios)) size = sizeof(psx_bios);
    memcpy(psx_bios, bios, size);
    const char* d = env_get("DISC");
    if (!d || disc_open(d) != 0) { psx_log("disco não encontrado: %s\n", d ? d : "(nenhum)"); return -1; }
    Psyz_SpuInit();
    { extern int cd_trace; cd_trace = env_get("CDTRACE") != 0; }
    { extern u32 watch_addr; const char* w = env_get("WATCH"); watch_addr = 0; if (w) for (; *w; w++) watch_addr = watch_addr * 16 + (*w <= '9' ? *w - '0' : (*w | 32) - 'a' + 10); }
    { extern u32 trace_pc; const char* w = env_get("TRACEPC"); trace_pc = 0; if (w) for (; *w; w++) trace_pc = trace_pc * 16 + (*w <= '9' ? *w - '0' : (*w | 32) - 'a' + 10); }
    { extern int dbg_on; dbg_on = env_get("WATCH") || env_get("TRACEPC") || env_get("PSXDEBUG"); }
    { extern int xfer_log; xfer_log = env_get("XFERLOG") ? env_get("XFERLOG")[0] - '0' : 0; }
    if (!card_loaded) card_format();
    card_loaded = 0;   // o próximo início formata de novo, a não ser que o Godot mande outro cartão
    { extern void hw_reset(void); extern void gte_reset(void); hw_reset(); gte_reset(); }
    fast_booted = 0; shown_len = 0; movie_req = -1;
    xa_rd = xa_cnt = 0; xa_phase = 0; memset(xa_h, 0, sizeof(xa_h)); xa_active = 0;
    movie_scan(); movie_wait = 0;
    cpu_reset();
    frame_end = 0;
    started = 1;
    psx_log("disco com %d setores\n", disc_sectors);
    return 0;
}

#define FRAME_CYCLES 564480
PSXAPI int x4_frame(unsigned buttons)
{
    if (!started) return -1;
    if (movie_wait) return 0;   // o Godot está tocando o vídeo
    pad_buttons = buttons;
    gpu_drew = 0;
    prim_len = 0;
    frame_end += FRAME_CYCLES;
    cpu_run(frame_end);
    irq_raise(0);       // VBlank
    { static int fcount; fcount++; if (env_get("BTRACE")) bios_trace = fcount >= 270; }
    { extern int st_int1, st_cmds, st_dma0, st_dma1, st_qfull, st_mdec_dec; static int fc;
      if (env_get("STATS") && ++fc % 30 == 0) { psx_log("[est int1=%d cmds=%d dma0=%d dma1=%d cheia=%d mdec=%d pc=%x]\n", st_int1, st_cmds, st_dma0, st_dma1, st_qfull, st_mdec_dec, cpu.pc); st_int1 = st_cmds = st_dma0 = st_dma1 = st_qfull = st_mdec_dec = 0;
        extern u32 trail[64][2]; extern int trail_i;
        if (env_get("TRAIL")) for (int k = 0; k < 12; k++) { int j = (trail_i - 12 + k) & 63; psx_log("   %x -> %x\n", trail[j][0], trail[j][1]); }
        { extern int st_cdr[4], st_cdw[16]; psx_log("   cd lê %d %d %d %d escreve idx=%d cmd=%d par=%d req=%d ie=%d if=%d\n", st_cdr[0], st_cdr[1], st_cdr[2], st_cdr[3], st_cdw[0], st_cdw[1], st_cdw[2], st_cdw[3], st_cdw[6], st_cdw[7]); for (int k = 0; k < 4; k++) st_cdr[k] = 0; for (int k = 0; k < 16; k++) st_cdw[k] = 0; }
        { extern int st_irqs, st_irq_delay; psx_log("   irqs=%d (em atraso %d)\n", st_irqs, st_irq_delay); st_irqs = st_irq_delay = 0; }
        psx_log("   sr=%x cause=%x epc=%x istat=%x imask=%x\n", cpu.cop0[12], cpu.cop0[13], cpu.cop0[14], i_stat, i_mask); } }
    gpu_frame_begin();
    extern int disp_written;
    extern int gpu_display_info(int*, int*, int*, int*, int*);
    if (gpu_drew) {
        int x, y, w, h, is24;
        gpu_display_info(&x, &y, &w, &h, &is24);
        // primeiro item: tamanho da tela (o Godot ajusta a escala)
        shown[0] = 2; shown[1] = 0xF1000000u; shown[2] = (u32)w | ((u32)(h > 240 ? 240 : h) << 16);
        memcpy(shown + 3, prim_stream, prim_len * 4);
        shown_len = prim_len + 3;
        disp_written = 0;
    } else if (disp_written) {
        gpu_vram_snapshot();
        // nada desenhado, mas a imagem da tela foi enviada direto para a VRAM (vídeos, logotipos)
        int x, y, w, h, is24;
        gpu_display_info(&x, &y, &w, &h, &is24);
        shown[0] = 3;
        shown[1] = 0xF0000000u | (u32)is24;
        shown[2] = (u32)x | ((u32)y << 16);
        shown[3] = (u32)w | ((u32)(h > 240 ? 240 : h) << 16);
        shown_len = 4;
        disp_written = 0;
    }
    return 0;
}
PSXAPI const u32* x4_prims(int* n) { *n = shown_len; return shown; }
PSXAPI const u16* x4_vram(int* dirty)
{
    *dirty = vram_draw_dirty;
    vram_draw_dirty = 0;
    return vram_draw;
}
PSXAPI const char* x4_log(void) { return log_buf; }
PSXAPI void x4_log_clear(void) { log_len = 0; log_buf[0] = 0; }
PSXAPI int x4_xa_need(void) { return -1; }
PSXAPI void x4_xa_feed(const u8* s, int n) { (void)s; (void)n; }
static short audio_buf[4096 * 2];
PSXAPI const short* x4_audio(int frames)
{
    if (frames > 4096) frames = 4096;
    Psyz_SpuPullSamples(audio_buf, frames);
    return audio_buf;
}
PSXAPI void x4_card_set(int port, const u8* d, int n)
{
    if (port != 0) return;
    if (n > (int)sizeof(card_data)) n = sizeof(card_data);
    memcpy(card_data, d, n);
    card_loaded = 1;
}
PSXAPI const u8* x4_card_get(int port, int* dirty)
{
    // só devolve quando o jogo escreveu algo e já terminou a escrita (nada há meio segundo)
    static int quiet;
    if (port != 0 || !card_dirty) { *dirty = 0; return card_data; }
    if (++quiet < 2) { *dirty = 0; return card_data; }
    quiet = 0; card_dirty = 0; *dirty = 1;
    return card_data;
}
// vídeos .STR do disco: tocados pelo Godot (arquivos .ogv convertidos), o tocador do jogo é dispensado
static void movie_scan_dir(int lba, int size, int depth)
{
    u8 sec[2352];
    for (int s = 0; s < (size + 2047) / 2048; s++) {
        disc_read_sector(lba + s, sec);
        const u8* d = sec + 24;
        int off = 0;
        while (off < 2048 && d[off]) {
            const u8* r = d + off;
            int ln = r[32];
            const char* nm = (const char*)r + 33;
            int el = r[2] | r[3] << 8 | r[4] << 16 | r[5] << 24;
            int es = r[10] | r[11] << 8 | r[12] << 16 | r[13] << 24;
            if ((r[25] & 2) && ln > 1 && depth < 2) movie_scan_dir(el, es, depth + 1);
            else for (int i = 0; i + 3 < ln; i++)
                if (nm[i] == '.' && (nm[i+1] | 32) == 's' && (nm[i+2] | 32) == 't' && (nm[i+3] | 32) == 'r' && movie_n < 16) {
                    movie_lba[movie_n] = el; movie_len[movie_n] = es / 2048; movie_n++; break;
                }
            off += r[0];
        }
    }
}
void movie_scan(void)
{
    u8 sec[2352];
    movie_n = 0;
    disc_read_sector(16, sec);
    const u8* root = sec + 24 + 156;
    movie_scan_dir(root[2] | root[3] << 8 | root[4] << 16 | root[5] << 24, root[10] | root[11] << 8 | root[12] << 16 | root[13] << 24, 0);
    // em ordem de posição no disco
    for (int i = 0; i < movie_n; i++) for (int j = i + 1; j < movie_n; j++)
        if (movie_lba[j] < movie_lba[i]) { int t = movie_lba[i]; movie_lba[i] = movie_lba[j]; movie_lba[j] = t; t = movie_len[i]; movie_len[i] = movie_len[j]; movie_len[j] = t; }
    for (int i = 0; i < movie_n; i++) psx_log("vídeo %d: setor %d (%d setores)\n", i, movie_lba[i], movie_len[i]);
}
void psx_movie_check(int lba)
{
    extern int movie_abort;
    for (int i = 0; i < movie_n; i++)
        if (lba >= movie_lba[i] && lba < movie_lba[i] + 32) {
            movie_req = i; movie_wait = 1; movie_abort = 1;
            psx_log("vídeo %d pedido\n", i);
            return;
        }
}
PSXAPI int x4_movie_request(void) { return movie_wait ? movie_req : -1; }
PSXAPI void x4_movie_done(void) { movie_wait = 0; }
PSXAPI u32 psx_debug_pc(void) { return cpu.pc; }
PSXAPI u8* psx_ram_ptr(void) { return psx_ram; }
// mem: lê/escreve a RAM do PS1 (tamanho 1/2/4 lê; negativo escreve)
extern int cd_fast;
PSXAPI long long x4_mem(unsigned addr, long long value, int size)
{
    if (addr == 0xFFFFFF00u) { if (size < 0) cd_fast = (int)value; return cd_fast; }   // leitor de CD acelerado (carregamentos)
    u8* p = psx_ram + (addr & 0x1FFFFF);
    int n = size < 0 ? -size : size;
    if (n != 1 && n != 2 && n != 4) return 0;
    if (size < 0) for (int i = 0; i < n; i++) p[i] = (u8)(value >> (i * 8));
    u32 v = 0;
    for (int i = 0; i < n; i++) v |= (u32)p[i] << (i * 8);
    return v;
}
// depois de restaurar um estado salvo: o arquivo do disco precisa ser aberto de novo
void psx_after_state_load(void)
{
    const char* d = env_get("DISC");
    if (d) disc_open(d);
    cd_fast = 0;
    log_len = 0; log_buf[0] = 0;
}

PSXAPI void psx_rwatch(u32 lo, u32 hi, u32 on) { extern u32 rw_lo, rw_hi, rw_on; rw_lo = lo; rw_hi = hi; rw_on = on; }
PSXAPI void psx_spu_debug(unsigned mask, int cd_mute, int keyon_log)
{
    extern unsigned psyz_voice_mask; extern int psyz_cd_mute, psyz_keyon_log; extern void (*psyz_log_fn)(const char*, ...);
    psyz_voice_mask = mask; psyz_cd_mute = cd_mute; psyz_keyon_log = keyon_log; psyz_log_fn = psx_log;
}
PSXAPI const u8* psx_spu_ram(void) { extern u8* Psyz_SpuGetRam(void); return Psyz_SpuGetRam(); }
