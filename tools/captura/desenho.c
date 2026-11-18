// desenho.c — desenhista das fotos da captura (v_N.bin + p_N.bin -> tela 320x240) só com contas, sem placa de vídeo.
//
// Faz exatamente as contas que o Godot 4.7.2 (renderizador de compatibilidade: scripts/x4c/x4_machine.gd _render() +
// scripts/x4c/psx_gpu.gdshader + o canvas.glsl do Godot) faz no Mesa 25.2 llvmpipe, o desenhista por software com que
// as telas do PC do dono foram feitas. Assim a tela sai igual em qualquer PC, qualquer placa, e sem abrir janela.
//
// Cada conta de ponto flutuante segue a ordem do llvmpipe: compilar com -ffp-contract=off (nada de juntar a*b+c
// sozinho); onde o llvmpipe multiplica e soma de uma vez (llvm.fmuladd numa CPU com FMA) usamos fma_f(), exata em
// qualquer CPU.
//   vértice : posição * escala do nó, arredondada para o pixel (snap_2d_vertices_to_pixel), tela -> -1..1 -> janela
//   setup   : planos dos atributos (lp_state_setup.c) e pontos cobertos em ponto fixo 1/256 (lp_setup_tri.c, regra
//             de cima/esquerda)
//   ponto   : o shader do PS1 (página, CLUT, cores de 15 bits, modulação, semitransparência em duas passadas)
//   mistura : em 16 bits normalizados (lp_bld_blend), guardada em 10 bits (RGB10_A2, a tela do Godot) e lida em 8 bits
//             como o glGetTexImage do Mesa ((v * 255 + 511) / 1023)
//
// uso: captura desenha PASTA N1,N2,...   (lê PASTA/v_N.bin e PASTA/p_N.bin, grava PASTA/tela_N.rgba, 320x240 RGBA)
// Os quadros são desenhados na ordem dada e o estado do desenho (página de textura, escala da tela) passa de um para o
// outro, como no tests/render_dump.gd.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LARG 320
#define ALT 240

typedef struct {
	int px, py, pu, pv;
	uint8_t c[4];        // cor do vértice (R, G, B) e as bandeiras no alfa
	float c0[4];         // CUSTOM0: página x, y; CLUT x, y
} Vert;

typedef struct {
	Vert *v; int nv, cv;
	int *i; int ni, ci;
} Malha;

static uint16_t *vram;          // 1024x512

// ---------------------------------------------------------------- contas exatas, sem a biblioteca de matemática
// fmaf/floorf/lrintf mudam de um sistema para outro (o fmaf do Windows nem sempre é exato): estas dão o mesmo bit em
// qualquer PC com SSE2 (todo x86-64).
static float fma_f(float a, float b, float c) {   // a*b + c com um arredondamento só (a FMA da CPU do PC do dono)
	volatile double p = (double)a * (double)b;   // exato: 24 + 24 bits cabem nos 53 do double
	volatile double s = p + (double)c;
	volatile double t = s - p;
	volatile double e1 = p - (s - t), e2 = (double)c - t;
	double err = e1 + e2;                         // p + c = s + err, exatamente
	double r = s;
	if (err != 0.0) {   // arredonda para ímpar em double e só então para float: dá o arredondamento certo da soma exata
		uint64_t u; memcpy(&u, &r, 8);
		if ((u & 1) == 0) { if ((err > 0.0) == (r > 0.0)) u++; else u--; memcpy(&r, &u, 8); }
	}
	return (float)r;
}
static float piso(float x) { int i = (int)x; if ((float)i > x) i--; return (float)i; }   // floor (|x| < 2^31)
static int arred_par(float x) {   // arredondamento para o mais perto, empate para o par (cvtps2dq, roundeven)
	float f = piso(x); int i = (int)f;
	volatile float d = x - f;
	if (d > 0.5f || (d == 0.5f && (i & 1))) i++;
	return i;
}
static uint16_t tela[ALT][LARG][3];   // canais de 10 bits
static int tpx, tpy, tdepth, tabr;   // estado E1 (fica de um quadro para o outro)
static float esc_x = 1.0f, esc_y = 1.0f;   // escala do nó (comando F1)

