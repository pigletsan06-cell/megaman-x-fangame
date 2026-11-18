// Runtime nativo do X4 dentro do Godot: faz o papel do "PS1" (memória, threads do jogo,
// CD, GPU em alto nível, controle) para o código do decomp compilado direto em código de máquina.
// O mesmo arquivo compila para Linux (.so) e Windows (.dll), sem libc (freestanding).
#include "common.h"
#include "pc_build.h"
#include <libcd.h>
#include <libgpu.h>
#include <libetc.h>
#include <stdarg.h>
#include "x4core.h"
#include "main/player_special.h"

#ifdef _WIN32
int _fltused = 0;
#endif
// ------------------------------------------------------------------ memória (sem libc)
#define HEAP_SIZE (48u << 20)
static __attribute__((aligned(16))) unsigned char heap[HEAP_SIZE];
static size_t heap_top;

void* malloc(size_t n)
{
    size_t a = (heap_top + 15) & ~(size_t)15;
    if (a + n > HEAP_SIZE) {
        x4_fail("sem memória");
        return 0;
    }
    heap_top = a + n;
    return heap + a;
}
void* calloc(size_t n, size_t m)
{
    void* p = malloc(n * m);
    if (p) memset(p, 0, n * m);
    return p;
}
void* realloc(void* p, size_t n)
{
    void* q = malloc(n);
    if (p && q) memcpy(q, p, n); // pode ler além do bloco antigo, mas fica dentro do heap
    return q;
}
void free(void* p) { (void)p; }

void* memcpy(void* d, const void* s, size_t n)
{
    unsigned char* a = d;
    const unsigned char* b = s;
    while (n >= 8) { *(unsigned long long*)a = *(const unsigned long long*)b; a += 8; b += 8; n -= 8; }
    while (n--) *a++ = *b++;
    return d;
}
void* memmove(void* d, const void* s, size_t n)
{
    unsigned char* a = d;
    const unsigned char* b = s;
    if (a < b) { while (n--) *a++ = *b++; }
    else { a += n; b += n; while (n--) *--a = *--b; }
    return d;
}
void* memset(void* d, int v, size_t n)
{
    unsigned char* a = d;
    while (n--) *a++ = (unsigned char)v;
    return d;
}
int memcmp(const void* x, const void* y, size_t n)
{
    const unsigned char *a = x, *b = y;
    for (; n; n--, a++, b++)
        if (*a != *b) return *a - *b;
    return 0;
}
size_t strlen(const char* s) { size_t n = 0; while (s[n]) n++; return n; }
int strcmp(const char* a, const char* b)
{
    while (*a && *a == *b) { a++; b++; }
    return (unsigned char)*a - (unsigned char)*b;
}
int strncmp(const char* a, const char* b, size_t n)
{
    for (; n; n--, a++, b++) {
        if (*a != *b || !*a) return (unsigned char)*a - (unsigned char)*b;
    }
    return 0;
}
char* strcpy(char* d, const char* s) { char* r = d; while ((*d++ = *s++)); return r; }
char* strncpy(char* d, const char* s, size_t n)
{
    size_t i = 0;
    for (; i < n && s[i]; i++) d[i] = s[i];
    for (; i < n; i++) d[i] = 0;
    return d;
}
char* strchr(const char* s, int c)
{
    for (;; s++) { if (*s == (char)c) return (char*)s; if (!*s) return 0; }
}
int abs(int v) { return v < 0 ? -v : v; }
unsigned long strtoul(const char* s, char** end, int base)
{
    unsigned long v = 0;
    while (*s == ' ' || *s == '\t') s++;
    if ((base == 0 || base == 16) && s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) { s += 2; base = 16; }
    if (base == 0) base = 10;
    for (;; s++) {
        int d;
        if (*s >= '0' && *s <= '9') d = *s - '0';
        else if (*s >= 'a' && *s <= 'z') d = *s - 'a' + 10;
        else if (*s >= 'A' && *s <= 'Z') d = *s - 'A' + 10;
        else break;
        if (d >= base) break;
        v = v * base + d;
    }
    if (end) *end = (char*)s;
    return v;
}
long strtol(const char* s, char** end, int base)
{
    int neg = 0;
    while (*s == ' ') s++;
    if (*s == '-') { neg = 1; s++; }
    long v = (long)strtoul(s, end, base);
    return neg ? -v : v;
}
int atoi(const char* s) { return (int)strtol(s, 0, 10); }

// ------------------------------------------------------------------ ambiente (MMX4_*)
static char env_buf[4096];
char* getenv(const char* name)
{
    // env_buf: "NOME=valor\0NOME=valor\0\0"
    size_t n = strlen(name);
    for (char* p = env_buf; *p; p += strlen(p) + 1)
        if (strncmp(p, name, n) == 0 && p[n] == '=') return p + n + 1;
    return 0;
}

