/* Codificador WebP do fangame: o mesmo caminho que o Pillow usa (Image.save(..., "WEBP", quality=Q, method=M)),
 * com a libwebp 1.6.0: configuração padrão, ARGB com alfa 255, WebPEncode e o pacote montado pelo WebPMux.
 * As aberturas das telas de seleção do PC do dono foram gravadas assim (qualidade 88, método 6): com este programa os
 * arquivos saem iguais byte a byte. Entrada: pontos RGB crus (largura x altura x 3).
 * uso: webpenc ENTRADA.rgb LARGURA ALTURA QUALIDADE METODO SAIDA.webp [ENTRADA SAIDA ...] */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "webp/encode.h"
#include "webp/mux.h"
#ifdef _WIN32
#include <windows.h>
#include <shellapi.h>
#endif

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

static int codifica(const char* ent, int w, int h, float q, int metodo, const char* sai)
{
    FILE* f = abre(ent, "rb");
    if (!f) { fprintf(stderr, "webpenc: não abri %s\n", ent); return 0; }
    size_t n = (size_t)w * h * 3;
    unsigned char* rgb = malloc(n);
    if (!rgb || fread(rgb, 1, n, f) != n) { fprintf(stderr, "webpenc: %s curto\n", ent); fclose(f); free(rgb); return 0; }
    fclose(f);
    WebPConfig config;
    if (!WebPConfigInit(&config)) return 0;
    config.lossless = 0; config.quality = q; config.alpha_quality = 100; config.method = metodo; config.exact = 0;
    if (!WebPValidateConfig(&config)) { fprintf(stderr, "webpenc: ajuste inválido\n"); return 0; }
    WebPPicture pic;
    if (!WebPPictureInit(&pic)) return 0;
    pic.width = w; pic.height = h; pic.use_argb = 1;
    if (!WebPPictureAlloc(&pic)) return 0;
    for (int y = 0; y < h; y++) {
        const unsigned char* s = rgb + (size_t)y * w * 3;
        uint32_t* d = pic.argb + (size_t)pic.argb_stride * y;
        for (int x = 0; x < w; x++) d[x] = (uint32_t)s[x * 3 + 2] | ((uint32_t)s[x * 3 + 1] << 8) | ((uint32_t)s[x * 3] << 16) | (0xffu << 24);
    }
    free(rgb);
    WebPMemoryWriter wr; WebPMemoryWriterInit(&wr);
    pic.writer = WebPMemoryWrite; pic.custom_ptr = &wr;
    int ok = WebPEncode(&config, &pic);
    WebPPictureFree(&pic);
    if (!ok) { fprintf(stderr, "webpenc: erro %d em %s\n", pic.error_code, ent); WebPMemoryWriterClear(&wr); return 0; }
    WebPData img = {wr.mem, wr.size}, out = {0};
    WebPMux* mux = WebPMuxNew();
    if (!mux) return 0;
    WebPMuxSetImage(mux, &img, 0);
    WebPMuxAssemble(mux, &out);
    WebPMuxDelete(mux);
    WebPMemoryWriterClear(&wr);
    FILE* o = abre(sai, "wb");
    if (!o || fwrite(out.bytes, 1, out.size, o) != out.size) { fprintf(stderr, "webpenc: não gravei %s\n", sai); if (o) fclose(o); WebPDataClear(&out); return 0; }
    fclose(o);
    WebPDataClear(&out);
    return 1;
}

int main(int argc0, char** argv0)
{
    int c = argc0; char** v = argv0;
#ifdef _WIN32
    int nw = 0; wchar_t** aw = CommandLineToArgvW(GetCommandLineW(), &nw);
    char** av = malloc(sizeof(char*) * (nw + 1)); c = nw;
    for (int i = 0; i < c; i++) { int n = WideCharToMultiByte(CP_UTF8, 0, aw[i], -1, 0, 0, 0, 0); av[i] = malloc(n); WideCharToMultiByte(CP_UTF8, 0, aw[i], -1, av[i], n, 0, 0); }
    v = av;
#endif
    if (c < 7 || (c - 5) % 2 != 0) { fprintf(stderr, "uso: webpenc ENTRADA.rgb LARGURA ALTURA QUALIDADE METODO SAIDA.webp [ENTRADA SAIDA ...]\n"); return 2; }
    int w = atoi(v[2]), h = atoi(v[3]), m = atoi(v[5]); float q = (float)atof(v[4]);
    if (!codifica(v[1], w, h, q, m, v[6])) return 1;
    for (int i = 7; i + 1 < c; i += 2) if (!codifica(v[i], w, h, q, m, v[i + 1])) return 1;
    return 0;
}