// ---------------------------------------------------------------- mistura e cores (llvmpipe, RGB10_A2)
static uint32_t para16(float x) {   // lp_build_clamped_float_to_unsigned_norm(16): x*(65535/65536) + 128, 16 bits baixos
	if (!(x > 0.0f)) x = 0.0f;   // clamp_zero_one_nanzero
	if (x > 1.0f) x = 1.0f;
	volatile float t = x * (65535.0f / 65536.0f);
	volatile float s = t + 128.0f;
	uint32_t b; memcpy(&b, (const void *)&s, 4);
	return b & 0xFFFF;
}
static uint32_t mul16(uint32_t a, uint32_t b) {   // lp_build_mul_norm: (ab + (ab >> 16) + 0x8000) >> 16
	uint32_t ab = a * b;
	ab = ab + (ab >> 16);
	return (ab + 0x8000u) >> 16;
}
static uint32_t de10(uint32_t v) { return (v << 6) | (v >> 4); }   // scale_bits 10 -> 16

// mistura: 0 = mix (SRC_ALPHA, ONE_MINUS_SRC_ALPHA), 1 = add (SRC_ALPHA, ONE), 2 = sub (reverse: dst - src*SRC_ALPHA)
static void mistura(int x, int y, const float cor[4], int modo) {
	uint32_t sa = para16(cor[3]);
	for (int k = 0; k < 3; k++) {
		uint32_t s = para16(cor[k]), d = de10(tela[y][x][k]), r;
		if (modo == 0) { r = mul16(s, sa) + mul16(d, 0xFFFFu - sa); if (r > 0xFFFF) r = 0xFFFF; }
		else if (modo == 1) { r = mul16(s, sa) + d; if (r > 0xFFFF) r = 0xFFFF; }
		else { uint32_t t = mul16(s, sa); r = d > t ? d - t : 0; }
		tela[y][x][k] = (uint16_t)(r >> 6);
	}
}

// ---------------------------------------------------------------- o shader do PS1 (psx_gpu.gdshader)
static int palavra(int x, int y) { return vram[(y & 511) * 1024 + (x & 1023)]; }

typedef struct { int sel; int modo; float semi_alpha, semi_scale; } Passada;

// devolve 0 se o ponto foi descartado
static int fragmento(const Passada *ps, const float fl[4], const float pc[4], float tu, float tv, const float col[3], float out[4]) {
	if (fl[1] > 1.5f) {
		return 0;   // (imagem direta da VRAM: o x4_machine.gd nunca chega aqui)
	} else if (fl[1] > 0.5f) {
		int tx = (int)piso(tu), ty = (int)piso(tv);
		tx &= 255; ty &= 255;
		int gx = (int)pc[0], gy = (int)pc[1];
		int depth = (int)(fl[0] + 0.5f);
		int w;
		if (depth == 0) {
			int v = palavra(gx + (tx >> 2), gy + ty);
			int idx = (v >> ((tx & 3) * 4)) & 15;
			w = palavra((int)pc[2] + idx, (int)pc[3]);
		} else if (depth == 1) {
			int v = palavra(gx + (tx >> 1), gy + ty);
			int idx = (v >> ((tx & 1) * 8)) & 255;
			w = palavra((int)pc[2] + idx, (int)pc[3]);
		} else {
			w = palavra(gx + tx, gy + ty);
		}
		if (w == 0) return 0;
		float c[3] = { (float)(w & 31) / 31.0f, (float)((w >> 5) & 31) / 31.0f, (float)((w >> 10) & 31) / 31.0f };
		if (fl[2] < 0.5f) {
			for (int k = 0; k < 3; k++) {
				volatile float m = c[k] * col[k];
				float m2 = m * 2.0f;
				c[k] = m2 < 0.0f ? 0.0f : (m2 > 1.0f ? 1.0f : m2);
			}
		}
		int semi = fl[3] > 0.5f && (w & 0x8000) != 0;
		if ((ps->sel == 1 && semi) || (ps->sel == 2 && !semi)) return 0;
		float e = semi ? ps->semi_scale : 1.0f;
		out[0] = c[0] * e; out[1] = c[1] * e; out[2] = c[2] * e; out[3] = semi ? ps->semi_alpha : 1.0f;
		return 1;
	} else {
		if (ps->sel == 1 && fl[3] > 0.5f) return 0;
		float e = fl[3] > 0.5f ? ps->semi_scale : 1.0f;
		out[0] = col[0] * e; out[1] = col[1] * e; out[2] = col[2] * e; out[3] = fl[3] > 0.5f ? ps->semi_alpha : 1.0f;
		return 1;
	}
}

