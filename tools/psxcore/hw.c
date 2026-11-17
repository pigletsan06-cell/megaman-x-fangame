// Hardware do PS1: interrupções, timers, DMA, GPU (alto nível), CD-ROM, controle (SIO0), SPU (psyz)
#include "psx.h"

void Psyz_SpuWrite(unsigned int reg_offset, unsigned short value);
unsigned short Psyz_SpuRead(unsigned int reg_offset);
void Psyz_SpuMemWrite(unsigned int offset, const void* src, unsigned int size);
void Psyz_SpuMemRead(unsigned int offset, void* dst, unsigned int size);
unsigned int Psyz_SpuGetTransferAddr(void);
void Psyz_SpuSetTransferAddr(unsigned int addr);

static inline u32 ram32(u32 a) { u8* p = psx_ram + (a & 0x1FFFFC); return p[0] | p[1] << 8 | p[2] << 16 | (u32)p[3] << 24; }
int cd_lba_dbg(void);
extern u32 watch_addr;
static inline void ram32w(u32 a, u32 v) { if (watch_addr && (a & 0x1FFFFC) == watch_addr) psx_log("[dma escreve %x = %x lba=%d]\n", a, v, cd_lba_dbg()); u8* p = psx_ram + (a & 0x1FFFFC); p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }

// ------------------------------------------------------------------ interrupções
u32 i_stat, i_mask;
void irq_raise(int n) { i_stat |= 1u << n; }

// ------------------------------------------------------------------ timers
static struct { u32 count, mode, target; u32 acc; int fired; } tmr[3];
static u32 hblank_acc;
static void timer_irq(int n)
{
    if (!(tmr[n].mode & 0x40) && tmr[n].fired) return;   // um disparo só
    tmr[n].fired = 1;
    if (tmr[n].mode & 0x80) tmr[n].mode ^= 0x400; else tmr[n].mode &= ~0x400;
    irq_raise(4 + n);
    if (!(tmr[n].mode & 0x80)) tmr[n].mode |= 0x400;
}
static void timer_add(int n, u32 ticks)
{
    // pula direto até o próximo evento (alvo ou volta a zero) em vez de contar de 1 em 1
    while (ticks) {
        u32 c = tmr[n].count;
        u32 dt = (tmr[n].target - c) & 0xFFFF; if (dt == 0) dt = 0x10000;
        u32 dw = 0x10000 - c;
        u32 step = dt < dw ? dt : dw;
        if (ticks < step) { tmr[n].count = (c + ticks) & 0xFFFF; return; }
        ticks -= step;
        tmr[n].count = (c + step) & 0xFFFF;
        if (tmr[n].count == tmr[n].target) {
            tmr[n].mode |= 0x800;
            if (tmr[n].mode & 0x10) timer_irq(n);
            if (tmr[n].mode & 0x08) { tmr[n].count = 0; continue; }
        }
        if (tmr[n].count == 0) {
            tmr[n].mode |= 0x1000;
            if (tmr[n].mode & 0x20) timer_irq(n);
        }
    }
}
void timers_tick(int cyc)
{
    // T0: relógio do sistema (ou de pontos ~ sys/5)
    u32 src0 = (tmr[0].mode >> 8) & 3;
    if (src0 & 1) { tmr[0].acc += cyc; u32 t = tmr[0].acc / 5; tmr[0].acc %= 5; if (t) timer_add(0, t); }
    else timer_add(0, cyc);
    // T1: sistema ou hblank
    u32 src1 = (tmr[1].mode >> 8) & 3;
    hblank_acc += cyc;
    u32 hb = hblank_acc / 2172; hblank_acc %= 2172;
    if (src1 & 1) { if (hb) timer_add(1, hb); }
    else timer_add(1, cyc);
    // T2: sistema ou sistema/8
    u32 src2 = (tmr[2].mode >> 8) & 3;
    if (src2 & 2) { tmr[2].acc += cyc; u32 t = tmr[2].acc / 8; tmr[2].acc %= 8; if (t) timer_add(2, t); }
    else timer_add(2, cyc);
}

// ------------------------------------------------------------------ GPU em alto nível
u16 vram[1024 * 512];
u16 vram_draw[1024 * 512];
int vram_draw_dirty = 1;
static int vram_dirty = 1;
u32 prim_stream[1 << 18];
int prim_len;
static u32 cmd_buf[16];
static int cmd_len, cmd_need;
static int poly_line;
static int xfer_w, xfer_h, xfer_x, xfer_y, xfer_i, xfer_n, xfer_mode;  // 1: CPU->VRAM, 2: VRAM->CPU
static s32 off_x, off_y, area_x0, area_y0, area_x1, area_y1;
static u32 e1_state;
static u32 gpustat_extra;
static int disp_x, disp_y;
static int disp_24;
static int disp_w = 320, disp_h = 240;
int disp_written;
int gpu_drew;   // houve desenho neste quadro
int xfer_log;

static int cmd_size(u32 c)
{
    u32 op = c >> 24;
    if (op >= 0x20 && op < 0x40) {
        int n = (op & 8) ? 4 : 3, tex = (op & 4) ? 1 : 0, gour = (op & 0x10) ? 1 : 0;
        return 1 + n * (1 + tex) + (gour ? n - 1 : 0);
    }
    if (op >= 0x40 && op < 0x60) {
        if (op & 8) return -1;   // polilinha: até o terminador
        return (op & 0x10) ? 4 : 3;
    }
    if (op >= 0x60 && op < 0x80) {
        int sz = (op >> 3) & 3, tex = (op & 4) ? 1 : 0;
        return 2 + tex + (sz == 0 ? 1 : 0);
    }
    if (op >= 0x80 && op < 0xA0) return 4;
    if (op >= 0xA0 && op < 0xC0) return 3;
    if (op >= 0xC0 && op < 0xE0) return 3;
    if (op == 0x02) return 3;
    return 1;
}

static u32 rel_xy(u32 w)
{
    s32 x = ((s32)(w << 21)) >> 21, y = ((s32)(w << 5)) >> 21;
    x += off_x - area_x0;
    y += off_y - area_y0;
    return ((u32)x & 0xFFFF) | (((u32)y & 0xFFFF) << 16);
}

static void emit(const u32* w, int n)
{
    if (prim_len + n + 1 >= (int)(sizeof(prim_stream) / 4)) return;
    prim_stream[prim_len++] = (u32)n;
    for (int i = 0; i < n; i++) prim_stream[prim_len++] = w[i];
}