// ------------------------------------------------------------------ mensagens
struct X4FILE { int dummy; };
static struct X4FILE f_err, f_out;
FILE* stderr = &f_err;
FILE* stdout = &f_out;
static char log_buf[16384];
static size_t log_len;
static void log_str(const char* s)
{
    while (*s && log_len < sizeof(log_buf) - 1) log_buf[log_len++] = *s++;
    log_buf[log_len] = 0;
}
static void log_num(unsigned long long v, int base)
{
    char t[24]; int i = 0;
    do { t[i++] = "0123456789abcdef"[v % base]; v /= base; } while (v && i < 23);
    char o[25]; int j = 0;
    while (i) o[j++] = t[--i];
    o[j] = 0;
    log_str(o);
}
int vfprintf(FILE* f, const char* fmt, va_list ap)
{
    (void)f;
    if (log_len > sizeof(log_buf) - 256) return 0;
    for (const char* p = fmt; *p; p++) {
        if (*p != '%') { char c[2] = { *p, 0 }; log_str(c); continue; }
        p++;
        int lng = 0;   // 0: int, 1: long, 2: long long / size_t
        while (*p && strchr("0123456789.-+ #", *p)) p++;
        while (*p == 'l' || *p == 'z' || *p == 'h') { if (*p == 'z') lng = 2; else if (*p == 'l') lng++; p++; }
        switch (*p) {
        case 's': { const char* s = va_arg(ap, const char*); log_str(s ? s : "(null)"); break; }
        case 'd': case 'i': {
            long long v = lng == 2 ? va_arg(ap, long long) : lng == 1 ? va_arg(ap, long) : va_arg(ap, int);
            if (v < 0) { log_str("-"); v = -v; }
            log_num((unsigned long long)v, 10); break;
        }
        case 'u': log_num(lng == 2 ? va_arg(ap, unsigned long long) : lng == 1 ? va_arg(ap, unsigned long) : va_arg(ap, unsigned), 10); break;
        case 'x': case 'X': log_num(lng == 2 ? va_arg(ap, unsigned long long) : lng == 1 ? va_arg(ap, unsigned long) : va_arg(ap, unsigned), 16); break;
        case 'p': log_str("0x"); log_num((unsigned long long)va_arg(ap, void*), 16); break;
        case 'c': { char c[2] = { (char)va_arg(ap, int), 0 }; log_str(c); break; }
        case '%': log_str("%"); break;
        default: if (!*p) return 0;
        }
    }
    return 0;
}
int fprintf(FILE* f, const char* fmt, ...) { va_list ap; va_start(ap, fmt); vfprintf(f, fmt, ap); va_end(ap); return 0; }
int printf(const char* fmt, ...) { va_list ap; va_start(ap, fmt); vfprintf(stdout, fmt, ap); va_end(ap); return 0; }
int fflush(FILE* f) { (void)f; return 0; }
FILE* fopen(const char* p, const char* m) { (void)p; (void)m; return 0; }
int fclose(FILE* f) { (void)f; return 0; }
size_t fwrite(const void* b, size_t s, size_t n, FILE* f) { (void)b; (void)s; (void)f; return n; }
void __assert_fail(const char* e, const char* file, unsigned line, const char* fn)
{
    fprintf(stderr, "assert: %s (%s:%u %s)\n", e, file, line, fn);
}

// ------------------------------------------------------------------ corrotinas (troca de pilha)
// co_switch(salvar_em, ir_para): guarda os registradores preservados e troca a pilha.
void co_switch(void** from, void** to);
#if defined(_WIN64)
__asm__(".text\n.globl co_switch\nco_switch:\n"
        "push %rbp\npush %rbx\npush %rdi\npush %rsi\npush %r12\npush %r13\npush %r14\npush %r15\n"
        "sub $168, %rsp\n"
        "movdqu %xmm6, 0(%rsp)\nmovdqu %xmm7, 16(%rsp)\nmovdqu %xmm8, 32(%rsp)\nmovdqu %xmm9, 48(%rsp)\n"
        "movdqu %xmm10, 64(%rsp)\nmovdqu %xmm11, 80(%rsp)\nmovdqu %xmm12, 96(%rsp)\nmovdqu %xmm13, 112(%rsp)\n"
        "movdqu %xmm14, 128(%rsp)\nmovdqu %xmm15, 144(%rsp)\n"
        "mov %rsp, (%rcx)\nmov (%rdx), %rsp\n"
        "movdqu 0(%rsp), %xmm6\nmovdqu 16(%rsp), %xmm7\nmovdqu 32(%rsp), %xmm8\nmovdqu 48(%rsp), %xmm9\n"
        "movdqu 64(%rsp), %xmm10\nmovdqu 80(%rsp), %xmm11\nmovdqu 96(%rsp), %xmm12\nmovdqu 112(%rsp), %xmm13\n"
        "movdqu 128(%rsp), %xmm14\nmovdqu 144(%rsp), %xmm15\n"
        "add $168, %rsp\n"
        "pop %r15\npop %r14\npop %r13\npop %r12\npop %rsi\npop %rdi\npop %rbx\npop %rbp\nret\n");
#define CO_SAVED_BYTES (8 * 8 + 168)
#else
__asm__(".text\n.globl co_switch\n.hidden co_switch\nco_switch:\n"
        "push %rbp\npush %rbx\npush %r12\npush %r13\npush %r14\npush %r15\n"
        "mov %rsp, (%rdi)\nmov (%rsi), %rsp\n"
        "pop %r15\npop %r14\npop %r13\npop %r12\npop %rbx\npop %rbp\nret\n");
#define CO_SAVED_BYTES (6 * 8)
#endif

struct Co {
    void* sp;
    int started;
    void (*entry)(void);
    unsigned char* stack;
    size_t size;
};
static struct Co* co_starting;
static void co_trampoline(void)
{
    struct Co* c = co_starting;
    c->entry();
    x4_fail("corrotina terminou");
    for (;;) {}
}
static void co_init(struct Co* c, void (*entry)(void))
{
    unsigned long long top = ((unsigned long long)(c->stack + c->size) - 128) & ~15ull;
    unsigned long long* sp = (unsigned long long*)top;
    *--sp = 0;                                  // retorno falso do trampolim
    *--sp = (unsigned long long)co_trampoline; // para onde o "ret" vai
    sp = (unsigned long long*)((unsigned char*)sp - CO_SAVED_BYTES);
    memset(sp, 0, CO_SAVED_BYTES);
    c->sp = sp;
    c->entry = entry;
    c->started = 0;
}
static void co_resume(void** save, struct Co* c)
{
    if (!c->started) { c->started = 1; co_starting = c; }
    co_switch(save, &c->sp);
}