// ---------------------------------------------------------------- vértices (canvas.glsl + módulo draw do Mesa)
#define NATR 5   // atributos que variam: u, v, r, g, b
typedef struct {
	float x, y;          // janela
	int fx, fy;          // ponto fixo (x - 0,5) * 256
	float a[NATR];
	float fl[4], pc[4];
} VJ;

static void vertice(const Vert *v, VJ *o) {
	// model_matrix * vec4(v, 0, 1): colunas (sx, 0), (-0, sy), origem 0
	volatile float mx0 = esc_x * (float)v->px, mx1 = -0.0f * (float)v->py;
	volatile float my0 = 0.0f * (float)v->px, my1 = esc_y * (float)v->py;
	volatile float mx = mx0 + mx1, my = my0 + my1;
	mx = mx + 0.0f; my = my + 0.0f;
	// canvas_transform (identidade) e snap: floor(vertex + 0.5)
	volatile float sx = mx + 0.5f, sy = my + 0.5f;
	float X = piso(sx), Y = piso(sy);
	// screen_transform: 2/320, 2/240, origem -1 (Transform3D do Godot em float)
	const float st00 = 2.0f / 320.0f, st11 = 2.0f / 240.0f;
	volatile float nx0 = st00 * X, ny0 = st11 * Y;
	volatile float nx = nx0 + (-1.0f), ny = ny0 + (-1.0f);
	// draw: x * (1/w) e janela = fmuladd(ndc, escala, translação) (viewport 320x240, FBO sem inverter)
	o->x = fma_f(nx, 160.0f, 160.0f);
	o->y = fma_f(ny, 120.0f, 120.0f);
	volatile float qx = o->x - 0.5f, qy = o->y - 0.5f;
	volatile float rx = qx * 256.0f, ry = qy * 256.0f;
	o->fx = arred_par(rx); o->fy = arred_par(ry);
	// atributos: cor do vértice em 8 bits normalizados (x * (1/255) na leitura), UV e CUSTOM0 em float
	const float i255 = (float)(1.0 / 255.0);
	o->a[0] = (float)v->pu; o->a[1] = (float)v->pv;
	for (int k = 0; k < 3; k++) o->a[2 + k] = (float)v->c[k] * i255;
	volatile float al = (float)v->c[3] * i255;
	volatile float al255 = al * 255.0f;
	int fl = arred_par(al255);
	o->fl[0] = (float)(fl & 3);
	o->fl[1] = (float)((fl >> 2) & 1) + (float)((fl >> 5) & 1);
	o->fl[2] = (float)((fl >> 3) & 1);
	o->fl[3] = (float)((fl >> 4) & 1);
	for (int k = 0; k < 4; k++) o->pc[k] = v->c0[k];
}

