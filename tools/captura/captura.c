// captura: o harness do psxcore com o núcleo junto (sem biblioteca separada), para Linux e Windows.
// Mesmos argumentos e variáveis do harness: captura NUCLEO(ignorado) BIOS "DISC=..." QUADROS "botao:a-b,..."
// captura desenha PASTA N1,N2,...: desenha as fotos (v_N.bin + p_N.bin) como o Godot no Mesa llvmpipe (desenho.c)
extern char psx_debug_pc[];
extern char psx_ram_ptr[];
extern char psx_rwatch[];
extern char psx_spu_debug[];
extern char psx_spu_ram[];
extern char x4_audio[];
extern char x4_frame[];
extern char x4_log[];
extern char x4_log_clear[];
extern char x4_movie_done[];
extern char x4_movie_request[];
extern char x4_prims[];
extern char x4_start[];
extern char x4_vram[];
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
int desenho_main(int argc, char** argv);   // desenho.c: as telas das fotos, sem placa de vídeo
int main(int argc, char** argv) {
    if (argc > 1 && strcmp(argv[1], "desenha") == 0) return desenho_main(argc, argv);
    (void)argv[1];   // (o núcleo vem junto: o 1º argumento só existe para ficar igual ao harness)
    int (*start)(const unsigned char*, size_t, const char*) = (void*)x4_start;
    int (*frame)(unsigned) = (void*)x4_frame;
    const unsigned* (*prims)(int*) = (void*)x4_prims;
    const unsigned short* (*vram)(int*) = (void*)x4_vram;
    const char* (*lg)(void) = (void*)x4_log;
    void (*lgc)(void) = (void*)x4_log_clear;
    unsigned (*dpc)(void) = (void*)psx_debug_pc;
    int (*mreq)(void) = (void*)x4_movie_request; void (*mdone)(void) = (void*)x4_movie_done;
    FILE* f = fopen(argv[2], "rb"); unsigned char* b = malloc(524288); fread(b, 1, 524288, f); fclose(f);
    { extern unsigned xa_fase_inicial; if (getenv("XA_FASE")) xa_fase_inicial = (unsigned)strtoul(getenv("XA_FASE"), 0, 10); }   // fase do XA (ver api.c)
    int r = start(b, 524288, argv[3]);
    printf("start=%d %s\n", r, lg()); lgc();
    int frames = atoi(argv[4]);
    const char* hold = argc > 5 ? argv[5] : "";
    clock_t t0 = clock();
    for (int i = 0; i < frames; i++) {
        unsigned bt = 0;
        // HOLD: "start:100-105,cross:..." bits psx: start 3, cross 14, right 5, left 7, up 4, down 6, square 15, circle 13, tri 12
        static char tmp[65536]; strcpy(tmp, hold);
        for (char* tok = strtok(tmp, ","); tok; tok = strtok(NULL, ",")) {
            char name[32]; int a, z;
            if (sscanf(tok, "%31[^:]:%d-%d", name, &a, &z) == 3 && i >= a && i <= z) {
                if (!strcmp(name, "start")) bt |= 1 << 3; else if (!strcmp(name, "cross")) bt |= 1 << 14;
                else if (!strcmp(name, "right")) bt |= 1 << 5; else if (!strcmp(name, "left")) bt |= 1 << 7;
                else if (!strcmp(name, "up")) bt |= 1 << 4; else if (!strcmp(name, "down")) bt |= 1 << 6;
                else if (!strcmp(name, "square")) bt |= 1 << 15; else if (!strcmp(name, "tri")) bt |= 1 << 12; else if (!strcmp(name, "circle")) bt |= 1 << 13;
                else if (name[0] == 'b' && name[1] >= '0' && name[1] <= '9') bt |= 1 << atoi(name + 1);
            }
        }
        if (getenv("POKE")) {   // POKE="d1c0c:0005:900-2000,..."
            unsigned char* (*ramp)(void) = (void*)psx_ram_ptr;
            static char t2[4096]; strcpy(t2, getenv("POKE"));
            for (char* tk = strtok(t2, ","); tk; tk = strtok(NULL, ",")) {
                unsigned a, v; int f0, f1;
                if (sscanf(tk, "%x:%x:%d-%d", &a, &v, &f0, &f1) == 4 && i >= f0 && i <= f1) { ramp()[a & 0x1FFFFF] = v; ramp()[(a + 1) & 0x1FFFFF] = v >> 8; }
            }
        }
        if (mreq() >= 0) { printf("[vídeo %d tocado no quadro %d]\n", mreq(), i); mdone(); }
        if (getenv("SPUDBG")) {   // SPUDBG="mascara_hex:cd_mudo:log_keyon"
            unsigned m; int c, k, f0 = 0, f1 = 1 << 30; void (*sd)(unsigned, int, int) = (void*)psx_spu_debug;
            if (sscanf(getenv("SPUDBG"), "%x:%d:%d:%d-%d", &m, &c, &k, &f0, &f1) >= 3) { sd(m, c, k && i >= f0 && i <= f1); if (k && i >= f0 && i <= f1) printf("[quadro %d]\n", i); } }
        if (getenv("SPUDUMP") && i == atoi(getenv("SPUDUMP"))) {   // RAM do SPU (512 KB) em DUMPDIR/spu_N.bin
            const unsigned char* (*sr)(void) = (void*)psx_spu_ram; char fn[256];
            sprintf(fn, "%s/spu_%d.bin", getenv("DUMPDIR") ? getenv("DUMPDIR") : "/tmp/psx", i); FILE* o = fopen(fn, "wb"); fwrite(sr(), 1, 512 * 1024, o); fclose(o); }
        if (getenv("RWATCH")) { unsigned lo, hi; int f0, f1; void (*rw)(unsigned, unsigned, unsigned) = (void*)psx_rwatch;
            if (sscanf(getenv("RWATCH"), "%x:%x:%d-%d", &lo, &hi, &f0, &f1) == 4) rw(lo, hi, i >= f0 && i <= f1); }
        frame(bt);
        if (getenv("AUDIO") && i >= atoi(getenv("AUDIO_FROM"))) {   // grava o som (44100 Hz estéreo 16 bits, cru)
            static FILE* af; const short* (*aud)(int) = (void*)x4_audio;
            if (!af) af = fopen(getenv("AUDIO"), "wb");
            int nsmp = getenv("AUDIO_POR") ? atoi(getenv("AUDIO_POR")) : (i % 3 == 0) ? 736 : 735;   // por quadro (padrão: 735/736)
            fwrite(aud(nsmp), 4, nsmp, af); fflush(af);
        }
        const char* l = lg(); if (*l) { printf("%s", l); lgc(); }
        if (i % 60 == 0) { int n; prims(&n); printf("[q%d pc=%08x palavras=%d]\n", i, dpc(), n); fflush(stdout); }
        if (getenv("OBJLOG")) {   // OBJLOG="9a0a0:0x160:2000-2300": bytes de um objeto por quadro (hex) em DUMPDIR/obj.txt
            unsigned a, n; int f0, f1; static FILE* of;
            if (sscanf(getenv("OBJLOG"), "%x:%x:%d-%d", &a, &n, &f0, &f1) == 4 && i >= f0 && i <= f1) {
                unsigned char* (*rp)(void) = (void*)psx_ram_ptr;
                if (!of) { char fn[256]; sprintf(fn, "%s/obj.txt", getenv("DUMPDIR") ? getenv("DUMPDIR") : "/tmp/psx"); of = fopen(fn, "w"); }
                fprintf(of, "%d ", i); for (unsigned k = 0; k < n; k++) fprintf(of, "%02x", rp()[(a + k) & 0x1FFFFF]); fprintf(of, "\n"); fflush(of);
            }
        }
        int na_lista = 0;   // DUMP_LIST="3303,3363,...": fotografa só esses quadros
        if (getenv("DUMP_LIST")) { static char tl[65536]; strcpy(tl, getenv("DUMP_LIST")); for (char* k = strtok(tl, ","); k; k = strtok(NULL, ",")) if (atoi(k) == i) na_lista = 1; }
        if (na_lista || (getenv("DUMP") && i % atoi(getenv("DUMP")) == 0 && i >= (getenv("DUMP_FROM") ? atoi(getenv("DUMP_FROM")) : 0))) {
            char fn[256]; int n, d;
            const unsigned* p = prims(&n); const unsigned short* v = vram(&d);
            sprintf(fn, "%s/v_%d.bin", getenv("DUMPDIR") ? getenv("DUMPDIR") : "/tmp/psx", i); FILE* o = fopen(fn, "wb"); fwrite(v, 2, 1024 * 512, o); fclose(o);
            if (!getenv("NORAM")) { unsigned char* (*rp)(void) = (void*)psx_ram_ptr; sprintf(fn, "%s/r_%d.bin", getenv("DUMPDIR") ? getenv("DUMPDIR") : "/tmp/psx", i); FILE* o2 = fopen(fn, "wb"); fwrite(rp(), 1, 2 << 20, o2); fclose(o2); }
            sprintf(fn, "%s/p_%d.bin", getenv("DUMPDIR") ? getenv("DUMPDIR") : "/tmp/psx", i); o = fopen(fn, "wb"); fwrite(p, 4, n, o); fclose(o);
        }
    }
        printf("ms/quadro %.3f\n", (double)(clock() - t0) * 1000.0 / CLOCKS_PER_SEC / frames);
}
