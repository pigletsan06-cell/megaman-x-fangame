/* Contas da libm com o resultado da glibc (Linux) para as entradas da tabela; fora dela, a libm do sistema.
 * Ligado no ffmpeg do Windows com -Wl,--wrap=sin,... : a libvorbis e o reamostrador fazem as mesmas contas que
 * no PC do dono e o som sai igual. FUSION_MEMO=1 mostra, no fim, quantas contas ficaram fora da tabela. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "memo_tabela.h"

static int faltas;
static void conta_falta(int id, uint64_t a)
{
    faltas++;
    if (getenv("FUSION_MEMO") && faltas <= 20) fprintf(stderr, "memo: fora da tabela: função %d entrada 0x%llx\n", id, (unsigned long long)a);
}
static int acha(int id, uint64_t a, uint64_t b, uint64_t* r)
{
    int lo = 0, hi = MEMO_N - 1;
    while (lo <= hi) {
        int m = (lo + hi) / 2;
        const uint64_t* e = MEMO[m];
        int c = (e[0] != (uint64_t)id) ? (e[0] < (uint64_t)id ? -1 : 1) : (e[1] != a) ? (e[1] < a ? -1 : 1) : (e[2] != b) ? (e[2] < b ? -1 : 1) : 0;
        if (c == 0) { *r = e[3]; return 1; }
        if (c < 0) lo = m + 1; else hi = m - 1;
    }
    return 0;
}
static uint64_t bd(double x) { uint64_t u; memcpy(&u, &x, 8); return u; }
static double db(uint64_t u) { double x; memcpy(&x, &u, 8); return x; }
static uint64_t bf(float x) { uint32_t u; memcpy(&u, &x, 4); return u; }
static float fb(uint64_t u) { uint32_t v = (uint32_t)u; float x; memcpy(&x, &v, 4); return x; }

#define F1(nome, ID) \
    double __real_##nome(double); \
    double __wrap_##nome(double x) { uint64_t r; if (acha(ID, bd(x), 0, &r)) return db(r); conta_falta(ID, bd(x)); return __real_##nome(x); }
#define F2(nome, ID) \
    double __real_##nome(double, double); \
    double __wrap_##nome(double x, double y) { uint64_t r; if (acha(ID, bd(x), bd(y), &r)) return db(r); conta_falta(ID, bd(x)); return __real_##nome(x, y); }
F1(acos, M_ACOS) F1(asin, M_ASIN) F1(atan, M_ATAN) F1(cos, M_COS) F1(cosh, M_COSH) F1(exp, M_EXP) F1(exp2, M_EXP2)
F1(log, M_LOG) F1(log10, M_LOG10) F1(sin, M_SIN) F1(sinh, M_SINH) F1(tan, M_TAN) F1(tanh, M_TANH)
F2(atan2, M_ATAN2) F2(hypot, M_HYPOT) F2(pow, M_POW)
float __real_acosf(float);
float __wrap_acosf(float x) { uint64_t r; if (acha(M_ACOSF, bf(x), 0, &r)) return fb(r); conta_falta(M_ACOSF, bf(x)); return __real_acosf(x); }
void __real_sincos(double, double*, double*);
void __wrap_sincos(double x, double* s, double* c)
{
    uint64_t rs, rc;
    if (acha(M_SINCOS_S, bd(x), 0, &rs) && acha(M_SINCOS_C, bd(x), 0, &rc)) { *s = db(rs); *c = db(rc); return; }
    conta_falta(M_SINCOS_S, bd(x)); __real_sincos(x, s, c);
}
void __real_sincosf(float, float*, float*);
void __wrap_sincosf(float x, float* s, float* c)
{
    uint64_t rs, rc;
    if (acha(M_SINCOSF_S, bf(x), 0, &rs) && acha(M_SINCOSF_C, bf(x), 0, &rc)) { *s = fb(rs); *c = fb(rc); return; }
    conta_falta(M_SINCOSF_S, bf(x)); __real_sincosf(x, s, c);
}
static void __attribute__((destructor)) fim(void)
{
    if (getenv("FUSION_MEMO")) fprintf(stderr, "memo: %d conta(s) fora da tabela\n", faltas);
}

/* qsort estável (ordenação por intercalação), como o da glibc: com elementos iguais (a libvorbis ordena valores
 * absolutos, com muitos empates) a ordem sai igual à do Linux; o qsort do Windows não é estável. */
static void intercala(char* b, size_t n, size_t sz, int (*cmp)(const void*, const void*), char* t)
{
    if (n <= 1) return;
    size_t n1 = n / 2, n2 = n - n1;
    char* b1 = b; char* b2 = b + n1 * sz;
    intercala(b1, n1, sz, cmp, t); intercala(b2, n2, sz, cmp, t);
    char* o = t;
    while (n1 > 0 && n2 > 0) {
        if (cmp(b1, b2) <= 0) { memcpy(o, b1, sz); b1 += sz; n1--; }
        else { memcpy(o, b2, sz); b2 += sz; n2--; }
        o += sz;
    }
    if (n1 > 0) memcpy(o, b1, n1 * sz);
    memcpy(b, t, (n - n2) * sz);
}
void __wrap_qsort(void* base, size_t n, size_t sz, int (*cmp)(const void*, const void*))
{
    if (n <= 1 || sz == 0) return;
    char* t = malloc(n * sz);
    if (!t) { void __real_qsort(void*, size_t, size_t, int (*)(const void*, const void*)); __real_qsort(base, n, sz, cmp); return; }
    intercala((char*)base, n, sz, cmp, t);
    free(t);
}