// ---------------------------------------------------------------- triângulo (lp_setup_tri.c + lp_state_setup.c)
static void triangulo(const VJ *a, const VJ *b, const VJ *c, const Passada *ps) {
	const VJ *v0 = a, *v1 = b, *v2 = c;
	int64_t dx01 = v0->fx - v1->fx, dy01 = v0->fy - v1->fy, dx20 = v2->fx - v0->fx, dy20 = v2->fy - v0->fy;
	int64_t area = dx01 * dy20 - dx20 * dy01;
	if (area == 0) return;
	if (area < 0) { const VJ *t = v0; v0 = v1; v1 = t; }   // flatshade_first = falso: troca v0 e v1
	// planos das bordas (ponto fixo), regra de cima/esquerda (FBO: bottom_edge_rule = 0)
	int64_t X[3] = { v0->fx, v1->fx, v2->fx }, Y[3] = { v0->fy, v1->fy, v2->fy };
	int64_t pdx[3], pdy[3], pc_[3];
	for (int i = 0; i < 3; i++) {
		int j = (i + 1) % 3;
		pdx[i] = Y[i] - Y[j];   // dcdx
		pdy[i] = X[i] - X[j];   // dcdy
		pc_[i] = pdx[i] * X[i] - pdy[i] * Y[i];
		if (pdx[i] < 0 || (pdx[i] == 0 && pdy[i] >= 0)) pc_[i] += 1;
		pdx[i] *= 256; pdy[i] *= 256;
	}
	// caixa: pixels de min >> 8 até (max - 1) >> 8
	int64_t mnx = X[0], mxx = X[0], mny = Y[0], mxy = Y[0];
	for (int i = 1; i < 3; i++) { if (X[i] < mnx) mnx = X[i]; if (X[i] > mxx) mxx = X[i]; if (Y[i] < mny) mny = Y[i]; if (Y[i] > mxy) mxy = Y[i]; }
	int bx0 = (int)(mnx >> 8), bx1 = (int)((mxx - 1) >> 8), by0 = (int)(mny >> 8), by1 = (int)((mxy - 1) >> 8);
	if (bx0 < 0) bx0 = 0;
	if (by0 < 0) by0 = 0;
	if (bx1 > LARG - 1) bx1 = LARG - 1;
	if (by1 > ALT - 1) by1 = ALT - 1;
	if (bx0 > bx1 || by0 > by1) return;
	// planos dos atributos (ordem das contas do llvmpipe, sem FMA)
	volatile float x0c = v0->x - 0.5f, y0c = v0->y - 0.5f;
	volatile float fdx01 = v0->x - v1->x, fdy01 = v0->y - v1->y, fdx20 = v2->x - v0->x, fdy20 = v2->y - v0->y;
	volatile float e = fdx01 * fdy20, f = fdy01 * fdx20;
	volatile float ef = e - f;
	volatile float ooa = 1.0f / ef;
	volatile float dx20o = fdx20 * ooa, dy20o = fdy20 * ooa, dx01o = fdx01 * ooa, dy01o = fdy01 * ooa;
	float a0[NATR], dadx[NATR], dady[NATR];
	for (int k = 0; k < NATR; k++) {
		volatile float da01 = v0->a[k] - v1->a[k], da20 = v2->a[k] - v0->a[k];
		volatile float t1 = da01 * dy20o, t2 = da20 * dy01o;
		volatile float ddx = t1 - t2;
		volatile float t3 = da20 * dx01o, t4 = da01 * dx20o;
		volatile float ddy = t3 - t4;
		volatile float s1 = ddx * x0c, s2 = ddy * y0c;
		volatile float s = s1 + s2;
		a0[k] = v0->a[k] - s; dadx[k] = ddx; dady[k] = ddy;
	}
	for (int py = by0; py <= by1; py++) {
		for (int px = bx0; px <= bx1; px++) {
			int dentro = 1;
			for (int i = 0; i < 3 && dentro; i++) {
				int64_t E = pc_[i] + pdy[i] * py - pdx[i] * px;
				if (E <= 0) dentro = 0;
			}
			if (!dentro) continue;
			float at[NATR];
			for (int k = 0; k < NATR; k++) at[k] = fma_f(dady[k], (float)py, fma_f(dadx[k], (float)px, a0[k]));
			float out[4];
			if (!fragmento(ps, v0->fl, v0->pc, at[0], at[1], at + 2, out)) continue;
			mistura(px, py, out, ps->modo);
		}
	}
}

