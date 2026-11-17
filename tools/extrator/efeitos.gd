extends RefCounted
## Efeitos das armaduras do X (voo, tiros, carga, Giga...): no PC do dono foram "fotografados" do jogo rodando
## (fusion/grab*.py). Aqui o nosso núcleo de PS1 (captura) roda os mesmos golpes com os discos do jogador e este
## script faz a mesma conta dos grab*.py: pega as peças desenhadas perto do objeto (tiro, X...), desenha cada uma
## com a textura da VRAM e recorta. A receita (pecas/efeitos.json, nossa) diz qual captura, qual quadro e qual
## objeto vai em cada lugar do atlas.

var opcoes: Dictionary
var discos: Dictionary
var pecas   # pecas.gd (paletas dos pacotes e as cores da carga)

func _init(op: Dictionary, d: Dictionary, p) -> void:
	opcoes = op; discos = d; pecas = p

func _op(k: String, env: String, padrao: String) -> String:
	if str(opcoes.get(k, "")) != "": return str(opcoes[k])
	if env != "" and OS.get_environment(env) != "": return OS.get_environment(env)
	return padrao

# ---------------- capturas ----------------
func roda_captura(nome: String, c: Dictionary, quadros: Array, dir: String) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	var jg: String = c.jogo
	var b := ""; var poke := ""
	var n := int(c.quadros)
	if jg == "x5":
		b = "start:700-710,down:830-835,down:870-875,down:910-915,cross:960-966,cross:1210-1216"
		for i in range(1900, 2601, 30): b += ",cross:%d-%d" % [i, i + 3]
		poke = "d1c0c:0001:1255-1600,d1c48:0%d00:1000-1800" % int(c.armadura)
	else:
		b = "start:900-905,cross:1000-1006,start:1400-1403,start:1460-1463"
		poke = "ccf2e:000%d:1010-%d,ccedc:%s:1440-1900" % [int(c.armadura), n, str(c.fase)]
	if str(c.extra) != "": b += "," + str(c.extra)
	for k in ["DUMP", "DUMP_FROM", "OBJLOG", "AUDIO", "AUDIO_FROM", "AUDIO_POR", "SPUDBG", "SPUDUMP", "RWATCH", "NORAM"]: OS.unset_environment(k)
	var ql := PackedStringArray()
	for q in quadros: ql.append(str(q))
	OS.set_environment("DUMPDIR", dir); OS.set_environment("POKE", poke); OS.set_environment("DUMP_LIST", ",".join(ql))
	var out := []
	var cap := _op("captura", "FUSION_CAPTURA", "captura")
	var code := OS.execute(cap, ["x", _op("bios", "FUSION_BIOS", ""), "DISC=" + str(discos[jg].caminho), str(n), b], out, true)
	for k in ["DUMPDIR", "POKE", "DUMP_LIST"]: OS.unset_environment(k)
	for q in quadros:
		if not FileAccess.file_exists(dir.path_join("r_%d.bin" % q)) or not FileAccess.file_exists(dir.path_join("v_%d.bin" % q)):
			printerr("a captura %s não fotografou o quadro %d (saída %d): %s" % [nome, q, code, str(out).right(300)])
			return false
	return true

# ---------------- peças desenhadas (mesma leitura do prims_full do grab.py) ----------------
static func _s11(v: int) -> int:
	return v - 0x800 if v >= 0x400 else v