// pilhas dentro da imagem da biblioteca (endereços baixos no Windows: /base:0x10000000)
#define STACK_SIZE (512 * 1024)
static __attribute__((aligned(16))) unsigned char main_stack[STACK_SIZE];
static __attribute__((aligned(16))) unsigned char thread_stacks[4][STACK_SIZE];

static void* host_sp;         // pilha do Godot
static struct Co game_co;      // laço principal do jogo
static int game_failed;
static const char* fail_msg;

void x4_fail(const char* msg)
{
    if (!game_failed) { game_failed = 1; fail_msg = msg; fprintf(stderr, "X4 parou: %s\n", msg); }
    // volta para o Godot e nunca mais continua o jogo
    void* dead;
    for (;;) co_switch(&dead, &host_sp);
}
void abort(void) { x4_fail("abort"); for (;;) {} }
void exit(int c) { (void)c; x4_fail("exit"); for (;;) {} }

// ------------------------------------------------------------------ threads do jogo (como threads.c, com corrotinas)
struct PcThread {
    struct Co co;
    void (*entry)(void);
    int initialized;
    int restart;
};
static struct GameThread game_threads[4];
static struct PcThread pc_threads[4];
static void* sched_sp;
static int current_thread = -1;
struct GameThread* D_801F8300;

static void thread_body(void)
{
    int slot = current_thread;
    pc_threads[slot].entry();
    game_threads[slot].state = 0;
    pc_threads[slot].initialized = 0;
    current_thread = -1;
    void* dead;
    co_switch(&dead, &sched_sp);
}
static void prepare_thread(int slot)
{
    struct PcThread* t = &pc_threads[slot];
    t->co.stack = thread_stacks[slot];
    t->co.size = STACK_SIZE;
    co_init(&t->co, thread_body);
    t->initialized = 1;
    t->restart = 0;
}
void mmx4_pc_threads_init(void)
{
    for (int s = 0; s < 4; s++) {
        game_threads[s].state = 0;
        pc_threads[s].entry = 0;
        pc_threads[s].initialized = 0;
        pc_threads[s].restart = 0;
    }
    D_801F8300 = &game_threads[0];
}
struct GameThread* mmx4_pc_thread_slot(s32 slot) { return &game_threads[slot]; }
void mmx4_pc_thread_create(s32 slot, void (*entry)(void))
{
    pc_threads[slot].entry = entry;
    game_threads[slot].state = 2;
    prepare_thread(slot);
}
void mmx4_pc_thread_run(s32 slot)
{
    struct PcThread* t = &pc_threads[slot];
    if (t->entry == 0 || game_threads[slot].state == 0) return;
    if (!t->initialized || t->restart) prepare_thread(slot);
    current_thread = slot;
    D_801F8300 = &game_threads[slot];
    co_resume(&sched_sp, &t->co);
    current_thread = -1;
}
void mmx4_pc_thread_yield(void)
{
    int slot = current_thread;
    if (slot < 0) abort();
    co_switch(&pc_threads[slot].co.sp, &sched_sp);
    current_thread = slot;
}
void mmx4_pc_thread_close(void)
{
    int slot = current_thread;
    if (slot < 0) abort();
    pc_threads[slot].initialized = 0;
    void* dead;
    co_switch(&dead, &sched_sp);
    abort();
}
void mmx4_pc_thread_replace(void (*entry)(void))
{
    int slot = current_thread;
    if (slot < 0) abort();
    pc_threads[slot].entry = entry;
    pc_threads[slot].restart = 1;
    game_threads[slot].state = 2;
    void* dead;
    co_switch(&dead, &sched_sp);
    abort();
}

// ------------------------------------------------------------------ CD (setores de dados do disco, 2048 bytes)
static const unsigned char* disc;
static size_t disc_size;
static int cd_lba, cd_reading, cd_last, xa_playing, xa_lba;
static int xa_feed_lba;
static unsigned char xa_ffile, xa_fchan;
static int cd_mode_sf;
static void xa_reset(void);
static unsigned char cd_buf[12 + 2048 + 280];
static int cd_cur;
static CdlCB cd_ready_cb;
static void (*cd_data_cb)();

