extends RefCounted
## Peças das armaduras do X (assets/x/parts): o desenho e as cores saem dos pacotes dos discos do jogador
## (ROCK_X5.DAT, ROCK_X6.DAT e ARC/PL00_U.ARC / PL02_U.ARC do X4). A receita (pecas/receita.json, nossa) só diz
## qual quadro de qual pacote vai em cada lugar do atlas e com qual paleta do banco; a máscara (pecas/mascaras, sem
## cor) diz quais pontos ficam quando o quadro é só um pedaço da armadura (capacete, corpo, braço ou pernas).
## As variantes de cor da carga (atlas_cN, base_cN) são as mesmas contas do recolor.py do PC do dono.

const DATS := {"x5": "ROCK_X5.DAT", "x6": "ROCK_X6.DAT"}

var discos: Dictionary
var _dat := {}     # jogo -> {lba, ind: [[byte_ini, tam], ...]}
var _pk := {}      # "jogo|pacote" -> {grupos: Array, tiles: PackedByteArray, banco: PackedInt32Array}
var _tb := {}      # "jogo|pacote|quadro" -> {nib: PackedByteArray, base: PackedInt32Array, passo: PackedInt32Array}

func _init(d: Dictionary) -> void:
	discos = d

# ---------------- leitura dos pacotes ----------------
func _dados_dat(g: String) -> Dictionary:
	if _dat.has(g): return _dat[g]
	var d = discos[g]
	var arq: Array = d.arquivos()[DATS[g]]
	var lba: int = arq[0]
	var cab: PackedByteArray = d.dados(lba, 1)
	var prim := cab.decode_u32(0)   # setor do primeiro pacote = tamanho do índice
	var idx: PackedByteArray = d.dados(lba, prim)
	var ind := []
	var i := 0
	while i * 8 < prim * 2048:
		var s := idx.decode_u32(i * 8); var t := idx.decode_u32(i * 8 + 4)
		if s == 0 and t == 0: break
		ind.append([s * 2048, t]); i += 1
	_dat[g] = {"lba": lba, "ind": ind}
	return _dat[g]

static func _p(p):   # número do pacote no DAT (o JSON traz número com vírgula) ou nome do arquivo do X4
	return int(p) if (p is float or p is int) else str(p)

func _bytes_pacote(g: String, p) -> PackedByteArray:
	p = _p(p)
	var d = discos[g]
	if g == "x4":
		var a: Array = d.arquivos()[str(p)]
		return d.dados(a[0], (int(a[1]) + 2047) / 2048).slice(0, a[1])
	var dt := _dados_dat(g)
	var e: Array = dt.ind[int(p)]
	return d.dados(dt.lba + int(e[0]) / 2048, (int(e[1]) + 2047) / 2048).slice(0, e[1])

## pacote ARC: n entradas (tipo, tamanho) a partir do byte 8, dados alinhados em 0x800
static func entradas_arc(b: PackedByteArray) -> Array:
	var n := b.decode_u32(0)
	var out := []
	var off := 0x800
	for i in n:
		var t := b.decode_u32(8 + i * 8); var s := b.decode_u32(12 + i * 8)
		out.append([t, b.slice(off, off + s)])
		off += (s + 0x7ff) & ~0x7ff
	return out

func pacote(g: String, p) -> Dictionary:
	p = _p(p)
	var k := "%s|%s" % [g, str(p)]
	if _pk.has(k): return _pk[k]
	var es := entradas_arc(_bytes_pacote(g, p))
	var r := {}
	for e in es:
		var t: int = e[0]
		if t == 3 and not r.has("grupos"): r.grupos = grupos(e[1])
		elif t == 2 and not r.has("tiles"): r.tiles = e[1]
		elif t == 9 and not r.has("banco"): r.banco = _u16(e[1])
	_pk[k] = r
	return r

