// GTE (coprocessador de geometria) — implementação padrão (comportamento documentado do PS1)
#include "psx.h"

static s16 V[3][3];          // VXY0..2, VZ0..2
static u8 RGBC[4];
static u16 OTZ;
static s16 IR[4];
static s16 SXY[4][2];        // SXY0, SXY1, SXY2, SXYP(fifo)
static u16 SZ[4];
static u8 RGB[3][4];
static u32 RES1;
static s32 MAC[4];
static u16 IRGB_;
static s32 LZCS, LZCR;
// controle
static s16 RT[3][3], LM[3][3], LCM[3][3];
static s32 TR[3], BK[3], FC[3];
static s32 OFX, OFY;
static u16 H;
static s16 DQA;
static s32 DQB;
static s16 ZSF3, ZSF4;
static u32 FLAG;

static int sf, lm_;

static s64 chk_mac(int i, s64 v)
{
    if (i == 0) {
        if (v > 0x7FFFFFFFLL) FLAG |= 1 << 16;
        else if (v < -0x80000000LL) FLAG |= 1 << 15;
        return v;
    }
    if (v > 0x7FFFFFFFFFFLL) FLAG |= 1 << (31 - i);
    else if (v < -0x80000000000LL) FLAG |= 1 << (28 - i);
    return v;
}
static s32 set_mac(int i, s64 v)
{
    chk_mac(i, v);
    if (i > 0 && sf) v >>= 12;
    MAC[i] = (s32)v;
    return MAC[i];
}
static s16 sat_ir(int i, s32 v, int lm)
{
    s32 lo = lm ? 0 : -0x8000;
    if (v < lo) { FLAG |= 1 << (25 - i); return (s16)lo; }
    if (v > 0x7FFF) { FLAG |= 1 << (25 - i); return 0x7FFF; }
    return (s16)v;
}
static void set_ir(int i, s32 v, int lm) { IR[i] = sat_ir(i, v, lm); }
static void mac_to_ir(int lm) { set_ir(1, MAC[1], lm); set_ir(2, MAC[2], lm); set_ir(3, MAC[3], lm); }
static u8 sat_rgb(int i, s32 v)
{
    if (v < 0) { FLAG |= 1 << (21 - i); return 0; }
    if (v > 255) { FLAG |= 1 << (21 - i); return 255; }
    return (u8)v;
}
static void push_rgb(void)
{
    memcpy(RGB[0], RGB[1], 4); memcpy(RGB[1], RGB[2], 4);
    RGB[2][0] = sat_rgb(0, MAC[1] >> 4); RGB[2][1] = sat_rgb(1, MAC[2] >> 4); RGB[2][2] = sat_rgb(2, MAC[3] >> 4);
    RGB[2][3] = RGBC[3];
}
static u16 sat_z(s64 v)
{
    if (v < 0) { FLAG |= 1 << 18; return 0; }
    if (v > 0xFFFF) { FLAG |= 1 << 18; return 0xFFFF; }
    return (u16)v;
}
static void push_z(s32 z)
{
    SZ[0] = SZ[1]; SZ[1] = SZ[2]; SZ[2] = SZ[3];
    SZ[3] = sat_z(z);
}
static void push_xy(s32 x, s32 y)
{
    if (x < -0x400) { FLAG |= 1 << 14; x = -0x400; } else if (x > 0x3FF) { FLAG |= 1 << 14; x = 0x3FF; }
    if (y < -0x400) { FLAG |= 1 << 13; y = -0x400; } else if (y > 0x3FF) { FLAG |= 1 << 13; y = 0x3FF; }
    SXY[0][0] = SXY[1][0]; SXY[0][1] = SXY[1][1];
    SXY[1][0] = SXY[2][0]; SXY[1][1] = SXY[2][1];
    SXY[2][0] = (s16)x; SXY[2][1] = (s16)y;
}

