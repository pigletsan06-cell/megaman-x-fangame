/* Captura pela recompilação do X6 (a biblioteca que o launcher já compila no PC do jogador).
 * Mesmo roteiro do harness que fez as fotos do PC do dono: entra na fase 1 com a armadura N, espera 300 quadros,
 * roda SEQ ("quadros:botões_hex,...") e grava, a cada quadro, o estado do X (estado.txt) e a tela (fNNN.ppm).
 * ESCONDE: 0 nada; 1 o X e os efeitos dele (paletas 7800 7843 780D-F 784A); 2 só o rastro (780D-F).
 * uso: captura_rc BIBLIOTECA "DISC=...;GAMEDIR=...;CARDDIR=..." ARMADURA ESCONDE PASTA SEQ [PPM_DE PPM_ATE [OPÇÕES]]
 * OPÇÕES (opcional, "chave=valor;..."): fase=N e area=N (em vez da fase 1); esconde=7948,794b (paletas em hexa, como
 * o recomp_hide_cluts: 0xF000|coluna/64 limita as seguintes a uma página); poke=t:endereço_hexa:valor:tamanho|...
 * (antes do quadro t; t = -1 em todo quadro); voo=dx, voo_de=t, voo_ate=t, caminho=x:y,x:y,... (de voo_de a voo_ate o X
 * anda dx por quadro e a altura sai do caminho; como no harness das fotos do PC do dono) */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#include <shellapi.h>
#include <direct.h>
#else
#include <dlfcn.h>
#include <unistd.h>
#endif

typedef int (*start_f)(const unsigned char*, size_t, const char*);
typedef int (*frame_f)(unsigned);
typedef long long (*mem_f)(unsigned, long long, int);
typedef const unsigned char* (*scr_f)(int*, int*);
typedef void (*hide_f)(const unsigned short*, int);
#define P 0x970A0

static FILE* abre(const char* caminho, const char* modo)
{
#ifdef _WIN32
    wchar_t wc[1024], wm[8];
    MultiByteToWideChar(CP_UTF8, 0, caminho, -1, wc, 1024);
    MultiByteToWideChar(CP_UTF8, 0, modo, -1, wm, 8);
    return _wfopen(wc, wm);
#else
    return fopen(caminho, modo);
#endif
}