static func _u16(b: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array(); out.resize(b.size() / 2)
	for i in out.size(): out[i] = b.decode_u16(i * 2)
	return out

## quadros (tipo 3): grupos -> quadros -> peças [flags, tile, x, y] (x/y com sinal)
static func grupos(b: PackedByteArray) -> Array:
	var g0 := b.decode_u32(0)
	var out := []
	for j in g0 / 4:
		var g := b.decode_u32(j * 4)
		var fr := []
		if g + 4 <= b.size():
			var nq := b.decode_u16(g + 2)
			for f in nq:
				var c := b.decode_u16(g + f * 4); var st := b.decode_u16(g + f * 4 + 2)
				var pc := PackedInt32Array()
				for q in c:
					var o := g + (st + q) * 4
					pc.append(b[o]); pc.append(b[o + 1]); pc.append(b.decode_s8(o + 2)); pc.append(b.decode_s8(o + 3))
				fr.append(pc)
		out.append(fr)
	return out

## descompressão dos tiles (palavras de 16 bits; mesma conta do capdec.py)
static func descomprime(b: PackedByteArray, p: int) -> PackedByteArray:
	var out := PackedInt32Array()
	while p + 2 <= b.size():
		var fl := b.decode_u16(p); p += 2
		var m := 0x8000
		for _k in 16:
			if (fl & m) == 0:
				out.append(b.decode_u16(p)); p += 2
			else:
				var t := b.decode_u16(p); p += 2
				var n: int
				var off: int
				if t & 0xf800:
					n = t >> 11; off = t & 0x7ff
				else:
					n = b.decode_u16(p); p += 2; off = t
				if n == 0 and off == 0:
					var r := PackedByteArray(); r.resize(out.size() * 2)
					for i in out.size(): r.encode_u16(i * 2, out[i])
					return r
				if off == 0:
					for _j in n: out.append(0)
				else:
					for _j in n: out.append(out[out.size() - off])
			m >>= 1
	return PackedByteArray()

## tiles 16x16 de 4 bits do quadro i (tabela 0 do tipo 2): nib = pontos, base/passo = onde começa cada tile
func tiles(g: String, p, i: int) -> Dictionary:
	p = _p(p)
	var k := "%s|%s|%d" % [g, str(p), i]
	if _tb.has(k): return _tb[k]
	var T: PackedByteArray = pacote(g, p).tiles
	var base0 := T.decode_u32(0)
	var w := T.decode_u32(base0 + i * 4)
	var nt := w >> 20
	var raw := descomprime(T, base0 + (w & 0xfffff))
	var nib := PackedByteArray(); nib.resize(raw.size() * 2)
	for j in raw.size():
		var v := raw[j]
		nib[j * 2] = v & 15; nib[j * 2 + 1] = v >> 4
	var bases := PackedInt32Array(); var passos := PackedInt32Array()
	var kk := 0; var rem := nt
	var ok := true
	while rem > 0:
		var wpx: int; var h: int; var used: int
		if rem >= 16:
			wpx = 256; h = 16 * (rem / 16); used = h / 16 * 16
		else:
			wpx = rem * 16; h = 16; used = rem
		if kk + wpx * h > nib.size(): ok = false; break
		for ty in h / 16:
			for tx in wpx / 16:
				bases.append(kk + ty * 16 * wpx + tx * 16); passos.append(wpx)
		kk += wpx * h; rem -= used
	if not ok: bases = PackedInt32Array(); passos = PackedInt32Array()
	_tb[k] = {"nib": nib, "base": bases, "passo": passos}
	return _tb[k]

# ---------------- desenho ----------------
## pontos do quadro i nas camadas ls (cada camada por cima da anterior, peças na ordem):
## devolve [xs, ys, valores] (valor = paleta*16 + índice) na ordem de desenho
func pontos(g: String, p, ls: Array, i: int, vira_h: bool) -> Array:
	var pk := pacote(g, p)
	var G: Array = pk.grupos
	var tb := tiles(g, p, i)
	var nib: PackedByteArray = tb.nib; var bases: PackedInt32Array = tb.base; var passos: PackedInt32Array = tb.passo
	var xs := PackedInt32Array(); var ys := PackedInt32Array(); var vs := PackedInt32Array()
	for gf in ls:
		var gi := int(gf)
		if gi >= G.size() or i >= G[gi].size(): continue
		var pc: PackedInt32Array = G[gi][i]
		if pc.is_empty(): continue
		var ok := true
		for q in range(0, pc.size(), 4):
			if pc[q + 1] >= bases.size(): ok = false; break
		if not ok: continue   # camada com tile que não existe: fica de fora (como no PC do dono)
		for q in range(0, pc.size(), 4):
			var fl := pc[q]; var b0 := bases[pc[q + 1]]; var st := passos[pc[q + 1]]
			var px := pc[q + 2]; var py := pc[q + 3]
			var hf := vira_h and (fl & 0x40) != 0
			var pal := (fl & 15) << 4
			for r in 16:
				var lin := b0 + r * st
				for c in 16:
					var t := nib[lin + (15 - c if hf else c)]
					if t == 0: continue
					xs.append(px + c); ys.append(py + r); vs.append(pal | t)
	return [xs, ys, vs]

static func cor(c: int) -> int:   # 15 bits do PS1 -> RGBA8 empacotado (R | G<<8 | B<<16 | A<<24)
	c &= 0x7fff
	return ((c & 31) << 3) | ((((c >> 5) & 31) << 3) << 8) | ((((c >> 10) & 31) << 3) << 16) | (255 << 24)

func monta_atlas(nome: String, e: Dictionary, frames: Array, mascara: PackedByteArray) -> PackedInt32Array:
	var W := int(e.tam[0]); var H := int(e.tam[1])
	var px := PackedInt32Array(); px.resize(W * H)
	var vira: bool = e.vira_h
	for s in e.get("soltos", []):   # quadros antigos que ficaram no atlas fora da lista (desenho inteiro)
		var pt := pontos(str(s[2]), s[3], s[4], int(s[5]), vira)
		var pm := {}
		for par in s[6]: pm[int(par[0])] = int(par[1])
		var banco: PackedInt32Array = pacote(str(s[2]), s[3]).banco
		var xs: PackedInt32Array = pt[0]; var ys: PackedInt32Array = pt[1]; var vs: PackedInt32Array = pt[2]
		if xs.is_empty(): continue
		var mx := 1 << 30; var my := 1 << 30; var Mx := -(1 << 30); var My := -(1 << 30)
		for j in xs.size():
			mx = mini(mx, xs[j]); my = mini(my, ys[j]); Mx = maxi(Mx, xs[j]); My = maxi(My, ys[j])
		var lw := Mx - mx + 1; var lh := My - my + 1
		var loc := PackedInt32Array(); loc.resize(lw * lh); loc.fill(-1)
		for j in xs.size(): loc[(ys[j] - my) * lw + xs[j] - mx] = vs[j]
		for ay in lh:
			for ax in lw:
				var v := loc[ay * lw + ax]
				if v < 0: continue
				px[(int(s[1]) + ay) * W + int(s[0]) + ax] = cor(banco[pm[v >> 4] * 16 + (v & 15)])
	for q in e.quadros:
		var c := int(q[0])
		var f: Dictionary = frames[c]
		var fx := int(f.x); var fy := int(f.y); var fw := int(f.w); var fh := int(f.h); var ox := int(f.ox); var oy := int(f.oy)
		var masc: bool = int(q[6]) == 1
		var pm := {}
		for par in q[5]: pm[int(par[0])] = int(par[1])
		var banco: PackedInt32Array = pacote(str(q[1]), q[2]).banco
		var pt := pontos(str(q[1]), q[2], q[3], int(q[4]), vira)
		var xs: PackedInt32Array = pt[0]; var ys: PackedInt32Array = pt[1]; var vs: PackedInt32Array = pt[2]
		var loc := PackedInt32Array(); loc.resize(fw * fh); loc.fill(-1)   # o desenho final do quadro (por cima vence)
		for j in xs.size():
			var ax := xs[j] + ox; var ay := ys[j] + oy
			if ax < 0 or ay < 0 or ax >= fw or ay >= fh: continue
			loc[ay * fw + ax] = vs[j]
		for ay in fh:
			for ax in fw:
				var v := loc[ay * fw + ax]
				if v < 0: continue
				var o := (fy + ay) * W + fx + ax
				if masc and mascara[o] == 0: continue
				px[o] = cor(banco[pm[v >> 4] * 16 + (v & 15)])
	return px

# ---------------- cores da carga (recolor.py) ----------------
var _lut := {}
func _linha(spec: Array) -> PackedInt32Array:
	if spec[2] == "banco":
		return pacote(str(spec[0]), spec[1]).banco.slice(int(spec[3]) * 16, int(spec[3]) * 16 + 16)
	# paleta de trabalho da fase (tipo 5) de um pacote do DAT
	var es := entradas_arc(_bytes_pacote(str(spec[0]), spec[1]))
	for e in es:
		if e[0] == 5: return _u16(e[1]).slice(int(spec[3]) * 16, int(spec[3]) * 16 + 16)
	return PackedInt32Array()

static func _rgb(c: int) -> Vector3i:
	return Vector3i((c & 31) << 3, ((c >> 5) & 31) << 3, ((c >> 10) & 31) << 3)

## paletas[v] = 4 linhas de 16 (0x7800, 0x7843, 0x7844, 0x7802) para v = 0 (normal) .. 3
func paletas(ce: Dictionary) -> Array:
	var banco: PackedInt32Array = pacote(str(ce.pacote[0]), ce.pacote[1]).banco
	var l2 := _linha(ce.linha2); var l3 := _linha(ce.linha3)
	var out := []
	for par in ce.paletas:
		out.append([banco.slice(int(par[0]) * 16, int(par[0]) * 16 + 16), banco.slice(int(par[1]) * 16, int(par[1]) * 16 + 16), l2, l3])
	return out

## troca de cor de cada ponto, igual ao recolor.py: a cor mais próxima da paleta normal (a primeira, se empatar)
## vira a cor da mesma posição na variante; se não for igual, soma a diferença (limitada a 0..255)
func recolore(px: PackedInt32Array, pals: Array, v: int) -> PackedInt32Array:
	var src := []
	for ci in 4:
		for i in range(1, 16): src.append([_rgb(pals[0][ci][i]), ci, i])
	var lut := {}
	var out := px.duplicate()
	for j in px.size():
		var c := px[j]
		if c >= 0: continue   # transparente (alfa 0 deixa o inteiro positivo)
		if lut.has(c):
			out[j] = lut[c]; continue
		var t := Vector3i(c & 255, (c >> 8) & 255, (c >> 16) & 255)
		var best := -1; var bd := 1 << 30
		for k in src.size():
			var dv: Vector3i = src[k][0] - t
			var d := dv.x * dv.x + dv.y * dv.y + dv.z * dv.z
			if d < bd: bd = d; best = k
		var nv := _rgb(pals[v][src[best][1]][src[best][2]])
		var r: Vector3i
		if bd == 0: r = nv
		else: r = (t + nv - src[best][0]).clamp(Vector3i.ZERO, Vector3i(255, 255, 255))
		var nc := r.x | (r.y << 8) | (r.z << 16) | (c & (255 << 24))
		lut[c] = nc; out[j] = nc
	return out

# ---------------- grupo inteiro ----------------
static func le_frames(caminho: String) -> Array:
	var j = JSON.parse_string(FileAccess.get_file_as_string(caminho))
	if j is Dictionary: return j.frames
	return j

static func grava_png(px: PackedInt32Array, W: int, H: int, dst: String) -> bool:
	var im := Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, px.to_byte_array())
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	return im.save_png(dst) == OK