void gpu_vram_snapshot(void);
static void draw_command(void)
{
    u32 op = cmd_buf[0] >> 24;
    u32 out[16];
    int n = cmd_len;
    memcpy(out, cmd_buf, n * 4);
    // a imagem da VRAM usada nos desenhos deste quadro é a do momento do primeiro desenho
    // (o jogo costuma mandar os quadros de animação do próximo quadro logo depois de desenhar)
    if (!gpu_drew) { gpu_vram_snapshot(); gpu_drew = 1; }
    if (op >= 0x20 && op < 0x40) {
        int nv = (op & 8) ? 4 : 3, tex = (op & 4) ? 1 : 0, gour = (op & 0x10) ? 1 : 0;
        int i = 1;
        for (int k = 0; k < nv; k++) {
            if (k > 0 && gour) i++;
            out[i] = rel_xy(out[i]); i++;
            if (tex) i++;
        }
        emit(out, n);
    } else if (op >= 0x60 && op < 0x80) {
        out[1] = rel_xy(out[1]);
        emit(out, n);
    } else if (op >= 0x40 && op < 0x60) {
        // linhas: viram retângulos finos (aproximação)
        int gour = (op & 0x10) ? 1 : 0;
        int i = 1;
        u32 c0 = out[0] & 0xFFFFFF, p0 = out[i++];
        if (gour) i++;
        u32 p1 = out[i];
        s32 x0 = ((s32)(p0 << 21)) >> 21, y0 = ((s32)(p0 << 5)) >> 21;
        s32 x1 = ((s32)(p1 << 21)) >> 21, y1 = ((s32)(p1 << 5)) >> 21;
        u32 q[5];
        q[0] = 0x28000000 | c0 | (op & 2 ? 0x02000000 : 0);
        s32 dx = x1 - x0, dy = y1 - y0;
        s32 ox = (dy < 0 ? -dy : dy) >= (dx < 0 ? -dx : dx) ? 1 : 0, oy = ox ? 0 : 1;
        q[1] = rel_xy(((u32)x0 & 0x7FF) | (((u32)y0 & 0x7FF) << 16));
        q[2] = rel_xy(((u32)(x1) & 0x7FF) | (((u32)(y1) & 0x7FF) << 16));
        q[3] = rel_xy(((u32)(x0 + ox) & 0x7FF) | (((u32)(y0 + oy) & 0x7FF) << 16));
        q[4] = rel_xy(((u32)(x1 + ox) & 0x7FF) | (((u32)(y1 + oy) & 0x7FF) << 16));
        emit(q, 5);
    }
}

static void vram_fill(void)
{
    u32 c = cmd_buf[0];
    u16 v = ((c >> 3) & 31) | (((c >> 11) & 31) << 5) | (((c >> 19) & 31) << 10);
    int x = cmd_buf[1] & 0x3F0, y = (cmd_buf[1] >> 16) & 0x1FF;
    int w = ((cmd_buf[2] & 0x3FF) + 15) & ~15, h = (cmd_buf[2] >> 16) & 0x1FF;
    for (int j = 0; j < h; j++)
        for (int i = 0; i < w; i++) vram[((y + j) & 511) * 1024 + ((x + i) & 1023)] = v;
    vram_dirty = 1;
    // se cai na área de desenho, também vira um retângulo na tela (limpeza do fundo)
    if (x < area_x1 && x + w > area_x0 && y < area_y1 && y + h > area_y0) {
        u32 r[3];
        r[0] = 0x60000000 | (c & 0xFFFFFF);
        r[1] = (u32)((x - area_x0) & 0xFFFF) | ((u32)((y - area_y0) & 0xFFFF) << 16);
        r[2] = (u32)w | ((u32)h << 16);
        if (!gpu_drew) { gpu_vram_snapshot(); gpu_drew = 1; }
        emit(r, 3);
    }
}

void gpu_vram_snapshot(void)
{
    if (vram_dirty) {
        memcpy(vram_draw, vram, sizeof(vram));
        vram_dirty = 0;
        vram_draw_dirty = 1;
    }
}

void gpu_gp0(u32 w)
{
    if (xfer_mode == 1) {
        for (int k = 0; k < 2 && xfer_i < xfer_n; k++, xfer_i++) {
            int px = xfer_x + xfer_i % xfer_w, py = xfer_y + xfer_i / xfer_w;
            vram[(py & 511) * 1024 + (px & 1023)] = (u16)(k ? (w >> 16) : w);
        }
        vram_dirty = 1;
        if (xfer_i >= xfer_n) xfer_mode = 0;
        return;
    }
    if (poly_line) {
        if ((w & 0xF000F000) == 0x50005000) { poly_line = 0; cmd_len = 0; return; }
        // segmento: último vértice + novo
        u32 op = cmd_buf[0] >> 24;
        int gour = (op & 0x10) ? 1 : 0;
        if (gour) {
            if (poly_line == 1) { cmd_buf[3] = w; poly_line = 2; return; }   // cor
            cmd_buf[4] = w;
            u32 seg[5] = { cmd_buf[0], cmd_buf[2], cmd_buf[3], w };
            memcpy(cmd_buf, seg, 16); cmd_len = 4;
            draw_command();
            cmd_buf[1] = cmd_buf[2]; cmd_buf[2] = w; poly_line = 1;
            return;
        }
        u32 seg[3] = { cmd_buf[0], cmd_buf[2], w };
        memcpy(cmd_buf, seg, 12); cmd_len = 3;
        draw_command();
        cmd_buf[2] = w;
        return;
    }
    if (cmd_len == 0) {
        u32 op = w >> 24;
        if (op == 0x00 || op == 0x01 || (op >= 0x03 && op < 0x20)) return;
        if (op >= 0xE1 && op <= 0xE6) {
            switch (op) {
            case 0xE1: e1_state = w; emit(&w, 1); break;
            case 0xE3: area_x0 = w & 0x3FF; area_y0 = (w >> 10) & 0x3FF; break;
            case 0xE4: area_x1 = (w & 0x3FF) + 1; area_y1 = ((w >> 10) & 0x3FF) + 1; break;
            case 0xE5: off_x = ((s32)(w << 21)) >> 21; off_y = ((s32)(w << 10)) >> 21; break;
            default: break;
            }
            return;
        }
        cmd_need = cmd_size(w);
        if (cmd_need < 0) {   // polilinha
            cmd_buf[0] = w; cmd_len = 1;
            cmd_need = (op & 0x10) ? 4 : 3;
        }
    }
    cmd_buf[cmd_len++] = w;
    if (cmd_len < cmd_need) return;
    u32 op = cmd_buf[0] >> 24;
    if (op >= 0x40 && op < 0x60 && (op & 8)) {
        draw_command();
        poly_line = 1;
        if (op & 0x10) cmd_buf[2] = cmd_buf[3];
        cmd_len = 0;
        return;
    }
    if (op == 0x02) { cmd_len = 0; vram_fill(); return; }
    if (op >= 0x20 && op < 0x80) { draw_command(); cmd_len = 0; return; }
    cmd_len = 0;
    if (op >= 0x80 && op < 0xA0) {
        int sx = cmd_buf[1] & 0x3FF, sy = (cmd_buf[1] >> 16) & 0x1FF;
        int dx = cmd_buf[2] & 0x3FF, dy = (cmd_buf[2] >> 16) & 0x1FF;
        int ww = cmd_buf[3] & 0xFFFF, hh = cmd_buf[3] >> 16;
        ww = ((ww - 1) & 0x3FF) + 1; hh = ((hh - 1) & 0x1FF) + 1;
        for (int j = 0; j < hh; j++)
            for (int i = 0; i < ww; i++)
                vram[((dy + j) & 511) * 1024 + ((dx + i) & 1023)] = vram[((sy + j) & 511) * 1024 + ((sx + i) & 1023)];
        vram_dirty = 1;
        return;
    }
    if (op >= 0xA0 && op < 0xE0) {
        xfer_x = cmd_buf[1] & 0x3FF; xfer_y = (cmd_buf[1] >> 16) & 0x1FF;
        xfer_w = cmd_buf[2] & 0xFFFF; xfer_h = cmd_buf[2] >> 16;
        xfer_w = ((xfer_w - 1) & 0x3FF) + 1; xfer_h = ((xfer_h - 1) & 0x1FF) + 1;
        xfer_n = xfer_w * xfer_h; xfer_i = 0;
        xfer_mode = (op < 0xC0) ? 1 : 2;
        { extern int xfer_log; if (xfer_log && op < 0xC0) psx_log("[xfer %d,%d %dx%d drew=%d prims=%d]\n", xfer_x, xfer_y, xfer_w, xfer_h, gpu_drew, prim_len); }
        if (op < 0xC0 && xfer_x < disp_x + disp_w * (disp_24 ? 3 : 2) / 2 && xfer_x + xfer_w > disp_x && xfer_y < disp_y + disp_h && xfer_y + xfer_h > disp_y) disp_written = 1;
        return;
    }
}

