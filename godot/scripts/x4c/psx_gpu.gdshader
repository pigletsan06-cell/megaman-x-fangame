shader_type canvas_item;
render_mode unshaded;
// GPU do PS1 em alto nível: lê a VRAM (1024x512, 16 bits por ponto em RG8) e a CLUT
uniform sampler2D vram : filter_nearest, repeat_disable;
uniform float semi_alpha = 1.0;      // 0.5 no modo de mistura 0
uniform float semi_scale = 1.0;      // 0.25 no modo 3
uniform int pass_sel = 0;            // 0 tudo, 1 só pontos opacos, 2 só semitransparentes
varying vec4 page_clut;               // x, y da página; x, y da CLUT
varying vec4 flags;                   // profundidade, texturizado, cru, semitransparente
varying vec2 tuv;

void vertex() {
	page_clut = CUSTOM0;
	int fl = int(round(COLOR.a * 255.0));
	flags = vec4(float(fl & 3), float((fl >> 2) & 1) + float((fl >> 5) & 1), float((fl >> 3) & 1), float((fl >> 4) & 1));
	tuv = UV;
}

int word_at(ivec2 p) {
	vec4 t = texelFetch(vram, ivec2(p.x & 1023, p.y & 511), 0);
	return int(round(t.r * 255.0)) | (int(round(t.g * 255.0)) << 8);
}

vec3 rgb15(int w) {
	return vec3(float(w & 31), float((w >> 5) & 31), float((w >> 10) & 31)) / 31.0;
}

void fragment() {
	vec4 col = COLOR;
	if (flags.y > 1.5) {
		// imagem direta da VRAM (vídeos e telas enviadas sem desenho), 15 ou 24 bits
		ivec2 t = ivec2(floor(tuv));
		ivec2 o = ivec2(page_clut.xy);
		if (int(flags.x + 0.5) == 3) {
			int bx = t.x * 3;
			int w0 = word_at(o + ivec2(bx >> 1, t.y));
			int w1 = word_at(o + ivec2((bx >> 1) + 1, t.y));
			int b0 = w0 & 255, b1 = (w0 >> 8) & 255, b2 = w1 & 255, b3 = (w1 >> 8) & 255;
			vec3 c = (bx & 1) == 0 ? vec3(float(b0), float(b1), float(b2)) : vec3(float(b1), float(b2), float(b3));
			COLOR = vec4(c / 255.0, 1.0);
		} else {
			COLOR = vec4(rgb15(word_at(o + t)), 1.0);
		}
	} else if (flags.y > 0.5) {
		ivec2 t = ivec2(floor(tuv));
		t = ivec2(t.x & 255, t.y & 255);
		ivec2 page = ivec2(page_clut.xy);
		int depth = int(flags.x + 0.5);
		int w;
		if (depth == 0) {
			int v = word_at(page + ivec2(t.x >> 2, t.y));
			int idx = (v >> ((t.x & 3) * 4)) & 15;
			w = word_at(ivec2(page_clut.zw) + ivec2(idx, 0));
		} else if (depth == 1) {
			int v = word_at(page + ivec2(t.x >> 1, t.y));
			int idx = (v >> ((t.x & 1) * 8)) & 255;
			w = word_at(ivec2(page_clut.zw) + ivec2(idx, 0));
		} else {
			w = word_at(page + t);
		}
		if (w == 0) discard;
		vec3 c = rgb15(w);
		if (flags.z < 0.5) c = clamp(c * col.rgb * 2.0, 0.0, 1.0);
		bool semi = flags.w > 0.5 && (w & 0x8000) != 0;
		if ((pass_sel == 1 && semi) || (pass_sel == 2 && !semi)) discard;
		COLOR = vec4(c * (semi ? semi_scale : 1.0), semi ? semi_alpha : 1.0);
	} else {
		if (pass_sel == 1 && flags.w > 0.5) discard;
		COLOR = vec4(col.rgb * (flags.w > 0.5 ? semi_scale : 1.0), flags.w > 0.5 ? semi_alpha : 1.0);
	}
}