static u8 unr[0x101];
static int unr_init;
static u32 gte_div(u32 h, u32 sz)
{
    if (!unr_init) {
        for (int i = 0; i < 0x101; i++) {
            int v = (0x40000 / (i + 0x100) + 1) / 2 - 0x101;
            unr[i] = v < 0 ? 0 : (u8)v;
        }
        unr_init = 1;
    }
    if (h >= sz * 2) { FLAG |= 1 << 17; return 0x1FFFF; }
    int z = 0;
    while (z < 16 && !(sz & (0x8000 >> z))) z++;
    u32 n = h << z;
    u32 d = sz << z;
    u32 u = unr[(d - 0x7FC0) >> 7] + 0x101;
    d = (0x2000080 - (d * u)) >> 8;
    d = (0x0000080 + (d * u)) >> 8;
    u32 r = (u32)(((u64)n * d + 0x8000) >> 16);
    return r > 0x1FFFF ? 0x1FFFF : r;
}

static void rtp(int v, int last)
{
    s64 x = V[v][0], y = V[v][1], z = V[v][2];
    s64 m1 = ((s64)TR[0] << 12) + RT[0][0] * x + RT[0][1] * y + RT[0][2] * z;
    s64 m2 = ((s64)TR[1] << 12) + RT[1][0] * x + RT[1][1] * y + RT[1][2] * z;
    s64 m3 = ((s64)TR[2] << 12) + RT[2][0] * x + RT[2][1] * y + RT[2][2] * z;
    set_mac(1, m1); set_mac(2, m2); set_mac(3, m3);
    set_ir(1, MAC[1], lm_); set_ir(2, MAC[2], lm_);
    // IR3: saturação com flag baseada em m3>>12
    {
        s32 v3 = MAC[3];
        s32 lo = lm_ ? 0 : -0x8000;
        s32 c = (s32)(m3 >> 12);
        if (c < -0x8000 || c > 0x7FFF) FLAG |= 1 << 22;
        IR[3] = (s16)(v3 < lo ? lo : v3 > 0x7FFF ? 0x7FFF : v3);
    }
    push_z((s32)(m3 >> 12));
    u32 q = gte_div(H, SZ[3]);
    s64 sx = (s64)q * IR[1] + OFX;
    s64 sy = (s64)q * IR[2] + OFY;
    chk_mac(0, sx); chk_mac(0, sy);
    push_xy((s32)(sx >> 16), (s32)(sy >> 16));
    if (last) {
        s64 dp = (s64)DQA * q + DQB;
        chk_mac(0, dp);
        MAC[0] = (s32)dp;
        s32 ir0 = (s32)(dp >> 12);
        if (ir0 < 0) { FLAG |= 1 << 12; ir0 = 0; } else if (ir0 > 0x1000) { FLAG |= 1 << 12; ir0 = 0x1000; }
        IR[0] = (s16)ir0;
    }
}

static void mvmva(int mx, int vx, int tx)
{
    s16 (*M)[3];
    static s16 garbage[3][3];
    s16 vec[3];
    s32* T;
    static s32 zero[3];
    switch (mx) { case 0: M = RT; break; case 1: M = LM; break; case 2: M = LCM; break; default: M = garbage; break; }
    if (vx < 3) { vec[0] = V[vx][0]; vec[1] = V[vx][1]; vec[2] = V[vx][2]; }
    else { vec[0] = IR[1]; vec[1] = IR[2]; vec[2] = IR[3]; }
    switch (tx) { case 0: T = TR; break; case 1: T = BK; break; case 2: T = FC; break; default: T = zero; break; }
    for (int i = 0; i < 3; i++) {
        s64 m = ((s64)T[i] << 12) + (s64)M[i][0] * vec[0] + (s64)M[i][1] * vec[1] + (s64)M[i][2] * vec[2];
        set_mac(i + 1, m);
    }
    mac_to_ir(lm_);
}