static void desenha_malha(const Malha *m, int modo) {
	Passada pss[2]; int np = 0;
	if (modo < 0) { pss[0] = (Passada){ 0, 0, 1.0f, 1.0f }; np = 1; }
	else {
		pss[0] = (Passada){ 1, 0, 1.0f, 1.0f };
		static const int bl[4] = { 0, 1, 2, 1 };
		pss[1] = (Passada){ 2, bl[modo], modo == 0 ? 0.5f : 1.0f, modo == 3 ? 0.25f : 1.0f };
		np = 2;
	}
	VJ *vj = malloc(sizeof(VJ) * (size_t)(m->nv ? m->nv : 1));
	for (int i = 0; i < m->nv; i++) vertice(&m->v[i], &vj[i]);
	for (int p = 0; p < np; p++)
		for (int t = 0; t + 2 < m->ni; t += 3) triangulo(&vj[m->i[t]], &vj[m->i[t + 1]], &vj[m->i[t + 2]], &pss[p]);
	free(vj);
}

static void m_vert(Malha *m, Vert v) {
	if (m->nv == m->cv) { m->cv = m->cv ? m->cv * 2 : 256; m->v = realloc(m->v, sizeof(Vert) * (size_t)m->cv); }
	m->v[m->nv++] = v;
}
static void m_ind(Malha *m, int i) {
	if (m->ni == m->ci) { m->ci = m->ci ? m->ci * 2 : 512; m->i = realloc(m->i, sizeof(int) * (size_t)m->ci); }
	m->i[m->ni++] = i;
}

static int s11(int v) { v &= 0x7FF; return v >= 0x400 ? v - 0x800 : v; }