static void* carrega(const char* caminho)
{
#ifdef _WIN32
    wchar_t wc[1024];
    MultiByteToWideChar(CP_UTF8, 0, caminho, -1, wc, 1024);
    /* a pasta da biblioteca entra na busca das dependências dela */
    return (void*)LoadLibraryExW(wc, NULL, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
#else
    return dlopen(caminho, RTLD_NOW | RTLD_LOCAL);
#endif
}

static void* simbolo(void* h, const char* n)
{
#ifdef _WIN32
    return (void*)GetProcAddress((HMODULE)h, n);
#else
    return dlsym(h, n);
#endif
}

static void sai(int c)
{
    fflush(stdout); fflush(stderr);
#ifdef _WIN32
    ExitProcess((UINT)c);   /* a thread do jogo ainda está rodando: sai sem esperar por ela */
#else
    _exit(c);
#endif
}

/* "chave=valor;..." → valor (cópia em buf) ou NULL */
static const char* opcao(const char* ops, const char* chave, char* buf, size_t n)
{
    if (!ops) return NULL;
    size_t k = strlen(chave);
    for (const char* p = ops; p && *p; ) {
        const char* fim = strchr(p, ';'); size_t len = fim ? (size_t)(fim - p) : strlen(p);
        if (len > k && strncmp(p, chave, k) == 0 && p[k] == '=') {
            size_t m = len - k - 1; if (m >= n) m = n - 1;
            memcpy(buf, p + k + 1, m); buf[m] = 0; return buf;
        }
        p = fim ? fim + 1 : NULL;
    }
    return NULL;
}

int main(int argc0, char** argv0)
{
    int c = argc0; char** v = argv0;
#ifdef _WIN32
    /* argumentos em UTF-8 (caminhos com acento) */
    int nw = 0; wchar_t** aw = CommandLineToArgvW(GetCommandLineW(), &nw);
    static char* av[16]; c = nw < 16 ? nw : 16;
    for (int i = 0; i < c; i++) { int n = WideCharToMultiByte(CP_UTF8, 0, aw[i], -1, 0, 0, 0, 0); av[i] = malloc(n); WideCharToMultiByte(CP_UTF8, 0, aw[i], -1, av[i], n, 0, 0); }
    v = av;
#endif
    if (c < 7) { fprintf(stderr, "uso: captura_rc BIBLIOTECA ENV ARMADURA ESCONDE PASTA SEQ [PPM_DE PPM_ATE]\n"); return 2; }
    void* h = carrega(v[1]);
    if (!h) { fprintf(stderr, "captura_rc: não abri a biblioteca %s\n", v[1]); return 3; }
    start_f st = (start_f)simbolo(h, "x4_start"); frame_f fr = (frame_f)simbolo(h, "x4_frame"); mem_f mem = (mem_f)simbolo(h, "x4_mem");
    scr_f sc = (scr_f)simbolo(h, "recomp_screen"); hide_f hd = (hide_f)simbolo(h, "recomp_hide_cluts");
    if (!st || !fr || !mem || !sc || !hd) { fprintf(stderr, "captura_rc: a biblioteca não tem as funções da captura\n"); return 3; }
    int arm = atoi(v[3]), esc = atoi(v[4]); const char* dir = v[5]; const char* q = v[6];
    /* a recompilação grava registros na pasta atual (psx_*.json): que fiquem na pasta da captura */
#ifdef _WIN32
    { wchar_t wd[1024]; MultiByteToWideChar(CP_UTF8, 0, dir, -1, wd, 1024); _wchdir(wd); }
#else
    if (chdir(dir) != 0) { fprintf(stderr, "captura_rc: pasta %s inacessível\n", dir); return 3; }
#endif
    int ppm_de = c > 7 ? atoi(v[7]) : 0, ppm_ate = c > 8 ? atoi(v[8]) : 1 << 30;
    const char* ops = c > 9 ? v[9] : NULL;
    static char ob[8][4096];
    const char* o_fase = opcao(ops, "fase", ob[0], sizeof ob[0]); const char* o_area = opcao(ops, "area", ob[1], sizeof ob[1]);
    const char* o_esc = opcao(ops, "esconde", ob[2], sizeof ob[2]); const char* o_poke = opcao(ops, "poke", ob[3], sizeof ob[3]);
    const char* o_voo = opcao(ops, "voo", ob[4], sizeof ob[4]); const char* o_vde = opcao(ops, "voo_de", ob[5], sizeof ob[5]);
    const char* o_vate = opcao(ops, "voo_ate", ob[6], sizeof ob[6]); const char* o_cam = opcao(ops, "caminho", ob[7], sizeof ob[7]);
    const int fase = o_fase ? atoi(o_fase) : 1, area = o_area ? atoi(o_area) : 0;
    if (st(0, 0, v[2]) != 0) { fprintf(stderr, "captura_rc: a recompilação não iniciou\n"); sai(4); }
    /* até a fase: aperta start (6 de cada 40 quadros) fora da escolha de fase; na escolha, fase 1 e a armadura */
    for (int lf = 0; lf < 4000; lf++) {
        int s = (int)mem(0xCCED0, 0, 1);
        if (s == 7 || s == 8) { mem(0xCCEDC, fase | (area << 8), -2); mem(0xCCF2E, arm, -1); }
        if (s == 10) break;
        fr((lf > 60 && lf % 40 < 6 && s != 7 && s != 8) ? 0x0008 : 0);
    }
    for (int i = 0; i < 300; i++) { mem(0xCCF2E, arm, -1); fr(0); }
    if (esc == 2) { static const unsigned short tc[] = {0x780D, 0x780E, 0x780F}; hd(tc, 3); }
    if (esc == 1) { static const unsigned short hc[] = {0x7800, 0x7843, 0x780D, 0x780E, 0x780F, 0x784A}; hd(hc, sizeof hc / 2); }
    if (o_esc) { static unsigned short hc2[80]; int nh = 0; const char* q2 = o_esc;
        while (*q2 && nh < 80) { hc2[nh++] = (unsigned short)strtoul(q2, (char**)&q2, 16); if (*q2 == ',') q2++; else if (*q2) break; }
        hd(hc2, nh); }
    static int seq[4096][2]; int n = 0;
    while (q && *q && n < 4096) {
        seq[n][0] = atoi(q); const char* d2 = strchr(q, ':'); if (!d2) break; q = d2 + 1;
        seq[n][1] = (int)strtol(q, (char**)&q, 16); n++; if (*q == ',') q++;
    }
    char fn[1200]; snprintf(fn, sizeof fn, "%s/estado.txt", dir); FILE* lg = abre(fn, "w");
    if (!lg) { fprintf(stderr, "captura_rc: não consegui escrever em %s\n", dir); sai(5); }
    int t = 0;
    int fx = -99999;
    for (int s = 0; s < n; s++) for (int i = 0; i < seq[s][0]; i++, t++) {
        /* (mesma ordem do harness das fotos: as escritas e o voo antes do quadro) */
        for (const char* pk = o_poke; pk && *pk; ) {
            int pt = atoi(pk); const char* c1 = strchr(pk, ':'); if (!c1) break; unsigned pa = (unsigned)strtoul(c1 + 1, 0, 16);
            const char* c2 = strchr(c1 + 1, ':'); if (!c2) break; long long pv = strtoll(c2 + 1, 0, 0); const char* c3 = strchr(c2 + 1, ':'); if (!c3) break;
            int psz = atoi(c3 + 1); if (pt == t || pt == -1) mem(pa, pv, -psz);
            pk = strchr(c3, '|'); if (pk) pk++;
        }
        if (o_voo && t >= (o_vde ? atoi(o_vde) : 0) && t < (o_vate ? atoi(o_vate) : 1 << 30)) {
            if (fx == -99999) fx = (int)mem(P + 0xA, 0, 2);
            fx += atoi(o_voo); mem(P + 0xA, fx, -2);
            if (o_cam) { int px0 = -1, py0 = 0, fy = -1; const char* fp = o_cam;   /* altura pela posição x (reta entre os pontos) */
                while (fp && *fp) { int px = atoi(fp); const char* cc = strchr(fp, ':'); if (!cc) break; int py = atoi(cc + 1);
                    if (fx <= px) { fy = px0 < 0 ? py : py0 + (py - py0) * (fx - px0) / (px - px0 ? px - px0 : 1); break; }
                    px0 = px; py0 = py; fy = py; fp = strchr(cc, ','); if (fp) fp++; }
                if (fy >= 0) mem(P + 0xE, fy, -2); }
        }
        fr(seq[s][1]);
        /* (as mesmas leituras, na mesma ordem, do harness original) */
        int bo = (int)mem(P + 0x14, 0, 1); unsigned ca = 0x971F8 + bo * 0x54;
        fprintf(lg, "%d %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld\n", t, mem(P + 5, 0, 1), mem(P + 6, 0, 1),
            mem(P + 0x47, 0, 1), mem(P + 0xA, 0, 2), mem(P + 0xE, 0, 2), mem(ca + 0xA, 0, 2), mem(ca + 0xE, 0, 2), mem(P + 0x15, 0, 1), mem(0x80000 + 0, 0, 1) * 0,
            mem(0x1F900000, 0, 4), mem(0x1F900001, 0, 4), mem(0x1F900002, 0, 4), mem(0x1F900100, 0, 4), mem(0x1F900110, 0, 4), mem(0x1F900112, 0, 4),
            mem(0x1F9000F0, 0, 4) * 0, mem(P + 0x7A, 0, 1));
        if (t >= ppm_de && t <= ppm_ate) {
            int w, hh; const unsigned char* px = sc(&w, &hh);
            snprintf(fn, sizeof fn, "%s/f%03d.ppm", dir, t);
            FILE* f = abre(fn, "wb");
            if (!f || !px) { fprintf(stderr, "captura_rc: sem tela no quadro %d\n", t); sai(6); }
            fprintf(f, "P6 %d %d 255\n", w, hh); fwrite(px, 1, (size_t)w * hh * 3, f); fclose(f);
        }
    }
    fclose(lg);
    printf("captura_rc: %d quadros\n", t);
    sai(0);
    return 0;
}