u32 gpu_read(void)
{
    if (xfer_mode == 2) {
        u32 v = 0;
        for (int k = 0; k < 2 && xfer_i < xfer_n; k++, xfer_i++) {
            int px = xfer_x + xfer_i % xfer_w, py = xfer_y + xfer_i / xfer_w;
            v |= (u32)vram[(py & 511) * 1024 + (px & 1023)] << (k * 16);
        }
        if (xfer_i >= xfer_n) xfer_mode = 0;
        return v;
    }
    return 0;
}

static u32 field_bit;
u32 gpu_stat(void)
{
    // pronto para comandos, para enviar/receber VRAM e para DMA
    u32 s = 0x1C000000 | (e1_state & 0x7FF) | gpustat_extra;
    s |= field_bit;
    return s;
}
void gpu_gp1(u32 w)
{
    switch (w >> 24) {
    case 0x00: cmd_len = 0; xfer_mode = 0; poly_line = 0; gpustat_extra = 0x00800000; break;
    case 0x01: cmd_len = 0; xfer_mode = 0; poly_line = 0; break;
    case 0x03: gpustat_extra = (gpustat_extra & ~0x00800000) | ((w & 1) << 23); break;
    case 0x04: gpustat_extra = (gpustat_extra & ~0x60000000) | ((w & 3) << 29); break;
    case 0x05: disp_x = w & 0x3FF; disp_y = (w >> 10) & 0x1FF; break;
    case 0x08: disp_24 = (w >> 4) & 1;
        { static const int hw_[4] = { 256, 320, 512, 640 }; disp_w = (w & 0x40) ? 368 : hw_[w & 3]; disp_h = (w & 4) ? 480 : 240; } gpustat_extra = (gpustat_extra & ~0x7F4000) | ((w & 0x3F) << 17) | ((w & 0x40) << 10) | ((w & 0x80) << 7); break;
    case 0x10: break;
    default: break;
    }
}
void gpu_frame_begin(void) { field_bit ^= 0x80000000; }
int gpu_display_info(int* x, int* y, int* w, int* h, int* is24) { *x = disp_x; *y = disp_y; *w = disp_w; *h = disp_h; *is24 = disp_24; return 0; }

// ------------------------------------------------------------------ CD-ROM
extern int xa_feed_sector(const u8* sec);   // som.c
extern void xa_reset_stream(void);
extern int xa_active;
static u8 cd_index, cd_ie = 0x1F, cd_if;
static u8 cd_param[16]; static int cd_nparam;
static u8 cd_resp[16]; static int cd_nresp, cd_rpos;
static u8 cd_mode, cd_stat = 0x02;
static int cd_setloc_lba, cd_lba;
static int cd_reading, cd_seek_pending;
static u8 cd_sector[2352];
static u8 cd_data[2352]; static int cd_dlen, cd_dpos;
static u8 cd_last_hdr[8];
static u8 cd_filter_file, cd_filter_chan;
static int cd_cmd = -1;
int cd_trace;
int st_int1, st_cmds, st_dma0, st_dma1, st_qfull, st_mdec_dec;
int cd_data_ready;
int cd_nparam_used;
static s32 cd_cmd_timer;           // até a primeira resposta
static s32 cd_second_timer; static int cd_second_cmd = -1;
static s32 cd_read_timer;
// fila de interrupções pendentes (o controlador entrega uma por vez)
static struct { u8 irq; u8 resp[16]; int n; } cd_q[8];
static int cd_qn;

static int bcd2i(u8 b) { return (b >> 4) * 10 + (b & 15); }
static u8 i2bcd(int v) { return (u8)((v / 10) << 4 | (v % 10)); }

static void cd_push_irq(u8 irq, const u8* r, int n)
{
    if (irq == 1) st_int1++;
    if (cd_qn >= 8) { st_qfull++; return; }
    cd_q[cd_qn].irq = irq;
    memcpy(cd_q[cd_qn].resp, r, n);
    cd_q[cd_qn].n = n;
    cd_qn++;
}
static void cd_deliver(void)
{
    if (cd_if || cd_qn == 0) return;
    cd_if = cd_q[0].irq;
    if (cd_trace) psx_log("[cd int%d r0=%x]\n", cd_if, cd_q[0].resp[0]);
    memcpy(cd_resp, cd_q[0].resp, cd_q[0].n);
    cd_nresp = cd_q[0].n; cd_rpos = 0;
    for (int i = 1; i < cd_qn; i++) cd_q[i - 1] = cd_q[i];
    cd_qn--;
    if (cd_if & cd_ie) irq_raise(2);
}
static void cd_int(u8 irq, const u8* r, int n) { cd_push_irq(irq, r, n); cd_deliver(); }
static void cd_stat_only(u8 irq) { u8 s = cd_stat; cd_int(irq, &s, 1); }

int cd_fast;   // 1: lê setores 8x mais rápido (só durante o carregamento do hub)
#define CD_SECTOR_CYCLES(mode) (((mode) & 0x80 ? 33868800 / 150 : 33868800 / 75) / (cd_fast > 1 ? cd_fast : 1))

int movie_abort;   // o próximo GetlocP faz o tocador do jogo desistir (o vídeo toca no Godot)
extern void psx_movie_check(int lba);
static void cd_start_read(void)
{
    cd_lba = cd_setloc_lba;
    psx_movie_check(cd_lba);
    cd_reading = 1;
    cd_stat = 0x22;
    cd_read_timer = CD_SECTOR_CYCLES(cd_mode) + (cd_fast ? 5000 : 20000);
}