static func prims(caminho: String) -> Array:
	var b := FileAccess.get_file_as_bytes(caminho)
	var n := b.size() / 4
	var out := []
	var ip := 0; var tpx := 0; var tpy := 0; var dep := 0
	while ip < n:
		var ws := b.decode_u32(ip * 4)
		var o := ip + 1
		ip += ws + 1
		if ws <= 0 or ws >= 0x80000000 or ip > n: break
		var w0 := b.decode_u32(o * 4)
		var cmd := w0 >> 24
		if cmd == 0xE1:
			tpx = (w0 & 15) * 64; tpy = ((w0 >> 4) & 1) * 256; dep = (w0 >> 7) & 3
			continue
		if not (cmd & 4): continue
		if cmd >= 0x60 and cmd < 0x80:
			var xy := b.decode_u32((o + 1) * 4)
			var x := _s11(xy & 0x7ff); var y := _s11((xy >> 16) & 0x7ff)
			var uvc := b.decode_u32((o + 2) * 4)
			var cl := uvc >> 16; var u := uvc & 0xff; var vv := (uvc >> 8) & 0xff
			var code := (cmd >> 3) & 3
			var sw := 0; var sh := 0
			if code == 2: sw = 8; sh = 8
			elif code == 3: sw = 16; sh = 16
			else:
				var wh := b.decode_u32((o + 3) * 4)
				sw = wh & 0xffff; sh = (wh >> 16) & 0xffff
			out.append({"P": [Vector2i(x, y), Vector2i(x + sw, y), Vector2i(x, y + sh), Vector2i(x + sw, y + sh)],
				"T": [Vector2i(u, vv), Vector2i(u + sw, vv), Vector2i(u, vv + sh), Vector2i(u + sw, vv + sh)],
				"clut": cl, "tpx": tpx, "tpy": tpy, "dep": dep})
		elif cmd >= 0x20 and cmd < 0x40:
			var nv := 4 if (cmd & 8) else 3
			var g := (cmd & 0x10) != 0
			var i := 1
			var P := []; var T := []
			var page := 0; var cl := 0
			for k in nv:
				if k > 0 and g: i += 1
				var xy := b.decode_u32((o + i) * 4); i += 1
				P.append(Vector2i(_s11(xy & 0x7ff), _s11((xy >> 16) & 0x7ff)))
				var uvw := b.decode_u32((o + i) * 4); i += 1
				T.append(Vector2i(uvw & 0xff, (uvw >> 8) & 0xff))
				if k == 0: cl = uvw >> 16
				if k == 1: page = uvw >> 16
			out.append({"P": P, "T": T, "clut": cl, "tpx": (page & 15) * 64, "tpy": ((page >> 4) & 1) * 256, "dep": (page >> 7) & 3})
	return out

static func sel_ok(pr: Dictionary, sel: Dictionary) -> bool:
	var inc := false
	for r in sel.inc:
		if _regra(pr, r): inc = true; break
	if not inc: return false
	for r in sel.get("exc", []):
		if _regra(pr, r): return false
	return true

static func _regra(pr: Dictionary, r: Dictionary) -> bool:
	if r.has("tpy") and pr.tpy != int(r.tpy): return false
	if r.has("tpx") and not _tem(r.tpx, pr.tpx): return false
	if r.has("clut") and not _tem(r.clut, pr.clut): return false
	if r.has("clut_lt") and not (pr.clut < int(r.clut_lt)): return false
	if r.has("tpx_ge") and not (pr.tpx >= int(r.tpx_ge)): return false
	return true

static func _tem(lista: Array, v: int) -> bool:
	for x in lista:
		if int(x) == v: return true
	return false

## texel do grab.py (0 = transparente); a VRAM é 1024x512 palavras de 16 bits
static func texel(v: PackedByteArray, tpx: int, tpy: int, dep: int, clut: int, u: int, vv: int) -> int:
	var cx := (clut & 63) * 16; var cy := (clut >> 6) & 511
	u &= 255
	var vy := (tpy + (vv & 255)) & 511
	if dep == 0:
		var t := (v.decode_u16((vy * 1024 + ((tpx + u / 4) & 1023)) * 2) >> ((u & 3) * 4)) & 15
		return 0 if t == 0 else v.decode_u16((cy * 1024 + cx + t) * 2) | 0x10000
	if dep == 1:
		var t := (v.decode_u16((vy * 1024 + ((tpx + u / 2) & 1023)) * 2) >> ((u & 1) * 8)) & 255
		return 0 if t == 0 else v.decode_u16((cy * 1024 + ((cx + t) & 1023)) * 2) | 0x10000
	return v.decode_u16((vy * 1024 + ((tpx + u) & 1023)) * 2) | 0x10000