static int bcd(int v) { return (v / 10) * 16 + v % 10; }
static int unbcd(int v) { return (v >> 4) * 10 + (v & 15); }
CdlLOC* CdIntToPos(int i, CdlLOC* p)
{
    unsigned char* b = (unsigned char*)p;
    int n = i + 150;
    b[0] = bcd(n / 4500); b[1] = bcd((n / 75) % 60); b[2] = bcd(n % 75); b[3] = 0;
    return p;
}
int CdPosToInt(CdlLOC* p)
{
    unsigned char* b = (unsigned char*)p;
    return unbcd(b[0]) * 4500 + unbcd(b[1]) * 75 + unbcd(b[2]) - 150;
}
static int xa_pos2;   // posição da música XA em meios-setores (toca a 150 setores/s)
int CdSync(int mode, u_char* result)
{
    (void)mode;
    if (result) {
        if (cd_last == 0x11) {   // CdlGetlocP: posição atual (relativa e absoluta)
            int n = xa_pos2 / 2 + 150;
            result[0] = 1; result[1] = 1;
            result[2] = bcd(n / 4500); result[3] = bcd((n / 75) % 60); result[4] = bcd(n % 75);
            result[5] = bcd(n / 4500); result[6] = bcd((n / 75) % 60); result[7] = bcd(n % 75);
        } else {
            result[0] = 2;
        }
    }
    return 2;
}
int CdLastCom(void) { return cd_last; }
static void cd_command(int com, u_char* param)
{
    cd_last = com;
    if ((com == 2 || com == 0x15 || com == 0x16) && param) cd_lba = CdPosToInt((CdlLOC*)param);
    else if (com == 6) { if (param) cd_lba = CdPosToInt((CdlLOC*)param); cd_reading = 1; xa_playing = 0; xa_reset(); }
    else if (com == 0x1B) { if (param) cd_lba = CdPosToInt((CdlLOC*)param); xa_playing = 1; xa_lba = cd_lba; xa_pos2 = cd_lba * 2; xa_feed_lba = cd_lba; xa_reset(); }
    else if (com == 0x0D && param) { xa_ffile = param[0]; xa_fchan = param[1]; }
    else if (com == 0x0E && param) { cd_mode_sf = (param[0] & 0x08) != 0; }
    else if (com == 9 || com == 8) { cd_reading = 0; xa_playing = 0; xa_reset(); }
}
int CdControl(u_char com, u_char* param, u_char* result) { (void)result; cd_command(com, param); return 1; }
int CdControlB(u_char com, u_char* param, u_char* result) { (void)result; cd_command(com, param); return 1; }
int CdControlF(u_char com, u_char* param) { cd_command(com, param); return 1; }
int CdReady(int mode, u_char* result)
{
    (void)mode; (void)result;
    if (!cd_reading) return 0;
    memset(cd_buf, 0, sizeof(cd_buf));
    int n = cd_lba + 150;
    cd_buf[0] = bcd(n / 4500); cd_buf[1] = bcd((n / 75) % 60); cd_buf[2] = bcd(n % 75); cd_buf[3] = 2;
    cd_buf[6] = 8; cd_buf[10] = 8;
    if (disc && (size_t)cd_lba * 2048 + 2048 <= disc_size)
        memcpy(cd_buf + 12, disc + (size_t)cd_lba * 2048, 2048);
    cd_lba++;
    cd_cur = 0;
    return 1;
}
CdlCB CdReadyCallback(CdlCB f) { CdlCB o = cd_ready_cb; cd_ready_cb = f; return o; }
void(*CdDataCallback(void (*f)()))
{
    void (*o)() = cd_data_cb; cd_data_cb = f; return (void*)o;
}
int CdInit(void) { return 1; }
int CdReset(int mode) { (void)mode; return 1; }
int CdGetSector(void* madr, int size)
{
    int n = size * 4;
    unsigned char* d = madr;
    for (int i = 0; i < n; i++) d[i] = (cd_cur + i < (int)sizeof(cd_buf)) ? cd_buf[cd_cur + i] : 0;
    cd_cur += n;
    return 1;
}
int mmx4_pc_replay_xa_start_ready(void) { return 1; }


// ------------------------------------------------------------------ som: SPU (psyz) + música XA
// Timers do PS1 que o libsnd usa para o sequenciador (copiado do psyz/libetc.c)
#define RCNT2_CLOCK_HZ 4233600
static struct { unsigned rate_hz; int accum; void (*handler)(void); } rcnt2, rcnt3;
static unsigned set_counter;
void* InterruptCallback(int arg0, void (*cb)())
{
    if (arg0 < 0 || arg0 >= 0x100) return 0;
    void (*prev)(void) = 0;
    switch (set_counter) {
    case 2: prev = rcnt2.handler; if (cb) { rcnt2.handler = cb; set_counter = 0; } break;
    case 3: prev = rcnt3.handler; if (cb) { rcnt3.handler = cb; set_counter = 0; } break;
    }
    return (void*)prev;
}
long SetRCnt(long spec, unsigned short target, long mode)
{
    (void)mode;
    set_counter = (unsigned)(spec & 0xFF);
    if (set_counter == 2) { rcnt2.rate_hz = target ? RCNT2_CLOCK_HZ / target : 0; rcnt2.accum = 0; }
    if (set_counter == 3) { rcnt3.rate_hz = 60; rcnt3.accum = 0; }
    return 1;
}
long ResetRCnt(long spec)
{
    if ((spec & 0xFF) == 2) rcnt2.accum = 0;
    if ((spec & 0xFF) == 3) rcnt3.accum = 0;
    return 1;
}
static void rcnt_add(int* acc, unsigned rate, int n, void (*cb)(void))
{
    if (!rate || !cb) return;
    int a = *acc + (int)rate * n;
    while (a >= 44100) { a -= 44100; cb(); }
    *acc = a;
}
void Psyz_RcntAdd(int n)
{
    if (n <= 0) return;
    rcnt_add(&rcnt2.accum, rcnt2.rate_hz, n, rcnt2.handler);
    rcnt_add(&rcnt3.accum, rcnt3.rate_hz, n, rcnt3.handler);
}
static void (*vsync_cb)(void);
int VSyncCallback(void (*f)()) { vsync_cb = (void (*)(void))f; return 0; }
void* DMACallback(int dma, void (*f)()) { (void)dma; (void)f; return 0; }
long GetVideoMode(void) { return 0; }
void psyz_log(unsigned int level, const char* file, unsigned int line, const char* func, const char* fmt, ...)
{
    (void)level; (void)file; (void)line; (void)func; (void)fmt;
}

// XA: setores lidos pelo Godot do .bin do jogo, decodificados aqui
#define XA_RING (65536)
static short xa_ring[XA_RING * 2];
static unsigned xa_rd, xa_cnt;
static int xa_hl1, xa_hl2, xa_hr1, xa_hr2;
static unsigned xa_phase;
static short xa_cur[2], xa_prev[2];