static func le_png(caminho: String) -> Array:
	var im := Image.load_from_file(caminho)
	if im == null: return []
	im.convert(Image.FORMAT_RGBA8)
	return [im.get_data().to_int32_array(), im.get_width(), im.get_height()]

## monta tudo em JOGO/assets/x/parts; base = pasta tools/extrator/pecas
func roda(jogo: String, base: String, prog: Callable) -> int:
	var rec = JSON.parse_string(FileAccess.get_file_as_string(base.path_join("receita.json")))
	if not rec is Dictionary: printerr("receita das peças estragada"); return -1
	var dst := jogo.path_join("assets/x/parts")
	var n := 0
	# 1) metadados nossos (quadros, mapa canônico...)
	var js := base.path_join("json")
	var pilha := [""]
	while not pilha.is_empty():
		var rel: String = pilha.pop_back()
		for sd in DirAccess.get_directories_at(js.path_join(rel)): pilha.append(rel.path_join(sd))
		for f in DirAccess.get_files_at(js.path_join(rel)):
			DirAccess.make_dir_recursive_absolute(dst.path_join(rel))
			DirAccess.copy_absolute(js.path_join(rel).path_join(f), dst.path_join(rel).path_join(f)); n += 1
	# 2) atlas desenhados dos pacotes
	var nomes: Array = rec.atlas.keys()
	var feitos := {}
	for k in nomes.size():
		var nm: String = nomes[k]
		var e: Dictionary = rec.atlas[nm]
		prog.call(k, nomes.size() + rec.cores.size(), "peças: " + nm)
		var frames := le_frames(dst.path_join(nm).path_join("frames.json"))
		var masc := PackedByteArray()
		if e.has("mascara"):
			var mi := Image.load_from_file(base.path_join(e.mascara))
			mi.convert(Image.FORMAT_L8); masc = mi.get_data()
		var px := monta_atlas(nm, e, frames, masc)
		if not grava_png(px, int(e.tam[0]), int(e.tam[1]), dst.path_join(nm).path_join("atlas.png")): return -1
		feitos[nm] = [px, int(e.tam[0]), int(e.tam[1])]
		n += 1
	# 3) cores da carga (c1..c3) de cada armadura
	var ks: Array = rec.cores.keys()
	for k in ks.size():
		var arm: String = ks[k]
		var ce: Dictionary = rec.cores[arm]
		prog.call(nomes.size() + k, nomes.size() + ks.size(), "cores da carga: " + arm)
		var pals := paletas(ce)
		for a in ce.atlas:
			var orig: String; var saida: String
			if a == "body>base":
				orig = "body"; saida = arm.path_join("base_c%d.png")
			else:
				orig = arm.path_join(a); saida = arm.path_join(a).path_join("atlas_c%d.png")
			var im: Array = feitos.get(orig, [])
			if im.is_empty():
				if not FileAccess.file_exists(dst.path_join(orig).path_join("atlas.png")): continue   # (voo: vem das capturas)
				im = le_png(dst.path_join(orig).path_join("atlas.png"))
			for v in range(1, pals.size()):
				if not grava_png(recolore(im[0], pals, v), im[1], im[2], dst.path_join(saida % v)): return -1
				n += 1
	return n