// ---------------------------------------------------------------- o fluxo de primitivas (X4Machine._render)
static void desenha_quadro(const int32_t *w, int total) {
	Malha m = { 0 };
	int run_mode = -2;
	int px[4], py[4], pu[4], pv[4], pcor[4];
	int ip = 0;
	while (ip < total) {
		int ws = w[ip];
		int o = ip + 1;
		ip += ws + 1;
		if (ws <= 0 || ip > total) break;
		uint32_t w0 = (uint32_t)w[o];
		int cmd = (w0 >> 24) & 0xFF;
		if (cmd == 0xE1) {
			tpx = (w0 & 15) * 64; tpy = ((w0 >> 4) & 1) * 256; tabr = (w0 >> 5) & 3; tdepth = (w0 >> 7) & 3;
			continue;
		}
		int n = 0, absoluto = 0, tex = (cmd & 4) != 0;
		int pgx = tpx, pgy = tpy, dep = tdepth, abr = tabr, clut = 0;
		if (cmd >= 0x20 && cmd < 0x40) {
			int gour = (cmd & 0x10) != 0;
			n = (cmd & 8) ? 4 : 3;
			int i = 1;
			int c = w0 & 0xFFFFFF;
			for (int k = 0; k < n; k++) {
				if (k > 0 && gour) {
					if (i >= ws) { n = 0; break; }
					c = w[o + i] & 0xFFFFFF; i++;
				}
				if (i >= ws) { n = 0; break; }
				uint32_t xy = (uint32_t)w[o + i]; i++;
				px[k] = s11(xy & 0x7FF); py[k] = s11((xy >> 16) & 0x7FF); pcor[k] = c;
				if (tex) {
					if (i >= ws) { n = 0; break; }
					uint32_t uvw = (uint32_t)w[o + i]; i++;
					pu[k] = uvw & 0xFF; pv[k] = (uvw >> 8) & 0xFF;
					if (k == 0) clut = (uvw >> 16) & 0xFFFF;
					else if (k == 1) {
						int page = (uvw >> 16) & 0xFFFF;
						pgx = (page & 15) * 64; pgy = ((page >> 4) & 1) * 256;
						dep = (page >> 7) & 3; abr = (page >> 5) & 3;
					}
				} else { pu[k] = 0; pv[k] = 0; }
			}
		} else if (cmd >= 0x60 && cmd < 0x80) {
			if (ws < 2) continue;
			uint32_t xy = (uint32_t)w[o + 1];
			int x = s11(xy & 0x7FF), y = s11((xy >> 16) & 0x7FF);
			int u0 = 0, v0 = 0, i2 = 2;
			if (tex) {
				if (ws < 3) continue;
				u0 = w[o + 2] & 0xFF; v0 = (w[o + 2] >> 8) & 0xFF; clut = (w[o + 2] >> 16) & 0xFFFF; i2 = 3;
			}
			int ww = 1, hh = 1;
			switch ((cmd >> 3) & 3) {
			case 0:
				if (i2 >= ws) continue;
				ww = w[o + i2] & 0xFFFF; hh = (w[o + i2] >> 16) & 0xFFFF;
				break;
			case 2: ww = 8; hh = 8; break;
			case 3: ww = 16; hh = 16; break;
			}
			n = 4;
			px[0] = x; py[0] = y; px[1] = x + ww; py[1] = y; px[2] = x; py[2] = y + hh; px[3] = x + ww; py[3] = y + hh;
			pu[0] = u0; pv[0] = v0; pu[1] = u0 + ww; pv[1] = v0; pu[2] = u0; pv[2] = v0 + hh; pu[3] = u0 + ww; pv[3] = v0 + hh;
			int c2 = w0 & 0xFFFFFF;
			for (int k = 0; k < 4; k++) pcor[k] = c2;
		} else if (cmd == 0x02) {
			if (ws < 3) continue;
			int ww3 = ((w[o + 2] & 0x3FF) + 15) & ~15, hh3 = (w[o + 2] >> 16) & 0x1FF;
			n = 4; tex = 0;
			px[0] = 0; py[0] = 0; px[1] = ww3; py[1] = 0; px[2] = 0; py[2] = hh3; px[3] = ww3; py[3] = hh3;
			int c3 = w0 & 0xFFFFFF;
			for (int k = 0; k < 4; k++) { pu[k] = 0; pv[k] = 0; pcor[k] = c3; }
			cmd = 0x60;
		} else if (cmd == 0xF1) {
			if (ws >= 2) {
				int sw = w[o + 1] & 0xFFFF, sh = (w[o + 1] >> 16) & 0xFFFF;
				if (sw > 0 && sh > 0) { esc_x = (float)(320.0 / sw); esc_y = (float)(240.0 / sh); }
			}
			continue;
		} else if (cmd == 0xF0) {
			if (ws < 3) continue;
			int dw = w[o + 2] & 0xFFFF, dh = (w[o + 2] >> 16) & 0xFFFF;
			pgx = w[o + 1] & 0x3FF; pgy = (w[o + 1] >> 16) & 0x1FF;
			dep = (w0 & 1) ? 3 : 2;
			n = 4; tex = 1; absoluto = 1;
			px[0] = 0; py[0] = 0; px[1] = 320; py[1] = 0; px[2] = 0; py[2] = 240; px[3] = 320; py[3] = 240;
			pu[0] = 0; pv[0] = 0; pu[1] = dw; pv[1] = 0; pu[2] = 0; pv[2] = dh; pu[3] = dw; pv[3] = dh;
			for (int k = 0; k < 4; k++) pcor[k] = 0x808080;
			cmd = 0x65;
		} else continue;
		if (n == 0) continue;
		int cru = (cmd & 1) != 0;
		int semi = (cmd & 2) != 0;
		int mode = semi ? abr : -1;
		if (mode != run_mode && m.nv > 0) { desenha_malha(&m, run_mode); m.nv = 0; m.ni = 0; }
		run_mode = mode;
		int fl = dep | (tex && !absoluto ? 4 : 0) | (cru ? 8 : 0) | (semi ? 16 : 0) | (absoluto ? 32 : 0);
		int base = m.nv;
		float cx = (float)(clut & 63) * 16.0f, cy = (float)((clut >> 6) & 511);
		for (int k = 0; k < n; k++) {
			Vert v;
			v.px = px[k]; v.py = py[k]; v.pu = pu[k]; v.pv = pv[k];
			v.c[0] = pcor[k] & 0xFF; v.c[1] = (pcor[k] >> 8) & 0xFF; v.c[2] = (pcor[k] >> 16) & 0xFF; v.c[3] = (uint8_t)fl;
			v.c0[0] = (float)pgx; v.c0[1] = (float)pgy; v.c0[2] = cx; v.c0[3] = cy;
			m_vert(&m, v);
		}
		m_ind(&m, base); m_ind(&m, base + 1); m_ind(&m, base + 2);
		if (n == 4) { m_ind(&m, base + 1); m_ind(&m, base + 3); m_ind(&m, base + 2); }
	}
	if (m.nv > 0) desenha_malha(&m, run_mode);
	free(m.v); free(m.i);
}

