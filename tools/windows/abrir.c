// "Mega Man X Fusion.exe": abre o launcher (engine\godot.exe --path launcher) sem janela de console.
// Sem biblioteca C: só kernel32 e user32. Compilar: tools/windows/compilar.sh (clang + lld-link, no Linux).
typedef unsigned short wc;
typedef struct { unsigned long cb; wc *res, *desk, *tit; unsigned long x, y, xs, ys, xc, yc, fill, flags;
                 unsigned short show, cbres2; unsigned char *res2; void *in, *out, *err; } INICIO;
typedef struct { void *proc, *thread; unsigned long pid, tid; } PROC;
__declspec(dllimport) unsigned long __stdcall GetModuleFileNameW(void *m, wc *buf, unsigned long n);
__declspec(dllimport) int __stdcall CreateProcessW(const wc *app, wc *cmd, void *pa, void *ta, int herda,
                                                   unsigned long flags, void *env, const wc *dir, INICIO *si, PROC *pi);
__declspec(dllimport) int __stdcall CloseHandle(void *h);
__declspec(dllimport) unsigned long __stdcall GetFileAttributesW(const wc *p);
__declspec(dllimport) void __stdcall ExitProcess(unsigned code);
__declspec(dllimport) int __stdcall MessageBoxW(void *w, const wc *txt, const wc *tit, unsigned tipo);

void *memset(void *d, int c, unsigned long long n) { unsigned char *p = d; while (n--) *p++ = (unsigned char)c; return d; }

static int cat(wc *d, int i, const wc *s) { while (*s && i < 4090) d[i++] = *s++; d[i] = 0; return i; }

void inicio(void) {
    static wc pasta[2048], exe[4096], cmd[8192], lan[4096];
    unsigned long n = GetModuleFileNameW(0, pasta, 2048);
    while (n > 0 && pasta[n - 1] != L'\\') n--;
    if (n > 0) n--;            // tira a barra do fim
    pasta[n] = 0;
    int i = cat(exe, 0, pasta); cat(exe, i, L"\\engine\\godot.exe");
    i = cat(lan, 0, pasta); cat(lan, i, L"\\launcher\\project.godot");
    if (GetFileAttributesW(exe) == 0xFFFFFFFFu || GetFileAttributesW(lan) == 0xFFFFFFFFu) {
        MessageBoxW(0, L"N\u00e3o achei engine\\godot.exe ou a pasta launcher.\nExtraia o pacote inteiro (n\u00e3o abra de dentro do .zip).",
                    L"Mega Man X Fusion", 0x10);
        ExitProcess(1);
    }
    i = cat(cmd, 0, L"\""); i = cat(cmd, i, exe); i = cat(cmd, i, L"\" --path \""); i = cat(cmd, i, pasta); cat(cmd, i, L"\\launcher\"");
    INICIO si; memset(&si, 0, sizeof si); si.cb = sizeof si;
    PROC pi; memset(&pi, 0, sizeof pi);
    if (!CreateProcessW(exe, cmd, 0, 0, 0, 0, 0, pasta, &si, &pi)) {
        MessageBoxW(0, L"N\u00e3o consegui abrir o launcher (engine\\godot.exe).", L"Mega Man X Fusion", 0x10);
        ExitProcess(1);
    }
    CloseHandle(pi.proc); CloseHandle(pi.thread);
    ExitProcess(0);
}