static void cd_exec(int cmd)
{
    u8 r[16];
    switch (cmd) {
    case 0x01: cd_stat_only(3); break;   // GetStat
    case 0x02:   // Setloc
        cd_setloc_lba = bcd2i(cd_param[0]) * 4500 + bcd2i(cd_param[1]) * 75 + bcd2i(cd_param[2]) - 150;
        if (cd_trace) psx_log("[setloc %d]\n", cd_setloc_lba);
        cd_seek_pending = 1;
        cd_stat_only(3);
        break;
    case 0x03: cd_stat_only(3); break;   // Play (CD-DA): não usado
    case 0x06: case 0x1B:   // ReadN / ReadS
        cd_stat = 0x02;
        cd_stat_only(3);
        cd_start_read();
        xa_reset_stream();
        break;
    case 0x07: cd_stat = 0x02; cd_stat_only(3); cd_second_cmd = 0x07; cd_second_timer = 100000; break;
    case 0x08: cd_reading = 0; cd_stat = 0x02; cd_stat_only(3); cd_second_cmd = 0x08; cd_second_timer = 100000; break;
    case 0x09:   // Pause
        cd_stat_only(3);
        cd_reading = 0; cd_stat = 0x02;
        cd_second_cmd = 0x09; cd_second_timer = cd_mode & 0x80 ? 70000 : 35000;
        break;
    case 0x0A:   // Init
        cd_mode = 0x20; cd_reading = 0; cd_stat = 0x02;
        cd_stat_only(3);
        cd_second_cmd = 0x0A; cd_second_timer = 80000;
        break;
    case 0x0B: case 0x0C: cd_stat_only(3); break;   // Mute/Demute
    case 0x0D: cd_filter_file = cd_param[0]; cd_filter_chan = cd_param[1]; cd_stat_only(3); break;
    case 0x0E: cd_mode = cd_param[0]; cd_stat_only(3); break;
    case 0x0F: r[0] = cd_stat; r[1] = cd_mode; r[2] = 0; r[3] = cd_filter_file; r[4] = cd_filter_chan; cd_int(3, r, 5); break;
    case 0x10: memcpy(r, cd_last_hdr, 8); cd_int(3, r, 8); break;   // GetlocL
    case 0x11: {   // GetlocP
        int a = (cd_lba > 0 ? cd_lba - 1 : 0) + 150, rel = a - 150;   // último setor lido
        if (movie_abort) { movie_abort = 0; a = 150; rel = 0; }   // posição longe do vídeo: o tocador do jogo desiste
        r[0] = 1; r[1] = 1;
        r[2] = i2bcd(rel / 4500); r[3] = i2bcd((rel / 75) % 60); r[4] = i2bcd(rel % 75);
        r[5] = i2bcd(a / 4500); r[6] = i2bcd((a / 75) % 60); r[7] = i2bcd(a % 75);
        cd_int(3, r, 8);
        break;
    }
    case 0x13: r[0] = cd_stat; r[1] = 1; r[2] = 1; cd_int(3, r, 3); break;   // GetTN
    case 0x14: {   // GetTD
        int t = bcd2i(cd_param[0]);
        int lba = t == 0 ? disc_sectors : 0;
        int n = lba + 150;
        r[0] = cd_stat; r[1] = i2bcd(n / 4500); r[2] = i2bcd((n / 75) % 60);
        cd_int(3, r, 3);
        break;
    }
    case 0x15: case 0x16:   // SeekL / SeekP
        cd_reading = 0;
        cd_stat = 0x42; cd_stat_only(3);
        cd_lba = cd_setloc_lba;
        cd_second_cmd = cmd; cd_second_timer = 100000;
        break;
    case 0x19:   // Test
        if (cd_param[0] == 0x20) { r[0] = 0x94; r[1] = 0x09; r[2] = 0x19; r[3] = 0xC0; cd_int(3, r, 4); }
        else cd_stat_only(3);
        break;
    case 0x1A: cd_stat_only(3); cd_second_cmd = 0x1A; cd_second_timer = 40000; break;   // GetID
    case 0x1E: cd_stat_only(3); cd_second_cmd = 0x1E; cd_second_timer = 200000; break;   // ReadTOC
    default:
        r[0] = cd_stat | 1; r[1] = 0x40; cd_int(5, r, 2);
        break;
    }
}

static void cd_second(int cmd)
{
    u8 r[8];
    switch (cmd) {
    case 0x1A: r[0] = 0x02; r[1] = 0x00; r[2] = 0x20; r[3] = 0x00; r[4] = 'S'; r[5] = 'C'; r[6] = 'E'; r[7] = 'A'; cd_int(2, r, 8); break;
    case 0x15: case 0x16: cd_stat = 0x02; cd_stat_only(2); break;
    default: cd_stat_only(2); break;
    }
}

int cd_lba_dbg(void) { return cd_lba; }
static void cd_read_sector(void)
{
    disc_read_sector(cd_lba, cd_sector);
    memcpy(cd_last_hdr, cd_sector + 12, 8);
    cd_lba++;
    u8 sub = cd_sector[0x12], file = cd_sector[0x10], chan = cd_sector[0x11];
    if (cd_trace) psx_log("[setor %d sub=%x f=%d c=%d modo=%x dados=%02x%02x%02x%02x]\n", cd_lba - 1, sub, file, chan, cd_mode, cd_sector[24], cd_sector[25], cd_sector[26], cd_sector[27]);
    if ((cd_mode & 0x40) && (sub & 0x44) == 0x44) {
        // setor de música/voz XA
        if (!(cd_mode & 0x08) || (file == cd_filter_file && chan == cd_filter_chan)) xa_feed_sector(cd_sector);
        return;
    }
    if (cd_mode & 0x20) { memcpy(cd_data, cd_sector + 12, 0x924); cd_dlen = 0x924; }
    else { memcpy(cd_data, cd_sector + 24, 0x800); cd_dlen = 0x800; }
    cd_dpos = cd_dlen;   // só fica disponível depois do pedido (BFRD)
    cd_stat = 0x22;
    // perde-se um setor se a interrupção anterior não foi reconhecida (o jogo ainda processa)
    u8 s = cd_stat;
    cd_int(1, &s, 1);
}

void cd_tick(int cyc)
{
    if (cd_cmd >= 0) {
        cd_cmd_timer -= cyc;
        if (cd_cmd_timer <= 0) { int c = cd_cmd; cd_cmd = -1; cd_exec(c); }
    }
    if (cd_second_cmd >= 0) {
        cd_second_timer -= cyc;
        if (cd_second_timer <= 0) { int c = cd_second_cmd; cd_second_cmd = -1; cd_second(c); }
    }
    if (cd_reading) {
        cd_read_timer -= cyc;
        if (cd_read_timer <= 0) {
            // CD acelerado: só entrega o próximo setor quando o jogo já reconheceu o anterior
            if (cd_fast > 1 && (cd_if || cd_qn)) cd_read_timer = 2000;
            else { cd_read_timer += CD_SECTOR_CYCLES(cd_mode); if (cd_read_timer < 2000) cd_read_timer = 2000; cd_read_sector(); }
        }
    }
}