static unsigned char *le_tudo(const char *c, long *n) {
	FILE *f = fopen(c, "rb");
	if (!f) return NULL;
	fseek(f, 0, SEEK_END); *n = ftell(f); fseek(f, 0, SEEK_SET);
	unsigned char *b = malloc((size_t)*n + 4);
	if (b && fread(b, 1, (size_t)*n, f) != (size_t)*n) { free(b); b = NULL; }
	fclose(f);
	return b;
}

int desenho_main(int argc, char **argv) {
	if (argc < 4) { fprintf(stderr, "uso: captura desenha PASTA N1,N2,...\n"); return 2; }
	const char *pasta = argv[2];
	char *lista = strdup(argv[3]);
	int feitos = 0;
	// cor de limpeza da tela do Godot (0,3; 0,3; 0,3) em 10 bits: round(0,3 * 1023) = 307
	for (char *k = strtok(lista, ","); k; k = strtok(NULL, ",")) {
		char c[4096]; long nv = 0, np = 0;
		snprintf(c, sizeof c, "%s/v_%s.bin", pasta, k);
		unsigned char *v = le_tudo(c, &nv);
		snprintf(c, sizeof c, "%s/p_%s.bin", pasta, k);
		unsigned char *p = le_tudo(c, &np);
		if (!v || !p || nv != 1024 * 512 * 2) { fprintf(stderr, "desenha: faltam as fotos do quadro %s\n", k); return 1; }
		vram = (uint16_t *)v;
		for (int y = 0; y < ALT; y++) for (int x = 0; x < LARG; x++) for (int q = 0; q < 3; q++) tela[y][x][q] = 307;
		desenha_quadro((const int32_t *)p, (int)(np / 4));
		unsigned char *rgba = malloc(LARG * ALT * 4);
		for (int y = 0; y < ALT; y++)
			for (int x = 0; x < LARG; x++) {
				for (int q = 0; q < 3; q++) rgba[(y * LARG + x) * 4 + q] = (unsigned char)((tela[y][x][q] * 255u + 511u) / 1023u);
				rgba[(y * LARG + x) * 4 + 3] = 255;
			}
		snprintf(c, sizeof c, "%s/tela_%s.rgba.tmp", pasta, k);
		FILE *f = fopen(c, "wb");
		if (!f || fwrite(rgba, 1, LARG * ALT * 4, f) != LARG * ALT * 4) { fprintf(stderr, "desenha: não gravou %s\n", c); return 1; }
		fclose(f);
		char d[4096]; snprintf(d, sizeof d, "%s/tela_%s.rgba", pasta, k);
		remove(d);
		if (rename(c, d) != 0) { fprintf(stderr, "desenha: não renomeou %s\n", c); return 1; }
		free(rgba); free(v); free(p);
		feitos++;
	}
	printf("desenha: %d telas\n", feitos);
	return 0;
}

#ifdef DESENHO_SOZINHO
int main(int argc, char **argv) { return desenho_main(argc, argv); }
#endif