## round(x, 3) do Python (meio para o par) e depois piso
static func _arred3_piso(x: float) -> int:
	var y := x * 1000.0
	var f := floorf(y)
	var r := y - f
	var n := f
	if r > 0.5: n = f + 1.0
	elif r == 0.5: n = f + 1.0 if int(f) % 2 != 0 else f
	return int(floorf(n / 1000.0))

## raster() do grab.py: dois triângulos, centro do ponto, pesos baricêntricos, textura sem filtro
static func raster(img: PackedInt32Array, C: int, v: PackedByteArray, pr: Dictionary, ox: int, oy: int, clamp_uv: bool, bb: PackedInt32Array) -> void:
	var Ps: Array = pr.P; var Ts: Array = pr.T
	var tpx: int = pr.tpx; var tpy: int = pr.tpy; var dep: int = pr.dep; var clut: int = pr.clut
	var tris := [[0, 1, 2], [1, 3, 2]] if Ps.size() == 4 else [[0, 1, 2]]
	for tr in tris:
		var A: Vector2i = Ps[tr[0]]; var B: Vector2i = Ps[tr[1]]; var Cc: Vector2i = Ps[tr[2]]
		var TA: Vector2i = Ts[tr[0]]; var TB: Vector2i = Ts[tr[1]]; var TC: Vector2i = Ts[tr[2]]
		var ax := A.x; var ay := A.y; var bx := B.x; var by := B.y; var cx := Cc.x; var cy := Cc.y
		var d := (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
		if d == 0: continue
		var df := float(d)
		for Y in range(mini(ay, mini(by, cy)), maxi(ay, maxi(by, cy))):
			for X in range(mini(ax, mini(bx, cx)), maxi(ax, maxi(bx, cx))):
				var px := float(X) + 0.5; var py := float(Y) + 0.5
				var w1 := ((px - ax) * (cy - ay) - (cx - ax) * (py - ay)) / df
				var w2 := ((bx - ax) * (py - ay) - (px - ax) * (by - ay)) / df
				var w0 := 1.0 - w1 - w2
				if w0 < -1e-6 or w1 < -1e-6 or w2 < -1e-6: continue
				var u := int(w0 * TA.x + w1 * TB.x + w2 * TC.x)
				var vv := int(w0 * TA.y + w1 * TB.y + w2 * TC.y)
				if clamp_uv:
					var q1 := float((X - ax) * (cy - ay) - (cx - ax) * (Y - ay)) / df
					var q2 := float((bx - ax) * (Y - ay) - (X - ax) * (by - ay)) / df
					var q0 := 1.0 - q1 - q2
					u = _arred3_piso(q0 * TA.x + q1 * TB.x + q2 * TC.x)
					vv = _arred3_piso(q0 * TA.y + q1 * TB.y + q2 * TC.y)
				var c := texel(v, tpx, tpy, dep, clut, u, vv)
				if c:
					c &= 0xFFFF
					var yy := Y + oy; var xx := X + ox
					if yy < 0: yy += C   # (índice negativo do numpy dá a volta)
					if xx < 0: xx += C
					if yy < 0 or xx < 0 or yy >= C or xx >= C: continue
					img[yy * C + xx] = ((c & 31) << 3) | ((((c >> 5) & 31) << 3) << 8) | ((((c >> 10) & 31) << 3) << 16) | (255 << 24)
					if xx < bb[0]: bb[0] = xx
					if yy < bb[1]: bb[1] = yy
					if xx > bb[2]: bb[2] = xx
					if yy > bb[3]: bb[3] = yy

# ---------------- foto (render_sel / grabw) ----------------
var _ram := {}; var _vram := {}; var _prims := {}
func _le(cache: Dictionary, k: String, caminho: String, bin := true):
	if not cache.has(k):
		if cache.size() > 6: cache.clear()
		cache[k] = FileAccess.get_file_as_bytes(caminho) if bin else prims(caminho)
	return cache[k]

## [imagem RGBA (PackedInt32Array), w, h, ox, oy] ou [] se não sobrou nada
func foto(dir: String, fi: int, fr: int, obj: int, bg: int, bo: bool, sel: Dictionary, BX: int, BY: int, C: int,
		clamp_uv: bool, espelho: String, extras: Array) -> Array:
	var r: PackedByteArray = _le(_ram, dir + str(fr), dir.path_join("r_%d.bin" % fr))
	var pos := func(o: int) -> Vector2i:
		var x := r.decode_u16(o + 0xA); var y := r.decode_u16(o + 0xE)
		var B := bg + (r[o + 0x14] * 0x54 if bo else 0)
		return Vector2i(x - r.decode_u16(B + 0xA), y - r.decode_u16(B + 0xE))
	var s: Vector2i = pos.call(obj)
	var prs: Array = _le(_prims, dir + str(fi), dir.path_join("p_%d.bin" % fi), false)
	var v: PackedByteArray = _le(_vram, dir + str(fi), dir.path_join("v_%d.bin" % fi))
	var lista: Array = prs
	if not extras.is_empty():
		lista = prs.duplicate()
		for e in extras:
			var o2: Vector2i = pos.call(int(e[0]))
			var tx := s.x + int(e[1]) - o2.x; var ty := s.y + int(e[2]) - o2.y
			for pr in prs:
				if not sel_ok(pr, sel): continue
				var c2 := _centro(pr)
				if absf(c2.x - o2.x) > float(e[3]) or absf(c2.y - o2.y) > float(e[4]): continue
				var q: Dictionary = pr.duplicate()
				var np := []
				for p in pr.P: np.append(Vector2i(p.x + tx, p.y + ty))
				q.P = np
				lista.append(q)
	var img := PackedInt32Array(); img.resize(C * C)
	var h := C / 2
	var bb := PackedInt32Array([C, C, -1, -1])
	for pr in lista:
		if not sel_ok(pr, sel): continue
		var c := _centro(pr)
		if absf(c.x - s.x) > BX or absf(c.y - s.y) > BY: continue
		raster(img, C, v, pr, h - s.x, h - s.y, clamp_uv, bb)
	var x0 := bb[0]; var y0 := bb[1]; var x1 := bb[2]; var y1 := bb[3]
	if x1 < 0: return []
	var w := x1 - x0 + 1; var hh := y1 - y0 + 1
	var crop := PackedInt32Array(); crop.resize(w * hh)
	var vira := espelho == "sempre" or (espelho == "obj" and r[obj + 0x15] != 0)
	for yy in hh:
		for xx in w:
			crop[yy * w + (w - 1 - xx if vira else xx)] = img[(y0 + yy) * C + x0 + xx]
	var ox := h - x0; var oy := h - y0
	if vira: ox = w - ox
	return [crop, w, hh, ox, oy]

static func _centro(pr: Dictionary) -> Vector2:
	var sx := 0.0; var sy := 0.0
	for p in pr.P: sx += p.x; sy += p.y
	return Vector2(sx / pr.P.size(), sy / pr.P.size())

# ---------------- grupo ----------------
func roda(jogo: String, base: String, prog: Callable) -> int:
	var rec = JSON.parse_string(FileAccess.get_file_as_string(base.path_join("efeitos.json")))
	if not rec is Dictionary: printerr("receita dos efeitos estragada"); return -1
	var A := jogo.path_join("assets")
	var meta := base.path_join("assets")
	var tmp := jogo.path_join(".captura/efeitos")
	# quadros que cada captura precisa
	var precisa := {}
	for rel in rec.atlas:
		for f in rec.atlas[rel].fotos:
			var lst: Dictionary = precisa.get(f[0], {})
			lst[int(f[2])] = true; lst[int(f[3])] = true
			precisa[f[0]] = lst
	var total: int = rec.capturas.size() + rec.atlas.size() + 3
	var passo := 0
	var n := 0
	var feitos := {}
	var caps: Array = rec.capturas.keys()
	for cn in caps:
		prog.call(passo, total, "efeitos: rodando %s" % cn); passo += 1
		var dir := tmp.path_join(cn)
		var qs: Array = precisa.get(cn, {}).keys(); qs.sort()
		if not roda_captura(cn, rec.capturas[cn], qs, dir): return -1
	for rel in rec.atlas:
		prog.call(passo, total, "efeitos: " + str(rel)); passo += 1
		var e: Dictionary = rec.atlas[rel]
		var W := int(e.tam[0]); var H := int(e.tam[1])
		var frames: Array = pecas.le_frames(meta.path_join(rel).path_join("frames.json"))
		var px := PackedInt32Array(); px.resize(W * H)
		for f in e.fotos:
			var g := foto(tmp.path_join(f[0]), int(f[2]), int(f[3]), int(f[4]), int(f[5]), int(f[6]) == 1, rec.selecoes[f[7]],
				int(f[8]), int(f[9]), int(f[10]), int(f[11]) == 1, str(f[12]), f[13])
			var k := int(f[1])
			var fr: Dictionary = frames[k]
			if g.is_empty() or g[1] != int(fr.w) or g[2] != int(fr.h) or g[3] != int(fr.ox) or g[4] != int(fr.oy):
				printerr("efeito %s quadro %d saiu diferente da receita (%s)" % [rel, k, str(g.slice(1)) if not g.is_empty() else "vazio"])
				return -1
			var crop: PackedInt32Array = g[0]
			for yy in g[2]:
				for xx in g[1]:
					var c := crop[yy * g[1] + xx]
					if c != 0: px[(int(fr.y) + yy) * W + int(fr.x) + xx] = c
		if not pecas.grava_png(px, W, H, A.path_join(rel).path_join("atlas.png")): return -1
		feitos[rel] = [px, W, H]
		n += 1
	# cópias (o mesmo efeito em várias armaduras)
	prog.call(passo, total, "efeitos: cópias"); passo += 1
	for de in rec.copias:
		for para in rec.copias[de]:
			DirAccess.make_dir_recursive_absolute(A.path_join(para))
			DirAccess.copy_absolute(A.path_join(de).path_join("atlas.png"), A.path_join(para).path_join("atlas.png")); n += 1
	# rastros: o atlas do voo sem os pontos com as cores do corpo e da armadura
	prog.call(passo, total, "efeitos: rastros"); passo += 1
	for rel in rec.derivados:
		var d: Dictionary = rec.derivados[rel]
		var src: Array = feitos.get(d.de, [])
		var banco: PackedInt32Array = pecas.pacote(str(d.pacote[0]), d.pacote[1]).banco
		var cores := {}
		for l in d.linhas:
			if l is Array: cores[pecas.cor(banco[int(l[0]) * 16 + int(l[1])]) & 0xffffff] = true
			else:
				for i in range(1, 16): cores[pecas.cor(banco[int(l) * 16 + i]) & 0xffffff] = true
		var px: PackedInt32Array = src[0].duplicate()
		for j in px.size():
			if px[j] != 0 and cores.has(px[j] & 0xffffff): px[j] = 0
		if not pecas.grava_png(px, src[1], src[2], A.path_join(rel).path_join("atlas.png")): return -1
		n += 1
	# cores da carga dos desenhos de voo (atlas_c1..c3), como as das peças
	prog.call(passo, total, "efeitos: cores da carga"); passo += 1
	var rp = JSON.parse_string(FileAccess.get_file_as_string(base.path_join("receita.json")))
	for arm in rp.cores:
		var ce: Dictionary = rp.cores[arm]
		if not "flight" in ce.atlas: continue
		var src: Array = feitos.get("x/parts/%s/flight" % arm, [])
		if src.is_empty(): continue
		var pals: Array = pecas.paletas(ce)
		for v in range(1, pals.size()):
			if not pecas.grava_png(pecas.recolore(src[0], pals, v), src[1], src[2], A.path_join("x/parts/%s/flight/atlas_c%d.png" % [arm, v])): return -1
			n += 1
	# os .json dessas pastas
	for rel in rec.atlas.keys() + rec.copias.values().reduce(func(a, b): return a + b, []) + rec.derivados.keys():
		for f in DirAccess.get_files_at(meta.path_join(rel)):
			DirAccess.make_dir_recursive_absolute(A.path_join(rel))
			DirAccess.copy_absolute(meta.path_join(rel).path_join(f), A.path_join(rel).path_join(f)); n += 1
	# limpa as capturas
	for cn in caps:
		var dir := tmp.path_join(cn)
		for f in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(tmp); DirAccess.remove_absolute(jogo.path_join(".captura"))
	return n