int st_cdr[4], st_cdw[16];
static u8 cd_read_reg(u32 a)
{
    st_cdr[a & 3]++;
    switch (a & 3) {
    case 0: {
        u8 s = cd_index;
        if (cd_nparam == 0) s |= 0x08;
        if (cd_nparam < 16) s |= 0x10;
        if (cd_rpos < cd_nresp) s |= 0x20;
        if (cd_dpos < cd_dlen && cd_data_ready) s |= 0x40;
        if (cd_cmd >= 0) s |= 0x80;
        return s;
    }
    case 1: { u8 v = cd_rpos < cd_nresp ? cd_resp[cd_rpos++] : 0; return v; }
    case 2: return cd_data_ready && cd_dpos < cd_dlen ? cd_data[cd_dpos++] : 0;
    case 3: return (cd_index & 1) ? (cd_if | 0xE0) : (cd_ie | 0xE0);
    }
    return 0;
}
static void cd_write_reg(u32 a, u8 v)
{
    int r = a & 3;
    st_cdw[r == 0 ? 0 : cd_index * 4 + r]++;
    if (r == 0) { cd_index = v & 3; return; }
    switch (cd_index * 4 + r) {
    case 1:   // comando
        if (cd_trace) psx_log("[cd cmd %x np=%d p0=%x ie=%x if=%x]\n", v, cd_nparam, cd_param[0], cd_ie, cd_if);
        st_cmds++;
        cd_cmd = v; cd_cmd_timer = (v == 0x0A) ? 60000 : 25000;
        cd_nresp = 0; cd_rpos = 0;
        cd_nparam_used = cd_nparam;
        cd_nparam = 0;
        break;
    case 2: if (cd_nparam < 16) cd_param[cd_nparam++] = v; break;
    case 3:   // pedido de dados
        if (cd_trace) psx_log("[cd req %x]\n", v);
        if (v & 0x80) { if (!cd_data_ready) { cd_data_ready = 1; cd_dpos = 0; } }
        else { cd_data_ready = 0; }
        break;
    case 6: cd_ie = v & 0x1F; if (cd_if & cd_ie) irq_raise(2); break;
    case 7:
        cd_if &= ~(v & 0x1F);
        if (v & 0x40) cd_nparam = 0;
        if (cd_if == 0) cd_deliver();
        break;
    default: break;
    }
}

// ------------------------------------------------------------------ controle (SIO0)
extern unsigned pad_buttons;
static u8 sio_rx; static int sio_rx_full;
static u16 sio_ctrl, sio_mode, sio_baud;
static int sio_stat_irq;
static int sio_step, sio_dev;   // passo do protocolo, dispositivo (1 controle, 2 cartão)
static s32 sio_ack_timer;
// cartão de memória (porta 1 do PS1 = índice 0): 128 KB, 1024 setores de 128 bytes
u8 card_data[0x20000];
int card_dirty;
static u8 card_flag = 0x08;   // bit 3: "cartão novo" até a primeira escrita
static u8 card_cmd, card_msb, card_lsb, card_sum, card_prev;
static int card_bad;
void card_format(void)
{
    memset(card_data, 0, sizeof(card_data));
    for (int f = 0; f < 64; f++) {
        u8* b = card_data + f * 128;
        if (f == 0 || f == 63) { b[0] = 'M'; b[1] = 'C'; }
        else if (f < 16) { b[0] = 0xA0; b[8] = 0xFF; b[9] = 0xFF; }
        else if (f < 36) { b[0] = b[1] = b[2] = b[3] = 0xFF; b[8] = 0xFF; b[9] = 0xFF; }
        u8 x = 0; for (int i = 0; i < 127; i++) x ^= b[i];
        b[127] = x;
    }
}
// devolve o byte recebido; *ack = 1 se o cartão confirma (há mais bytes)
static u8 card_byte(int step, u8 tx, int* ack)
{
    *ack = 1;
    if (step == 1) { card_cmd = tx; return card_flag; }
    switch (card_cmd) {
    case 'R':
        switch (step) {
        case 2: return 0x5A;
        case 3: return 0x5D;
        case 4: card_msb = tx; return 0x00;
        case 5: card_lsb = tx; card_bad = ((card_msb << 8) | card_lsb) > 0x3FF; return card_msb;
        case 6: return 0x5C;
        case 7: return 0x5D;
        case 8: card_sum = card_msb ^ card_lsb; return card_msb;
        case 9: return card_lsb;
        default:
            if (step < 10 + 128) {
                int a = (((card_msb << 8) | card_lsb) & 0x3FF) * 128 + (step - 10);
                u8 d = card_bad ? 0xFF : card_data[a];
                card_sum ^= d;
                return d;
            }
            if (step == 10 + 128) return card_sum;
            *ack = 0; return 0x47;
        }
    case 'W':
        switch (step) {
        case 2: return 0x5A;
        case 3: return 0x5D;
        case 4: card_msb = tx; card_prev = tx; return 0x00;
        case 5: card_lsb = tx; card_sum = card_msb ^ card_lsb; card_bad = ((card_msb << 8) | card_lsb) > 0x3FF; { u8 r = card_prev; card_prev = tx; return r; }
        default:
            if (step < 6 + 128) {
                int a = (((card_msb << 8) | card_lsb) & 0x3FF) * 128 + (step - 6);
                if (!card_bad) card_data[a] = tx;
                card_sum ^= tx;
                u8 r = card_prev; card_prev = tx; return r;
            }
            if (step == 6 + 128) { u8 r = card_prev; card_prev = tx; card_bad |= (tx != card_sum) ? 2 : 0; return r; }
            if (step == 7 + 128) return 0x5C;
            if (step == 8 + 128) return 0x5D;
            *ack = 0;
            if (card_bad & 1) return 0xFF;
            if (card_bad & 2) return 0x4E;
            card_flag &= ~0x08; card_dirty = 1;
            return 0x47;
        }
    case 'S':   // identificação
        { static const u8 id[] = { 0x5A, 0x5D, 0x5C, 0x5D, 0x04, 0x00, 0x00, 0x80 };
          if (step - 2 < 8) { if (step - 2 == 7) *ack = 0; return id[step - 2]; } }
        *ack = 0; return 0xFF;
    default:
        *ack = 0; return 0xFF;
    }
}
static void sio_transfer(u8 tx)
{
    int port = (sio_ctrl >> 13) & 1;
    u8 rx = 0xFF; int ack = 0;
    { extern int xfer_log; static int nlog; if (xfer_log > 1 && nlog < 400 && (sio_dev == 2 || tx == 0x81)) { nlog++; psx_log("<%d:%d:%02x ctrl=%x>", port, sio_step, tx, sio_ctrl); } }
    if (sio_step == 0) {
        if (tx == 0x01 && port == 0) { sio_dev = 1; ack = 1; }
        else if (tx == 0x81 && port == 0) { sio_dev = 2; ack = 1; }
        else sio_dev = 0;
        sio_step = 1;
    } else if (sio_dev == 1) {
        switch (sio_step) {
        case 1: rx = 0x41; ack = 1; break;
        case 2: rx = 0x5A; ack = 1; break;
        case 3: rx = (u8)~pad_buttons; ack = 1; break;
        case 4: rx = (u8)(~pad_buttons >> 8); ack = 0; break;
        default: rx = 0xFF; break;
        }
        sio_step++;
    } else if (sio_dev == 2) {
        rx = card_byte(sio_step, tx, &ack);
        { extern int xfer_log; if (xfer_log && !ack) psx_log("[cartão %x setor %d passos %d fim %x]\n", card_cmd, (card_msb << 8) | card_lsb, sio_step, rx); }
        if (!ack) sio_dev = 0;
        sio_step++;
    }
    sio_rx = rx; sio_rx_full = 1;
    if (ack) sio_ack_timer = 400;
}
void sio_tick(int cyc)
{
    if (sio_ack_timer > 0) {
        sio_ack_timer -= cyc;
        if (sio_ack_timer <= 0) {
            sio_stat_irq = 1;
            if (sio_ctrl & 0x1000) irq_raise(7);
        }
    }
}