static void ncds_core(int v, int col, int depth)
{
    s16 vec[3] = { V[v][0], V[v][1], V[v][2] };
    for (int i = 0; i < 3; i++) set_mac(i + 1, (s64)LM[i][0] * vec[0] + (s64)LM[i][1] * vec[1] + (s64)LM[i][2] * vec[2]);
    mac_to_ir(lm_);
    s16 ir[3] = { IR[1], IR[2], IR[3] };
    for (int i = 0; i < 3; i++) set_mac(i + 1, ((s64)BK[i] << 12) + (s64)LCM[i][0] * ir[0] + (s64)LCM[i][1] * ir[1] + (s64)LCM[i][2] * ir[2]);
    mac_to_ir(lm_);
    if (col) {
        s32 r = ((s32)RGBC[0] * IR[1]) << 4, g = ((s32)RGBC[1] * IR[2]) << 4, b = ((s32)RGBC[2] * IR[3]) << 4;
        if (depth) {
            s32 m[3] = { r, g, b };
            for (int i = 0; i < 3; i++) {
                s64 d = ((s64)FC[i] << 12) - m[i];
                set_mac(i + 1, d);   // sf
                s16 t = sat_ir(i + 1, MAC[i + 1], 0);
                set_mac(i + 1, (s64)m[i] + (s64)t * IR[0]);
            }
        } else {
            set_mac(1, r); set_mac(2, g); set_mac(3, b);
        }
        mac_to_ir(lm_);
    }
    push_rgb();
}