static void xa_reset(void)
{
    xa_rd = xa_cnt = 0;
    xa_hl1 = xa_hl2 = xa_hr1 = xa_hr2 = 0;
    xa_phase = 0;
    xa_cur[0] = xa_cur[1] = xa_prev[0] = xa_prev[1] = 0;
}
static short clamp16x(int v) { return v > 32767 ? 32767 : v < -32768 ? -32768 : (short)v; }
static const int xa_k0[4] = { 0, 60, 115, 98 };
static const int xa_k1[4] = { 0, 0, -52, -55 };
static void xa_dec28(const unsigned char* blk, int sub, int nib, short* dst, int stride, int* p1, int* p2)
{
    unsigned char h = blk[4 + sub * 2 + nib];
    int sh = (h & 15) > 12 ? 9 : 12 - (h & 15);
    int f = (h >> 4) & 3;
    for (int j = 0; j < 28; j++) {
        int t = (blk[16 + sub + j * 4] >> (nib * 4)) & 15;
        if (t & 8) t -= 16;
        int v = (t << sh) + ((*p1 * xa_k0[f] + *p2 * xa_k1[f] + 32) / 64);
        dst[j * stride] = clamp16x(v);
        *p2 = *p1;
        *p1 = v;
    }
}
static void xa_push(short l, short r)
{
    if (xa_cnt >= XA_RING) return;
    unsigned w = (xa_rd + xa_cnt) & (XA_RING - 1);
    xa_ring[w * 2] = l; xa_ring[w * 2 + 1] = r;
    xa_cnt++;
}
X4API int x4_xa_need(void)
{
    if (!xa_playing || xa_cnt > 37800 / 3) return -1;
    return xa_feed_lba++;
}
X4API void x4_xa_feed(const unsigned char* sec, int len)
{
    if (!xa_playing || len < 2352) return;
    unsigned char file = sec[0x10], chan = sec[0x11], sub = sec[0x12], ci = sec[0x13];
    if ((sub & 0x44) != 0x44) return;
    if (cd_mode_sf && (file != xa_ffile || chan != xa_fchan)) return;
    const unsigned char* u = sec + 0x18;
    static short tmp[4032 * 2];
    int n = 0;
    if ((ci & 3) == 1) {
        for (int i = 0; i < 18; i++)
            for (int s = 0; s < 4; s++) {
                xa_dec28(u + i * 128, s, 0, &tmp[n * 2], 2, &xa_hl1, &xa_hl2);
                xa_dec28(u + i * 128, s, 1, &tmp[n * 2 + 1], 2, &xa_hr1, &xa_hr2);
                n += 28;
            }
    } else {
        short mono[4032];
        for (int i = 0; i < 18; i++)
            for (int s = 0; s < 4; s++) {
                xa_dec28(u + i * 128, s, 0, &mono[n], 1, &xa_hl1, &xa_hl2); n += 28;
                xa_dec28(u + i * 128, s, 1, &mono[n], 1, &xa_hl1, &xa_hl2); n += 28;
            }
        for (int i = 0; i < n; i++) { tmp[i * 2] = mono[i]; tmp[i * 2 + 1] = mono[i]; }
    }
    int half = (ci & 4) != 0;   // 18900 Hz: repete cada amostra
    for (int i = 0; i < n; i++) {
        xa_push(tmp[i * 2], tmp[i * 2 + 1]);
        if (half) xa_push(tmp[i * 2], tmp[i * 2 + 1]);
    }
}
size_t Psyz_CdPullSamples(short* out, size_t frames)
{
    if (!xa_playing) return 0;
    size_t w = 0;
    const unsigned step = (37800u << 16) / 44100u;
    while (w < frames) {
        while (xa_phase >= 0x10000) {
            if (xa_cnt == 0) return w;
            xa_prev[0] = xa_cur[0]; xa_prev[1] = xa_cur[1];
            xa_cur[0] = xa_ring[xa_rd * 2]; xa_cur[1] = xa_ring[xa_rd * 2 + 1];
            xa_rd = (xa_rd + 1) & (XA_RING - 1);
            xa_cnt--;
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
extern void Psyz_SpuInit(void);
extern void Psyz_SpuPullSamples(short* out, int num_frames);
static short audio_buf[4096 * 2];
X4API const short* x4_audio(int frames)
{
    if (frames > 4096) frames = 4096;
    Psyz_SpuPullSamples(audio_buf, frames);
    return audio_buf;
}

// ------------------------------------------------------------------ tempo e controle
static int vsync_count;
static unsigned buttons;
int VSync(int mode) { (void)mode; return vsync_count; }
unsigned long mmx4_pc_frame_number(void) { return vsync_count; }
void mmx4_pc_input_update(u8* b)
{
    b[0] = 0; b[1] = 0x41;
    b[2] = (~buttons >> 8) & 0xFF; b[3] = ~buttons & 0xFF;
}

// ------------------------------------------------------------------ GPU em alto nível
static u16 vram[1024 * 512];
static u16 vram_draw[1024 * 512];
static int vram_dirty = 1, vram_draw_dirty = 1;
#define PRIM_MAX (1 << 18)
static u32 prims[PRIM_MAX];
static int prims_len;

int LoadImage(RECT* r, u_long* p)
{
    const u16* s = (const u16*)p;
    for (int y = 0; y < r->h; y++)
        for (int x = 0; x < r->w; x++)
            vram[((r->y + y) & 511) * 1024 + ((r->x + x) & 1023)] = s[y * r->w + x];
    vram_dirty = 1;
    return 0;
}
int StoreImage(RECT* r, u_long* p)
{
    u16* d = (u16*)p;
    for (int y = 0; y < r->h; y++)
        for (int x = 0; x < r->w; x++)
            d[y * r->w + x] = vram[((r->y + y) & 511) * 1024 + ((r->x + x) & 1023)];
    return 0;
}
int MoveImage(RECT* r, int dx, int dy)
{
    static u16 tmp[1024 * 512];
    for (int y = 0; y < r->h; y++)
        for (int x = 0; x < r->w; x++)
            tmp[y * r->w + x] = vram[((r->y + y) & 511) * 1024 + ((r->x + x) & 1023)];
    for (int y = 0; y < r->h; y++)
        for (int x = 0; x < r->w; x++)
            vram[((dy + y) & 511) * 1024 + ((dx + x) & 1023)] = tmp[y * r->w + x];
    vram_dirty = 1;
    return 0;
}
int ClearImage(RECT* r, u_char cr, u_char cg, u_char cb)
{
    u16 v = ((cr >> 3) & 31) | (((cg >> 3) & 31) << 5) | (((cb >> 3) & 31) << 10);
    for (int y = 0; y < r->h; y++)
        for (int x = 0; x < r->w; x++)
            vram[((r->y + y) & 511) * 1024 + ((r->x + x) & 1023)] = v;
    vram_dirty = 1;
    return 0;
}
OT_TYPE* ClearOTagR(OT_TYPE* ot, int n)
{
    for (int i = 0; i < n; i++) {
        ot[i].tag = i == 0 ? 0xFFFFFF : (u_long)&ot[i - 1];
        ot[i].len = 0;
    }
    return ot;
}
void DrawOTag(OT_TYPE* p)
{
    // o GPU do PS1 desenha a lista antes dos envios de VRAM feitos depois no quadro
    if (vram_dirty) {
        memcpy(vram_draw, vram, sizeof(vram));
        vram_dirty = 0;
        vram_draw_dirty = 1;
    }
    P_TAG* t = (P_TAG*)p;
    int guard = 0;
    while (t && (u_long)t != 0xFFFFFF && guard++ < 20000) {
        u_long n = t->len;
        if (n > 0 && n < 64 && prims_len + (int)n + 1 < PRIM_MAX) {
            const u32* w = (const u32*)((unsigned char*)t + 16);
            prims[prims_len++] = (u32)n;
            for (u_long i = 0; i < n; i++) prims[prims_len++] = w[i];
        }
        t = (P_TAG*)t->addr;
    }
}
DRAWENV* PutDrawEnv(DRAWENV* e) { return e; }
DISPENV* PutDispEnv(DISPENV* e) { return e; }
DRAWENV* SetDefDrawEnv(DRAWENV* env, int x, int y, int w, int h)
{
    memset(env, 0, sizeof(*env));
    env->clip.x = x; env->clip.y = y; env->clip.w = w; env->clip.h = h;
    env->ofs[0] = x; env->ofs[1] = y;
    env->tpage = 0x0A; env->dtd = 1;
    return env;
}
DISPENV* SetDefDispEnv(DISPENV* env, int x, int y, int w, int h)
{
    memset(env, 0, sizeof(*env));
    env->disp.x = x; env->disp.y = y; env->disp.w = w; env->disp.h = h;
    return env;
}
u_short GetTPage(int tp, int abr, int x, int y)
{
    return ((tp & 3) << 7) | ((abr & 3) << 5) | ((y & 0x100) >> 4) | ((x & 0x3FF) >> 6) | ((y & 0x200) << 2);
}
int GetGraphType(void) { return 0; }
void SetDrawMode(DR_MODE* p, int dfe, int dtd, int tpage, RECT* tw)
{
    (void)tw;
    P_TAG* t = (P_TAG*)p;
    t->len = 2;
    u32* w = (u32*)((unsigned char*)p + 16);
    w[0] = 0xE1000000 | (tpage & 0x9FF) | ((dtd & 1) << 9) | ((dfe & 1) << 10);
    w[1] = 0xE2000000;
}

int mmx4_pc_hide_background;
s32 mmx4_pc_sfx_group = -1;
u32 mmx4_pc_sfx_index;
const char* mmx4_pc_sfx_raw;
u32 mmx4_pc_sfx_frames = 360;

// ------------------------------------------------------------------ vídeos (o Godot toca os .ogv convertidos dos STR do disco)
static int movie_req = -1, movie_playing;
extern void func_800127C8(s32);
void func_80018000(u8 movie)
{
    movie_req = movie;
    if (current_thread < 0) return;   // fora de uma thread do jogo: não dá para esperar
    movie_playing = 1;
    while (movie_playing) func_800127C8(1);
}
X4API int x4_movie_request(void) { int m = movie_req; movie_req = -1; return m; }
X4API void x4_movie_done(void) { movie_playing = 0; }

// ------------------------------------------------------------------ ligação com o Godot
extern void godot_boot(void);
extern void godot_frame(void);

static void game_main(void)
{
    godot_boot();
    for (;;) {
        co_switch(&game_co.sp, &host_sp);
        godot_frame();
    }
}

X4API int x4_start(const unsigned char* disc_data, size_t size, const char* env)
{
    { extern int x4_state_reset(void); x4_state_reset(); }   // tudo do jogo volta ao estado inicial
    disc = disc_data;
    disc_size = size;
    size_t n = 0;
    // "A=1;B=2" -> lista com zeros
    for (const char* p = env; p && *p && n < sizeof(env_buf) - 2; p++) env_buf[n++] = *p == ';' ? 0 : *p;
    env_buf[n++] = 0; env_buf[n] = 0;
    Psyz_SpuInit();
    game_co.stack = main_stack;
    game_co.size = STACK_SIZE;
    co_init(&game_co, game_main);
    co_resume(&host_sp, &game_co);   // roda a inicialização até o primeiro quadro
    return game_failed ? -1 : 0;
}

int fg_armor;   // fangame: armadura de outro jogo (1 Falcon X5, 2 Gaea, 3 Fourth X5, 4 Ultimate X5, 5 Falcon X6, 6 Blade, 7 Shadow, 8 Ultimate X6)
int x4_pl_frame, x4_pl_x, x4_pl_y, x4_pl_flip, x4_pl_drawn;   // preenchidos ao desenhar o X (placeholder.c)
X4API int x4_frame(unsigned b)
{
    x4_pl_drawn = 0;
    if (game_failed) return -1;
    { extern int fg_nz_block_input(void); if (fg_nz_block_input()) b = 0; }   // Giga do Nightmare Zero: o Zero não obedece
    buttons = b;
    vsync_count++;
    if (xa_playing) xa_pos2 += 5;
    if (vsync_cb) vsync_cb();
    prims_len = 0;
    co_resume(&host_sp, &game_co);
    { extern void fg_zero_track(void); fg_zero_track(); }   // fangame: desafios do Zero
    if (getenv("X4_DEBUG") && vsync_count % 30 == 0) {
        fprintf(stderr, "q%d gi=%d/%d/%d eng=%d/%d/%d/%d stage=%d/%d xa=%d cd=%d/%d th=%d,%d,%d,%d\n", vsync_count,
            game_info.unk0, game_info.mode, game_info.unk2, engine_obj.state, engine_obj.unk1, engine_obj.unk2, engine_obj.unk3,
            engine_obj.stage, engine_obj.substage, D_80173C84, cd_reading, cd_lba,
            game_threads[0].state, game_threads[1].state, game_threads[2].state, game_threads[3].state);
        extern s32 D_80139530, D_80141BD4, D_80139544, D_80139540;
        fprintf(stderr, "   pl act=%d st=%d/%d/%d xy=%d,%d bd=%d ud=%d vy=%d gl=%d eng1=%d\n", g_Player.active, g_Player.state, g_Player.unk5, g_Player.unk6, g_Player.x_pos.i.hi, g_Player.y_pos.i.hi, g_Player.beam_in_delay, g_Player.update_delay, g_Player.y_vel.val, engine_obj.gameplay_locked, engine_obj.unk1);
        fprintf(stderr, "   xa st=%d bd4=%d ini=%d fim=%d pos=%d last=%x playing=%d\n", D_80139530, D_80141BD4, D_80139540, D_80139544, xa_pos2 / 2, cd_last, xa_playing);
    }
    { extern int fg_fly_on, fg_giga_on; if (g_Player.spike_immune == 2 && !(fg_fly_on && g_Player.unk5 == PLAYER_HOVER) && !(fg_giga_on && g_Player.unk5 == PLAYER_NOVA_STRIKE)) g_Player.spike_immune = 0; }   // fangame: fim do voo da Falcon por qualquer caminho
    return game_failed ? -1 : 0;
}

X4API const u32* x4_prims(int* n) { *n = prims_len; return prims; }
X4API const u16* x4_vram(int* dirty)
{
    *dirty = vram_draw_dirty;
    vram_draw_dirty = 0;
    return vram_draw;
}
X4API const char* x4_log(void) { return log_buf; }
X4API void x4_log_clear(void) { log_len = 0; log_buf[0] = 0; }

// mem: no X4 compilado os "endereços" são campos do jogo (0 estado, 1 subestado, 2 fase, 3 subfase, 4 personagem, 5 modo, 6 unk2, 7 vidas? reservado)
X4API long long x4_mem(unsigned addr, long long value, int size)
{
    u8* f = 0;
    if (addr >= 100 && addr < 100 + 4 * 16) { extern int fg_obj_query(int, int); return fg_obj_query((addr - 100) / 4, (addr - 100) % 4); }
    if (addr >= 0x1F900790u && addr < 0x1F900800u) { extern long long fg_nz_query(unsigned, long long, int); return fg_nz_query(addr, value, size); }   // Nightmare Zero (as do X5/X6)
    if (addr >= 0x1F900900u && addr < 0x1F900A00u) { extern long long fg_coop_query(unsigned, long long, int); return fg_coop_query(addr, value, size); }   // co-op online (chefe, golpes)
    if (addr == 0xFFFFFF13) { extern void func_8001540C(s32, s32, void*); if (size < 0) func_8001540C((s32)(value >> 8) & 0xFF, (s32)value & 0xFF, NULL); return 0; }   // fangame: toca um som do X4 (tipo<<8 | id)
    if (addr == 0xFFFFFF12) { if (size < 0) g_Player.weapon_energy[0] = (s8)value; return g_Player.weapon_energy[0]; }   // teste: barra do giga
    if (addr == 0xFFFFFF10) { extern int fg_muzzle_dx; if (size < 0) fg_muzzle_dx = (int)value; return fg_muzzle_dx; }
    if (addr == 0xFFFFFF11) { extern int fg_muzzle_dy; if (size < 0) fg_muzzle_dy = (int)value; return fg_muzzle_dy; }
    switch (addr) {
    case 0: f = (u8*)&engine_obj.state; break;
    case 1: f = (u8*)&engine_obj.unk1; break;
    case 2: f = (u8*)&engine_obj.stage; break;
    case 3: f = (u8*)&engine_obj.substage; break;
    case 4: f = (u8*)&engine_obj.cur_character; break;
    case 5: f = (u8*)&game_info.mode; break;
    case 6: f = (u8*)&engine_obj.unk2; break;
    case 7: f = (u8*)&engine_obj.palette_flags; break;
    case 8: f = (u8*)&engine_obj.unkE; break;
    case 9: f = (u8*)&engine_obj.unk3; break;
    case 10: f = (u8*)&engine_obj.unk5F; break;
    // jogador (só leitura): quadro do sprite, direção, posição na tela, invencibilidade
    case 11: return x4_pl_frame;
    case 12: return x4_pl_flip;
    case 13: return x4_pl_x;
    case 14: return x4_pl_y;
    case 18: return x4_pl_drawn;
    case 19: { extern int fg_fly_on, fg_fly_frame, fg_giga_on, fg_giga_frame; if (fg_giga_on && g_Player.unk5 == PLAYER_NOVA_STRIKE) return fg_giga_frame; { extern int fg_nova_frame; if (fg_nova_frame >= 0 && g_Player.unk5 == PLAYER_NOVA_STRIKE) return fg_nova_frame; } { extern int fg_slash_frame; if (fg_slash_frame >= 0) return fg_slash_frame; } return (fg_fly_on && g_Player.unk5 == PLAYER_HOVER) ? fg_fly_frame : -1; }   // quadro do voo da Falcon (X5)
    case 21: if (size < 0) g_Player.hp = (s8)value; return g_Player.hp;   // escrita: testes
    case 40: case 41: case 42: case 43: case 44: case 45: case 46: case 47: case 48: case 49: { extern int fg_zst[10]; return fg_zst[addr - 40]; }   // desafios do Zero
    case 50: { extern void fg_zero_reset(void); fg_zero_reset(); return 0; }
    case 51: return g_Player.x_pos.i.hi;
    case 52: return g_Player.y_pos.i.hi;
    case 53: { extern int fg_bz_ad; return fg_bz_ad; }
    case 54: return g_Player.unk5;
    case 55: return g_Player.air_action;
    case 63: { extern int fg_kill_best; return fg_kill_best; }   // desafio de combo: melhor sequência
    case 70: case 71: case 72: case 73: case 74: case 75: case 76: case 77: case 78: case 79: case 80: case 81: case 82: case 83: case 84: case 85: case 86: case 87: { extern long long fg_hab_query(int); extern int fg_socorro_t; if (size < 0 && addr == 86) fg_socorro_t = (int)value; return fg_hab_query(addr - 70); }   // habilidades novas (escudo, marca)
    case 88: case 89: { extern void fg_test_hab(int); if (size < 0) fg_test_hab(addr - 88); return 0; }   // testes das habilidades
    case 62: { extern int fg_zero_pal(int); return fg_zero_pal((int)value); }
    case 56: case 57: case 58: case 59: case 60: case 61: { extern int fg_bz_fx_query(int); return fg_bz_fx_query(addr - 56); }   // efeito do Giga do Black Zero
    case 36: { extern int fg_caps, fg_caps_new, fg_caps_worn; return fg_caps < 0 ? 0 : (fg_caps_new | (fg_caps_worn << 8)); }   // cápsulas pegas nesta fase
    case 35: {   // de qual peça vem o quadro especial (mem 19): 0 pernas, 1 braço, 2 corpo
        extern int fg_fly_on, fg_giga_on, fg_nova_frame, fg_slash_frame; extern int fg_fly_arm(void);
        if ((fg_giga_on || fg_nova_frame >= 0) && g_Player.unk5 == PLAYER_NOVA_STRIKE) return 2;
        if (fg_slash_frame >= 0) return 1;
        return fg_fly_arm() ? 1 : 0; }
    case 34: { extern int fg_sfx_pop(void); return fg_sfx_pop(); }   // sons do X5/X6 para o Godot (-1 = nada)
    case 30: if (size < 0) engine_obj.max_hp = (s8)value; return (u8)engine_obj.max_hp;   // save único do fangame (escrita: heart tanks de 3 em 3)
    case 31: return engine_obj.collected_upgrades;
    case 32: return (u8)engine_obj.palette_flags;
    case 33:
        if (size < 0) { engine_obj.sub_tanks[0] = (s8)(value & 0xFF); engine_obj.sub_tanks[1] = (s8)((value >> 8) & 0xFF); engine_obj.sub_tanks[2] = (s8)((value >> 16) & 0xFF); }
        return (u8)engine_obj.sub_tanks[0] | (u8)engine_obj.sub_tanks[1] << 8 | (u8)engine_obj.sub_tanks[2] << 16;
    case 25: { extern int fg_dbg; return fg_dbg; }
    case 28: { extern int fg_charge_fx; return fg_charge_fx; }   // partículas de carga do X5
    case 27: { extern int fg_flash; return fg_flash; }   // X piscando (paleta do X5)
    case 26: { extern int fg_giga_on, fg_giga_t, fg_fx_t; if (fg_fx_t >= 0 && g_Player.unk5 == PLAYER_HOVER) return fg_fx_t; return (fg_giga_on && g_Player.unk5 == PLAYER_NOVA_STRIKE) ? fg_giga_t : -1; }   // efeito do Giga (Gaea)
    case 23: { extern int fg_rel_t; return fg_rel_t; }   // anel de liberação da carga (X5)
    case 24: { extern int fg_obj_query(int, int); return fg_obj_query(9999, -1); }   // lança/raios da Falcon
    case 22: { int n = 0; for (int i = 0; i < (int)(sizeof(main_objects) / sizeof(main_objects[0])); i++) if (main_objects[i].active) n++; return n; }   // inimigos ativos
    case 20: { extern int fg_fly_on, fg_fly_fx; return (fg_fly_on && g_Player.unk5 == PLAYER_HOVER) ? fg_fly_fx : -1; }   // jato do voo
    case 15: return g_Player.invincibility_timer;
    case 16: return g_Player.active;
    case 17: return engine_obj.armor_parts;
    default: return 0;
    }
    if (size < 0) *f = (u8)value;
    return *f;
}