// ------------------------------------------------------------------ MDEC (vídeos FMV)
static u32 mdec_cmd, mdec_ctrl;
static u16 mdec_in[0x40000]; static int mdec_in_n, mdec_in_need;   // meias-palavras
static u8 mdec_out[0x100000]; static int mdec_out_n, mdec_out_pos;
static u8 qt_y[64], qt_c[64];
static s16 scale_tbl[64];
static int mdec_param_mode;   // 0: nada, 1: decodificar, 2: tabela de quantização, 3: tabela de escala
static const u8 zz[64] = {
    0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63 };
static int mdec_rd;
static int mdec_block(s16* blk, const u8* qt)
{
    s32 c[64];
    for (int i = 0; i < 64; i++) c[i] = 0;
    u16 h;
    do { if (mdec_rd >= mdec_in_n) return 0; h = mdec_in[mdec_rd++]; } while (h == 0xFE00);
    int q = h >> 10;
    s32 n = ((s32)(h << 22)) >> 22;
    s32 v = q == 0 ? n * 2 : n * qt[0];
    c[0] = v < -0x400 ? -0x400 : v > 0x3FF ? 0x3FF : v;
    int k = 0;
    while (mdec_rd < mdec_in_n) {
        h = mdec_in[mdec_rd++];
        if (h == 0xFE00) break;
        k += (h >> 10) + 1;
        if (k > 63) break;
        n = ((s32)(h << 22)) >> 22;
        v = q == 0 ? n * 2 : (n * qt[k] * q + 4) / 8;
        c[zz[k]] = v < -0x400 ? -0x400 : v > 0x3FF ? 0x3FF : v;
    }
    // IDCT separável com a tabela de escala do jogo (2x a base ortonormal por passada)
    s32 t[64];
    for (int y = 0; y < 8; y++)
        for (int x = 0; x < 8; x++) {
            s64 sum = 0;
            for (int z = 0; z < 8; z++) sum += (s64)c[y * 8 + z] * scale_tbl[z * 8 + x];
            t[y * 8 + x] = (s32)(sum >> 16);
        }
    for (int x = 0; x < 8; x++)
        for (int y = 0; y < 8; y++) {
            s64 sum = 0;
            for (int z = 0; z < 8; z++) sum += (s64)t[z * 8 + x] * scale_tbl[z * 8 + y];
            s32 r = (s32)(sum >> 16);
            blk[y * 8 + x] = (s16)(r < -128 ? -128 : r > 127 ? 127 : r);
        }
    return 1;
}
static void mdec_decode(void)
{
    int depth = (mdec_cmd >> 27) & 3;
    int is_signed = (mdec_cmd >> 26) & 1;
    int stp = (mdec_cmd >> 25) & 1;
    mdec_rd = 0; mdec_out_n = 0; mdec_out_pos = 0; st_mdec_dec++;
    s16 cr[64], cb[64], yb[4][64];
    while (mdec_rd < mdec_in_n) {
        if (depth >= 2) {
            if (!mdec_block(cr, qt_c) || !mdec_block(cb, qt_c)) break;
            int ok = 1;
            for (int i = 0; i < 4 && ok; i++) ok = mdec_block(yb[i], qt_y);
            if (!ok) break;
            for (int py = 0; py < 16; py++)
                for (int px = 0; px < 16; px++) {
                    int yi = (py >> 3) * 2 + (px >> 3);
                    s32 Y = yb[yi][(py & 7) * 8 + (px & 7)];
                    s32 R = cr[(py >> 1) * 8 + (px >> 1)], B = cb[(py >> 1) * 8 + (px >> 1)];
                    s32 r = Y + ((359 * R) >> 8), g = Y - ((88 * B + 183 * R) >> 8), b = Y + ((454 * B) >> 8);
                    r = r < -128 ? -128 : r > 127 ? 127 : r; g = g < -128 ? -128 : g > 127 ? 127 : g; b = b < -128 ? -128 : b > 127 ? 127 : b;
                    if (!is_signed) { r += 128; g += 128; b += 128; }
                    if (mdec_out_n + 3 > (int)sizeof(mdec_out)) return;
                    if (depth == 3) {
                        u16 p = (u16)(((r & 0xFF) >> 3) | (((g & 0xFF) >> 3) << 5) | (((b & 0xFF) >> 3) << 10) | (stp << 15));
                        mdec_out[mdec_out_n++] = (u8)p; mdec_out[mdec_out_n++] = (u8)(p >> 8);
                    } else {
                        mdec_out[mdec_out_n++] = (u8)r; mdec_out[mdec_out_n++] = (u8)g; mdec_out[mdec_out_n++] = (u8)b;
                    }
                }
        } else {
            s16 y[64];
            if (!mdec_block(y, qt_y)) break;
            for (int i = 0; i < 64; i++) {
                s32 v = y[i] + (is_signed ? 0 : 128);
                if (depth == 1) mdec_out[mdec_out_n++] = (u8)v;
                else { if (i & 1) mdec_out[mdec_out_n - 1] |= (u8)((v >> 4) << 4); else mdec_out[mdec_out_n++] = (u8)(v >> 4); }
            }
        }
    }
}
static void mdec_word(u32 w)
{
    if (mdec_param_mode == 0) {
        mdec_cmd = w;
        int op = w >> 29;
        if (op == 1) { mdec_param_mode = 1; mdec_in_n = 0; mdec_in_need = (int)(w & 0xFFFF) * 2; }
        else if (op == 2) { mdec_param_mode = 2; mdec_in_n = 0; mdec_in_need = (w & 1) ? 64 : 32; }
        else if (op == 3) { mdec_param_mode = 3; mdec_in_n = 0; mdec_in_need = 64; }
        if (mdec_in_need == 0) mdec_param_mode = 0;
        return;
    }
    if (mdec_in_n + 2 <= (int)(sizeof(mdec_in) / 2)) { mdec_in[mdec_in_n++] = (u16)w; mdec_in[mdec_in_n++] = (u16)(w >> 16); }
    if (mdec_in_n < mdec_in_need) return;
    if (mdec_param_mode == 1) mdec_decode();
    else if (mdec_param_mode == 2) {
        const u8* b = (const u8*)mdec_in;
        for (int i = 0; i < 64; i++) qt_y[i] = b[i];
        if (mdec_in_need == 64) for (int i = 0; i < 64; i++) qt_c[i] = b[64 + i];
    } else if (mdec_param_mode == 3) {
        for (int i = 0; i < 64; i++) scale_tbl[i] = (s16)mdec_in[i];
    }
    mdec_param_mode = 0;
}
static u32 mdec_status(void)
{
    u32 s = 0;
    if (mdec_out_pos >= mdec_out_n) s |= 0x80000000;
    if (mdec_param_mode) s |= 0x20000000 | 0x10000000;
    if (mdec_out_pos < mdec_out_n) s |= 0x08000000 | 0x20000000;
    s |= ((mdec_cmd >> 25) & 0xF) << 23;
    int rem = mdec_param_mode ? (mdec_in_need - mdec_in_n) / 2 - 1 : -1;
    s |= (u32)rem & 0xFFFF;
    return s;
}
static u32 mdec_read_out(void)
{
    u32 v = 0;
    for (int k = 0; k < 4; k++) v |= (u32)(mdec_out_pos < mdec_out_n ? mdec_out[mdec_out_pos++] : 0) << (k * 8);
    return v;
}