void gte_command(u32 op)
{
    FLAG = 0;
    sf = (op >> 19) & 1 ? 1 : 0;
    lm_ = (op >> 10) & 1;
    switch (op & 0x3F) {
    case 0x01: rtp(0, 1); break;
    case 0x30: rtp(0, 0); rtp(1, 0); rtp(2, 1); break;
    case 0x06: {   // NCLIP
        s64 v = (s64)SXY[0][0] * SXY[1][1] + (s64)SXY[1][0] * SXY[2][1] + (s64)SXY[2][0] * SXY[0][1]
            - (s64)SXY[0][0] * SXY[2][1] - (s64)SXY[1][0] * SXY[0][1] - (s64)SXY[2][0] * SXY[1][1];
        chk_mac(0, v); MAC[0] = (s32)v;
        break;
    }
    case 0x0C: {   // OP
        s32 d1 = RT[0][0], d2 = RT[1][1], d3 = RT[2][2];
        set_mac(1, (s64)IR[3] * d2 - (s64)IR[2] * d3);
        set_mac(2, (s64)IR[1] * d3 - (s64)IR[3] * d1);
        set_mac(3, (s64)IR[2] * d1 - (s64)IR[1] * d2);
        mac_to_ir(lm_);
        break;
    }
    case 0x10: case 0x29: case 0x2A: {   // DPCS / DCPL / DPCT
        int n = (op & 0x3F) == 0x2A ? 3 : 1;
        for (int k = 0; k < n; k++) {
            u8 c[3];
            if ((op & 0x3F) == 0x2A) { c[0] = RGB[0][0]; c[1] = RGB[0][1]; c[2] = RGB[0][2]; }
            else { c[0] = RGBC[0]; c[1] = RGBC[1]; c[2] = RGBC[2]; }
            s32 m[3];
            for (int i = 0; i < 3; i++) {
                m[i] = (op & 0x3F) == 0x29 ? (((s32)c[i] * IR[i + 1]) << 4) : ((s32)c[i] << 16);
            }
            for (int i = 0; i < 3; i++) {
                set_mac(i + 1, ((s64)FC[i] << 12) - m[i]);
                s16 t = sat_ir(i + 1, MAC[i + 1], 0);
                set_mac(i + 1, (s64)m[i] + (s64)t * IR[0]);
            }
            mac_to_ir(lm_);
            push_rgb();
        }
        break;
    }
    case 0x11: {   // INTPL
        s32 m[3] = { (s32)IR[1] << 12, (s32)IR[2] << 12, (s32)IR[3] << 12 };
        for (int i = 0; i < 3; i++) {
            set_mac(i + 1, ((s64)FC[i] << 12) - m[i]);
            s16 t = sat_ir(i + 1, MAC[i + 1], 0);
            set_mac(i + 1, (s64)m[i] + (s64)t * IR[0]);
        }
        mac_to_ir(lm_);
        push_rgb();
        break;
    }
    case 0x12: mvmva((op >> 17) & 3, (op >> 15) & 3, (op >> 13) & 3); break;
    case 0x13: ncds_core(0, 1, 1); break;
    case 0x16: ncds_core(0, 1, 1); ncds_core(1, 1, 1); ncds_core(2, 1, 1); break;
    case 0x14: {   // CDP
        s16 ir[3] = { IR[1], IR[2], IR[3] };
        for (int i = 0; i < 3; i++) set_mac(i + 1, ((s64)BK[i] << 12) + (s64)LCM[i][0] * ir[0] + (s64)LCM[i][1] * ir[1] + (s64)LCM[i][2] * ir[2]);
        mac_to_ir(lm_);
        s32 m[3] = { ((s32)RGBC[0] * IR[1]) << 4, ((s32)RGBC[1] * IR[2]) << 4, ((s32)RGBC[2] * IR[3]) << 4 };
        for (int i = 0; i < 3; i++) {
            set_mac(i + 1, ((s64)FC[i] << 12) - m[i]);
            s16 t = sat_ir(i + 1, MAC[i + 1], 0);
            set_mac(i + 1, (s64)m[i] + (s64)t * IR[0]);
        }
        mac_to_ir(lm_);
        push_rgb();
        break;
    }
    case 0x1B: ncds_core(0, 1, 0); break;   // NCCS
    case 0x3F: ncds_core(0, 1, 0); ncds_core(1, 1, 0); ncds_core(2, 1, 0); break;   // NCCT
    case 0x1C: {   // CC
        s16 ir[3] = { IR[1], IR[2], IR[3] };
        for (int i = 0; i < 3; i++) set_mac(i + 1, ((s64)BK[i] << 12) + (s64)LCM[i][0] * ir[0] + (s64)LCM[i][1] * ir[1] + (s64)LCM[i][2] * ir[2]);
        mac_to_ir(lm_);
        set_mac(1, ((s32)RGBC[0] * IR[1]) << 4); set_mac(2, ((s32)RGBC[1] * IR[2]) << 4); set_mac(3, ((s32)RGBC[2] * IR[3]) << 4);
        mac_to_ir(lm_);
        push_rgb();
        break;
    }
    case 0x1E: ncds_core(0, 0, 0); break;   // NCS
    case 0x20: ncds_core(0, 0, 0); ncds_core(1, 0, 0); ncds_core(2, 0, 0); break;   // NCT
    case 0x28: {   // SQR
        set_mac(1, (s64)IR[1] * IR[1]); set_mac(2, (s64)IR[2] * IR[2]); set_mac(3, (s64)IR[3] * IR[3]);
        mac_to_ir(lm_);
        break;
    }
    case 0x2D: {   // AVSZ3
        s64 v = (s64)ZSF3 * (SZ[1] + SZ[2] + SZ[3]);
        chk_mac(0, v); MAC[0] = (s32)v;
        OTZ = sat_z(v >> 12);
        break;
    }
    case 0x2E: {   // AVSZ4
        s64 v = (s64)ZSF4 * (SZ[0] + SZ[1] + SZ[2] + SZ[3]);
        chk_mac(0, v); MAC[0] = (s32)v;
        OTZ = sat_z(v >> 12);
        break;
    }
    case 0x3D: {   // GPF
        set_mac(1, (s64)IR[0] * IR[1]); set_mac(2, (s64)IR[0] * IR[2]); set_mac(3, (s64)IR[0] * IR[3]);
        mac_to_ir(lm_);
        push_rgb();
        break;
    }
    case 0x3E: {   // GPL
        s64 m1 = (s64)MAC[1] << (sf ? 12 : 0), m2 = (s64)MAC[2] << (sf ? 12 : 0), m3 = (s64)MAC[3] << (sf ? 12 : 0);
        set_mac(1, m1 + (s64)IR[0] * IR[1]); set_mac(2, m2 + (s64)IR[0] * IR[2]); set_mac(3, m3 + (s64)IR[0] * IR[3]);
        mac_to_ir(lm_);
        push_rgb();
        break;
    }
    default: break;
    }
    if (FLAG & 0x7F87E000) FLAG |= 0x80000000;
}

static s32 lzc(s32 v)
{
    u32 x = (v < 0) ? ~(u32)v : (u32)v;
    int n = 0;
    while (n < 32 && !(x & 0x80000000)) { x <<= 1; n++; }
    return n;
}

u32 gte_read_data(int r)
{
    switch (r) {
    case 0: return (u16)V[0][0] | ((u32)(u16)V[0][1] << 16);
    case 1: return (u32)(s32)V[0][2];
    case 2: return (u16)V[1][0] | ((u32)(u16)V[1][1] << 16);
    case 3: return (u32)(s32)V[1][2];
    case 4: return (u16)V[2][0] | ((u32)(u16)V[2][1] << 16);
    case 5: return (u32)(s32)V[2][2];
    case 6: return RGBC[0] | RGBC[1] << 8 | RGBC[2] << 16 | (u32)RGBC[3] << 24;
    case 7: return OTZ;
    case 8: return (u32)(s32)IR[0];
    case 9: return (u32)(s32)IR[1];
    case 10: return (u32)(s32)IR[2];
    case 11: return (u32)(s32)IR[3];
    case 12: return (u16)SXY[0][0] | ((u32)(u16)SXY[0][1] << 16);
    case 13: return (u16)SXY[1][0] | ((u32)(u16)SXY[1][1] << 16);
    case 14: case 15: return (u16)SXY[2][0] | ((u32)(u16)SXY[2][1] << 16);
    case 16: return SZ[0]; case 17: return SZ[1]; case 18: return SZ[2]; case 19: return SZ[3];
    case 20: case 21: case 22: { int i = r - 20; return RGB[i][0] | RGB[i][1] << 8 | RGB[i][2] << 16 | (u32)RGB[i][3] << 24; }
    case 23: return RES1;
    case 24: return (u32)MAC[0]; case 25: return (u32)MAC[1]; case 26: return (u32)MAC[2]; case 27: return (u32)MAC[3];
    case 28: case 29: {
        int rr = IR[1] >> 7, g = IR[2] >> 7, b = IR[3] >> 7;
        rr = rr < 0 ? 0 : rr > 31 ? 31 : rr; g = g < 0 ? 0 : g > 31 ? 31 : g; b = b < 0 ? 0 : b > 31 ? 31 : b;
        return rr | g << 5 | b << 10;
    }
    case 30: return (u32)LZCS;
    case 31: return (u32)lzc(LZCS);
    }
    return 0;
}

void gte_write_data(int r, u32 v)
{
    switch (r) {
    case 0: V[0][0] = (s16)v; V[0][1] = (s16)(v >> 16); break;
    case 1: V[0][2] = (s16)v; break;
    case 2: V[1][0] = (s16)v; V[1][1] = (s16)(v >> 16); break;
    case 3: V[1][2] = (s16)v; break;
    case 4: V[2][0] = (s16)v; V[2][1] = (s16)(v >> 16); break;
    case 5: V[2][2] = (s16)v; break;
    case 6: RGBC[0] = v; RGBC[1] = v >> 8; RGBC[2] = v >> 16; RGBC[3] = v >> 24; break;
    case 7: OTZ = (u16)v; break;
    case 8: IR[0] = (s16)v; break;
    case 9: IR[1] = (s16)v; break;
    case 10: IR[2] = (s16)v; break;
    case 11: IR[3] = (s16)v; break;
    case 12: SXY[0][0] = (s16)v; SXY[0][1] = (s16)(v >> 16); break;
    case 13: SXY[1][0] = (s16)v; SXY[1][1] = (s16)(v >> 16); break;
    case 14: SXY[2][0] = (s16)v; SXY[2][1] = (s16)(v >> 16); break;
    case 15: push_xy((s16)v, (s16)(v >> 16)); break;
    case 16: SZ[0] = (u16)v; break; case 17: SZ[1] = (u16)v; break; case 18: SZ[2] = (u16)v; break; case 19: SZ[3] = (u16)v; break;
    case 20: case 21: case 22: { int i = r - 20; RGB[i][0] = v; RGB[i][1] = v >> 8; RGB[i][2] = v >> 16; RGB[i][3] = v >> 24; break; }
    case 23: RES1 = v; break;
    case 24: MAC[0] = (s32)v; break; case 25: MAC[1] = (s32)v; break; case 26: MAC[2] = (s32)v; break; case 27: MAC[3] = (s32)v; break;
    case 28: IR[1] = (s16)((v & 31) << 7); IR[2] = (s16)(((v >> 5) & 31) << 7); IR[3] = (s16)(((v >> 10) & 31) << 7); break;
    case 30: LZCS = (s32)v; break;
    default: break;
    }
}