// ------------------------------------------------------------------ DMA
static u32 dma_madr[7], dma_bcr[7], dma_chcr[7], dma_dpcr = 0x07654321, dma_dicr;
static void dma_done(int ch)
{
    dma_chcr[ch] &= ~0x11000000;
    if (dma_dicr & (1u << (16 + ch))) dma_dicr |= 1u << (24 + ch);
    u32 f = (dma_dicr >> 24) & (dma_dicr >> 16) & 0x7F;
    int master = (dma_dicr & 0x8000) || ((dma_dicr & 0x800000) && f);
    if (master && !(dma_dicr & 0x80000000)) { dma_dicr |= 0x80000000; irq_raise(3); }
}
static void dma_run(int ch)
{
    u32 chcr = dma_chcr[ch];
    u32 addr = dma_madr[ch] & 0x1FFFFC;
    int sync = (chcr >> 9) & 3;
    int from_ram = chcr & 1;
    int step = (chcr & 2) ? -4 : 4;
    u32 words = sync == 0 ? (dma_bcr[ch] & 0xFFFF ? dma_bcr[ch] & 0xFFFF : 0x10000) : (dma_bcr[ch] & 0xFFFF) * (dma_bcr[ch] >> 16);
    if (xfer_log >= 3 && ch != 4 && !(ch == 2 && sync == 2)) psx_log("[dma%d madr=%x palavras=%d sync=%d de_ram=%d]\n", ch, addr, words, sync, from_ram);
    if (ch == 2 && sync == 2) {   // lista ligada para a GPU
        int guard = 0;
        while (guard++ < 200000) {
            u32 hdr = ram32(addr);
            u32 n = hdr >> 24;
            for (u32 i = 0; i < n; i++) gpu_gp0(ram32(addr + 4 + i * 4));
            if (hdr & 0x800000) break;
            addr = hdr & 0x1FFFFC;
        }
        dma_done(ch);
        return;
    }
    if (ch == 6) {   // limpa a tabela de ordenação (de trás para frente)
        u32 n = dma_bcr[ch] & 0xFFFF; if (!n) n = 0x10000;
        for (u32 i = 0; i < n; i++) {
            ram32w(addr, i == n - 1 ? 0xFFFFFF : ((addr - 4) & 0x1FFFFF));
            addr -= 4;
        }
        dma_done(ch);
        return;
    }
    for (u32 i = 0; i < words; i++, addr = (addr + step) & 0x1FFFFC) {
        switch (ch) {
        case 2:
            if (from_ram) gpu_gp0(ram32(addr)); else ram32w(addr, gpu_read());
            break;
        case 3: {
            if (i == 0 && cd_trace) psx_log("[dma3 %d palavras dpos=%d]\n", words, cd_dpos);
            u32 v = 0;
            for (int k = 0; k < 4; k++) v |= (u32)(cd_dpos < cd_dlen ? cd_data[cd_dpos++] : 0) << (k * 8);
            ram32w(addr, v);
            break;
        }
        case 4: {
            unsigned ta = Psyz_SpuGetTransferAddr();
            if (from_ram) { u32 v = ram32(addr); Psyz_SpuMemWrite(ta, &v, 4); }
            else { u32 v; Psyz_SpuMemRead(ta, &v, 4); ram32w(addr, v); }
            Psyz_SpuSetTransferAddr(ta + 4);
            break;
        }
        case 0: if (i == 0) st_dma0++; if (from_ram) mdec_word(ram32(addr)); break;
        case 1: if (i == 0) st_dma1++; ram32w(addr, mdec_read_out()); break;
        default: break;
        }
    }
    dma_done(ch);
}
void dma_write(u32 a, u32 v)
{
    u32 off = a - 0x1F801080;
    int ch = off >> 4;
    if (ch == 7) {
        if ((off & 15) == 0) dma_dpcr = v;
        else if ((off & 15) == 4) {
            dma_dicr = (dma_dicr & 0xFF000000) & ~(v & 0x7F000000);
            dma_dicr |= v & 0x00FF803F;
            u32 f = (dma_dicr >> 24) & (dma_dicr >> 16) & 0x7F;
            if ((dma_dicr & 0x8000) || ((dma_dicr & 0x800000) && f)) dma_dicr |= 0x80000000; else dma_dicr &= ~0x80000000;
        }
        return;
    }
    switch (off & 15) {
    case 0: dma_madr[ch] = v & 0xFFFFFF; break;
    case 4: dma_bcr[ch] = v; break;
    case 8:
        dma_chcr[ch] = v;
        if ((v & 0x01000000) && (((v >> 9) & 3) != 0 || (v & 0x10000000) || ch == 6)) dma_run(ch);
        break;
    }
}
u32 dma_read(u32 a)
{
    u32 off = a - 0x1F801080;
    int ch = off >> 4;
    if (ch == 7) return (off & 15) == 0 ? dma_dpcr : dma_dicr;
    switch (off & 15) { case 0: return dma_madr[ch]; case 4: return dma_bcr[ch]; case 8: return dma_chcr[ch]; }
    return 0;
}