static void wr_mat(s16 m[3][3], int r, u32 v)
{
    s16* f = &m[0][0];
    f[r * 2] = (s16)v;
    if (r * 2 + 1 < 9) f[r * 2 + 1] = (s16)(v >> 16);
}
static u32 rd_mat(s16 m[3][3], int r)
{
    s16* f = &m[0][0];
    if (r == 4) return (u32)(s32)f[8];
    return (u16)f[r * 2] | ((u32)(u16)f[r * 2 + 1] << 16);
}

u32 gte_read_ctrl(int r)
{
    switch (r) {
    case 0: case 1: case 2: case 3: case 4: return rd_mat(RT, r);
    case 5: return (u32)TR[0]; case 6: return (u32)TR[1]; case 7: return (u32)TR[2];
    case 8: case 9: case 10: case 11: case 12: return rd_mat(LM, r - 8);
    case 13: return (u32)BK[0]; case 14: return (u32)BK[1]; case 15: return (u32)BK[2];
    case 16: case 17: case 18: case 19: case 20: return rd_mat(LCM, r - 16);
    case 21: return (u32)FC[0]; case 22: return (u32)FC[1]; case 23: return (u32)FC[2];
    case 24: return (u32)OFX; case 25: return (u32)OFY;
    case 26: return (u32)(s32)(s16)H;
    case 27: return (u32)(s32)DQA; case 28: return (u32)DQB;
    case 29: return (u32)(s32)ZSF3; case 30: return (u32)(s32)ZSF4;
    case 31: return FLAG;
    }
    return 0;
}

void gte_write_ctrl(int r, u32 v)
{
    switch (r) {
    case 0: case 1: case 2: case 3: case 4: wr_mat(RT, r, v); break;
    case 5: TR[0] = (s32)v; break; case 6: TR[1] = (s32)v; break; case 7: TR[2] = (s32)v; break;
    case 8: case 9: case 10: case 11: case 12: wr_mat(LM, r - 8, v); break;
    case 13: BK[0] = (s32)v; break; case 14: BK[1] = (s32)v; break; case 15: BK[2] = (s32)v; break;
    case 16: case 17: case 18: case 19: case 20: wr_mat(LCM, r - 16, v); break;
    case 21: FC[0] = (s32)v; break; case 22: FC[1] = (s32)v; break; case 23: FC[2] = (s32)v; break;
    case 24: OFX = (s32)v; break; case 25: OFY = (s32)v; break;
    case 26: H = (u16)v; break;
    case 27: DQA = (s16)v; break; case 28: DQB = (s32)v; break;
    case 29: ZSF3 = (s16)v; break; case 30: ZSF4 = (s16)v; break;
    case 31: FLAG = (v & 0x7FFFF000) | ((v & 0x7F87E000) ? 0x80000000 : 0); break;
    }
}

void gte_reset(void)
{
    memset(V, 0, sizeof(V)); memset(RGBC, 0, sizeof(RGBC)); OTZ = 0; memset(IR, 0, sizeof(IR)); memset(SXY, 0, sizeof(SXY));
    memset(SZ, 0, sizeof(SZ)); memset(RGB, 0, sizeof(RGB)); RES1 = 0; memset(MAC, 0, sizeof(MAC)); IRGB_ = 0; LZCS = LZCR = 0;
    memset(RT, 0, sizeof(RT)); memset(LM, 0, sizeof(LM)); memset(LCM, 0, sizeof(LCM)); memset(TR, 0, sizeof(TR)); memset(BK, 0, sizeof(BK)); memset(FC, 0, sizeof(FC));
    OFX = OFY = 0; H = 0; DQA = 0; DQB = 0; ZSF3 = ZSF4 = 0; FLAG = 0; sf = lm_ = 0;
}