// ------------------------------------------------------------------ registradores
static u32 memctl[16];
void hw_tick(int cyc); extern int hw_pending;
u32 hw_read(u32 a, int size)
{
    if (hw_pending) { int c = hw_pending; hw_pending = 0; hw_tick(c); }
    if (a >= 0x1F801C00 && a < 0x1F802000) {
        u32 off = a - 0x1F801C00;
        if (size == 4) return Psyz_SpuRead(off) | ((u32)Psyz_SpuRead(off + 2) << 16);
        return Psyz_SpuRead(off & ~1);
    }
    if (a >= 0x1F801800 && a < 0x1F801804) {
        if (size == 1) return cd_read_reg(a);
        u32 v = 0;
        for (int i = 0; i < size; i++) v |= (u32)cd_read_reg(a) << (i * 8);   // leituras largas: dados do FIFO
        return v;
    }
    if (a >= 0x1F801080 && a < 0x1F801100) return dma_read(a & ~3);
    if (a >= 0x1F801100 && a < 0x1F801130) {
        int n = (a >> 4) & 3; int r = a & 15;
        if (r == 0) return tmr[n].count;
        if (r == 4) { u32 m = tmr[n].mode; tmr[n].mode &= ~0x1800; return m; }
        if (r == 8) return tmr[n].target;
        return 0;
    }
    switch (a) {
    case 0x1F801070: return i_stat;
    case 0x1F801074: return i_mask;
    case 0x1F801810: return gpu_read();
    case 0x1F801814: return gpu_stat();
    case 0x1F801040: { u8 v = sio_rx_full ? sio_rx : 0xFF; sio_rx_full = 0; return v; }
    case 0x1F801044: return 0x05 | (sio_rx_full ? 0x02 : 0) | (sio_stat_irq ? 0x200 : 0) | (sio_ack_timer > 0 ? 0x80 : 0);
    case 0x1F801048: return sio_mode;
    case 0x1F80104A: return sio_ctrl;
    case 0x1F80104E: return sio_baud;
    case 0x1F801054: return 0x05;
    case 0x1F801820: return mdec_read_out();
    case 0x1F801824: return mdec_status();
    }
    if (a >= 0x1F801000 && a < 0x1F801040) return memctl[(a >> 2) & 15];
    if (a == 0x1F801060) return 0xB88;
    return 0;
}

void hw_write(u32 a, u32 v, int size)
{
    if (hw_pending) { int c = hw_pending; hw_pending = 0; hw_tick(c); }
    if (a >= 0x1F801C00 && a < 0x1F802000) {
        u32 off = a - 0x1F801C00;
        if (size == 4) { Psyz_SpuWrite(off, (u16)v); Psyz_SpuWrite(off + 2, (u16)(v >> 16)); }
        else Psyz_SpuWrite(off & ~1, (u16)v);
        return;
    }
    if (a >= 0x1F801800 && a < 0x1F801804) { cd_write_reg(a, (u8)v); return; }
    if (a >= 0x1F801080 && a < 0x1F801100) { dma_write(a & ~3, v); return; }
    if (a >= 0x1F801100 && a < 0x1F801130) {
        int n = (a >> 4) & 3; int r = a & 15;
        if (r == 0) tmr[n].count = v & 0xFFFF;
        else if (r == 4) { tmr[n].mode = (v & 0x3FF) | 0x400; tmr[n].count = 0; tmr[n].fired = 0; }
        else if (r == 8) tmr[n].target = v & 0xFFFF;
        return;
    }
    if (a >= 0x1F802000 && a < 0x1F803000) {   // porta de depuração: saída de texto da BIOS
        if (a == 0x1F802023 || a == 0x1F802080) { char c[2] = { (char)v, 0 }; psx_log("%s", c); }
        return;
    }
    switch (a) {
    case 0x1F801070: i_stat &= v; return;
    case 0x1F801074: i_mask = v & 0x7FF; return;
    case 0x1F801810: gpu_gp0(v); return;
    case 0x1F801814: gpu_gp1(v); return;
    case 0x1F801040: sio_transfer((u8)v); return;
    case 0x1F801048: sio_mode = v; return;
    case 0x1F80104A:
        sio_ctrl = v;
        if (v & 0x10) { sio_stat_irq = 0; }
        if (v & 0x40) { sio_ctrl = 0; sio_step = 0; sio_stat_irq = 0; }
        if (!(v & 0x02)) { sio_step = 0; }
        return;
    case 0x1F80104E: sio_baud = v; return;
    case 0x1F801820: mdec_word(v); return;
    case 0x1F801824:
        mdec_ctrl = v;
        if (v & 0x80000000) { mdec_param_mode = 0; mdec_out_n = mdec_out_pos = 0; mdec_in_n = 0; }
        return;
    }
    if (a >= 0x1F801000 && a < 0x1F801040) memctl[(a >> 2) & 15] = v;
}

int hw_pending;   // ciclos ainda não repassados ao hardware (a CPU os acumula)
void hw_tick(int cyc)
{
    timers_tick(cyc);
    cd_tick(cyc);
    sio_tick(cyc);
}

// volta todo o hardware ao estado de ligado (para começar outro jogo/fase sem reabrir o programa)
void hw_reset(void)
{
    i_stat = i_mask = 0; cd_fast = 0;
    memset(tmr, 0, sizeof(tmr)); hblank_acc = 0;
    memset(vram, 0, sizeof(vram)); memset(vram_draw, 0, sizeof(vram_draw));
    vram_draw_dirty = 1; vram_dirty = 1; prim_len = 0;
    memset(cmd_buf, 0, sizeof(cmd_buf)); cmd_len = cmd_need = 0; poly_line = 0;
    xfer_w = xfer_h = xfer_x = xfer_y = xfer_i = xfer_n = xfer_mode = 0;
    off_x = off_y = area_x0 = area_y0 = area_x1 = area_y1 = 0;
    e1_state = 0; gpustat_extra = 0; disp_x = disp_y = 0; disp_24 = 0; disp_w = 320; disp_h = 240;
    disp_written = 0; gpu_drew = 0; field_bit = 0;
    cd_index = 0; cd_ie = 0x1F; cd_if = 0; memset(cd_param, 0, sizeof(cd_param)); cd_nparam = 0;
    memset(cd_resp, 0, sizeof(cd_resp)); cd_nresp = cd_rpos = 0; cd_mode = 0; cd_stat = 0x02;
    cd_setloc_lba = cd_lba = 0; cd_reading = cd_seek_pending = 0; cd_dlen = cd_dpos = 0;
    memset(cd_last_hdr, 0, sizeof(cd_last_hdr)); cd_filter_file = cd_filter_chan = 0; cd_cmd = -1;
    cd_data_ready = 0; cd_nparam_used = 0; cd_cmd_timer = 0; cd_second_timer = 0; cd_second_cmd = -1; cd_read_timer = 0;
    memset(cd_q, 0, sizeof(cd_q)); cd_qn = 0; movie_abort = 0;
    sio_rx = 0; sio_rx_full = 0; sio_ctrl = sio_mode = sio_baud = 0; sio_stat_irq = 0; sio_step = sio_dev = 0; sio_ack_timer = 0;
    card_dirty = 0; card_flag = 0x08; card_cmd = card_msb = card_lsb = card_sum = card_prev = 0; card_bad = 0;
    mdec_cmd = mdec_ctrl = 0; mdec_in_n = mdec_in_need = 0; mdec_out_n = mdec_out_pos = 0; mdec_param_mode = 0; mdec_rd = 0;
    memset(dma_madr, 0, sizeof(dma_madr)); memset(dma_bcr, 0, sizeof(dma_bcr)); memset(dma_chcr, 0, sizeof(dma_chcr));
    dma_dpcr = 0x07654321; dma_dicr = 0; memset(memctl, 0, sizeof(memctl));
}
