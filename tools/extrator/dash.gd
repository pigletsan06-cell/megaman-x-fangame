extends RefCounted
## Dash da armadura Blade do X6 desenhado pelo próprio X6 (assets/x/parts/Blade_X6/dash6 e dash6_add), para quando
## as peças estão misturadas. Igual ao do PC do dono: a recompilação do X6 (a DLL que o launcher já monta) roda três
## vezes cada roteiro (nada escondido / o X e os efeitos escondidos / só o rastro escondido) e de cada quadro sai:
##   camada opaca  = os pontos que mudam entre "sem o X" e "sem o rastro" (cores da tela sem o rastro)
##   rastro somado = os pontos que mudam entre "tudo" e "sem o rastro" (diferença, que o jogo soma por cima)
## A tela de cada quadro mostra o estado de 2 quadros antes. Receita em pecas/dash.json.

var opcoes: Dictionary

func _init(o: Dictionary) -> void:
	opcoes = o

func _op(k: String, env: String, padrao: String) -> String:
	if str(opcoes.get(k, "")) != "": return str(opcoes[k])
	if env != "" and OS.get_environment(env) != "": return OS.get_environment(env)
	return padrao

## estado.txt: uma linha por quadro (t, ação, subestado, quadro, x, y, câmera x, câmera y, virado, ...)
static func estado(caminho: String) -> Array:
	var S := []
	var f := FileAccess.open(caminho, FileAccess.READ)
	if f == null: return S
	while not f.eof_reached():
		var l := f.get_line().strip_edges()
		if l == "": continue
		var v := PackedInt32Array()
		for p in l.split(" ", false): v.append(int(p))
		S.append(v)
	f.close()
	return S

## tela P6 (RGB) → [bytes, largura, altura]
static func ppm(caminho: String) -> Array:
	var b := FileAccess.get_file_as_bytes(caminho)
	if b.size() < 16: return []
	var campos := []; var i := 0; var cur := ""
	while campos.size() < 4 and i < b.size():
		var c := b[i]; i += 1
		if c == 32 or c == 10 or c == 13 or c == 9:
			if cur != "": campos.append(cur); cur = ""
		else: cur += char(c)
	if campos.size() < 4 or campos[0] != "P6": return []
	var w := int(campos[1]); var h := int(campos[2])
	return [b.slice(i, i + w * h * 3), w, h]

## chave do quadro no atlas: espera (subestado 0) = 500 + t; andando (subestado 1) = base + t (t até 19)
static func chave(S: Array, i: int, base: int) -> int:
	var s: PackedInt32Array = S[i]
	var j := i
	if s[2] == 0:
		while j > 0 and S[j - 1][1] == 0x4A and S[j - 1][2] == 0: j -= 1
		return 500 + mini(i - j, 19)
	while j > 0 and S[j - 1][1] == 0x4A and S[j - 1][2] == 1: j -= 1
	return base + mini(i - j, 19)

## um roteiro (3 pastas: 0 tudo, 1 sem o X, 2 sem o rastro) → quadros novos em op/ad
func colhe(pasta: String, nome: String, base: int, rec: Dictionary, op: Dictionary, ad: Dictionary) -> bool:
	var S := estado(pasta.path_join(nome + "0/estado.txt"))
	if S.is_empty(): printerr("dash: sem estado em ", nome); return false
	var atraso := int(rec.atraso); var jx := int(rec.janela[0]); var jy := int(rec.janela[1])
	var hx := int(rec.hud[0]); var hy := int(rec.hud[1]); var lim := int(rec.limiar)
	for t in range(atraso, S.size()):
		var s: PackedInt32Array = S[t - atraso]
		if s[1] != 0x4A: continue
		var k := chave(S, t - atraso, base)
		if op.has(k): continue
		var nm := "f%03d.ppm" % t
		var a := ppm(pasta.path_join(nome + "0").path_join(nm)); var b := ppm(pasta.path_join(nome + "1").path_join(nm))
		var c := ppm(pasta.path_join(nome + "2").path_join(nm))
		if a.is_empty() or b.is_empty() or c.is_empty(): printerr("dash: falta a tela %s de %s" % [nm, nome]); return false
		var A: PackedByteArray = a[0]; var B: PackedByteArray = b[0]; var C: PackedByteArray = c[0]
		var W: int = a[1]; var H: int = a[2]
		var sx := s[4] - s[6]; var sy := s[5] - s[7]
		var y0 := maxi(0, sy - jy); var y1 := mini(H, sy + jy); var x0 := maxi(0, sx - jx); var x1 := mini(W, sx + jx)
		var mo := PackedByteArray(); mo.resize(W * H)
		var ma := PackedByteArray(); ma.resize(W * H)
		var bo := [W, H, -1, -1]; var ba := [W, H, -1, -1]
		for y in range(y0, y1):
			for x in range(x0, x1):
				if y < hy and x < hx: continue   # (o HUD)
				var p := (y * W + x) * 3
				var dcb := absi(C[p] - B[p]) + absi(C[p + 1] - B[p + 1]) + absi(C[p + 2] - B[p + 2])
				var dac := absi(A[p] - C[p]) + absi(A[p + 1] - C[p + 1]) + absi(A[p + 2] - C[p + 2])
				if dcb > lim:
					mo[y * W + x] = 1
					bo[0] = mini(bo[0], x); bo[1] = mini(bo[1], y); bo[2] = maxi(bo[2], x); bo[3] = maxi(bo[3], y)
				if dac > lim:
					ma[y * W + x] = 1
					ba[0] = mini(ba[0], x); ba[1] = mini(ba[1], y); ba[2] = maxi(ba[2], x); ba[3] = maxi(ba[3], y)
		op[k] = _recorte(mo, bo, W, C, A, false, sx, sy)
		ad[k] = _recorte(ma, ba, W, C, A, true, sx, sy)
	return true

## recorte da caixa da máscara: [pontos RGBA, largura, altura, ox, oy] (null se vazio)
func _recorte(m: PackedByteArray, bb: Array, W: int, C: PackedByteArray, A: PackedByteArray, soma: bool, sx: int, sy: int):
	if bb[2] < 0: return null
	var w: int = bb[2] - bb[0] + 1; var h: int = bb[3] - bb[1] + 1
	var px := PackedInt32Array(); px.resize(w * h)
	for yy in h:
		for xx in w:
			var q: int = (bb[1] + yy) * W + bb[0] + xx; var p := q * 3
			var r: int; var g: int; var bl: int
			if soma:
				r = clampi(A[p] - C[p], 0, 255); g = clampi(A[p + 1] - C[p + 1], 0, 255); bl = clampi(A[p + 2] - C[p + 2], 0, 255)
			else:
				r = C[p]; g = C[p + 1]; bl = C[p + 2]
			px[yy * w + xx] = r | (g << 8) | (bl << 16) | ((255 if m[q] else 0) << 24)
	return [px, w, h, sx - bb[0], sy - bb[1]]

## atlas de 1024 de largura, quadros em ordem de chave, um ponto de folga (como no PC do dono)
static func empacota(store: Dictionary, largura: int) -> Array:
	var ks := []
	for k in store: if store[k] != null: ks.append(k)
	ks.sort()
	var x := 0; var y := 0; var alt := 0; var pos := {}
	for k in ks:
		var w: int = store[k][1]; var h: int = store[k][2]
		if x + w > largura: x = 0; y += alt + 1; alt = 0
		pos[k] = [x, y]; x += w + 1; alt = maxi(alt, h)
	var H := y + alt + 1
	var px := PackedInt32Array(); px.resize(largura * H)
	var frames := {}
	for k in ks:
		var e: Array = store[k]; var P: Array = pos[k]
		var src: PackedInt32Array = e[0]
		for yy in int(e[2]):
			for xx in int(e[1]): px[(P[1] + yy) * largura + P[0] + xx] = src[yy * int(e[1]) + xx]
		frames[k] = {"x": P[0], "y": P[1], "w": e[1], "h": e[2], "ox": e[3], "oy": e[4]}
	return [px, largura, H, frames]

func roda(jogo: String, base: String, prog: Callable) -> int:
	var rec = JSON.parse_string(FileAccess.get_file_as_string(base.path_join("dash.json")))
	if not rec is Dictionary: printerr("receita do dash estragada"); return -1
	var win := OS.get_name() == "Windows"
	var cap := _op("captura_rc", "FUSION_CAPTURA_RC", "")
	var lib := _op("recomp", "FUSION_RECOMP_X6", jogo.path_join("bin/x6recomp.dll" if win else "bin/libx6recomp.so"))
	var gd := _op("gamedir", "FUSION_GAMEDIR_X6", jogo.path_join("bin/recomp_x6"))
	var disco := _op("disco_x6", "", "")
	for par in [["a captura da recompilação", cap], ["a recompilação do X6", lib], ["o disco do X6", disco], ["a pasta da recompilação", gd.path_join("game.toml")]]:
		if par[1] == "" or not FileAccess.file_exists(par[1]): printerr("dash: falta %s (%s)" % par); return -1
	var pasta := jogo.path_join(".captura/dash")
	var op := {}; var ad := {}
	var cs: Array = rec.corridas
	var total := cs.size() * 4 + 2
	for i in cs.size():
		var cr: Dictionary = cs[i]
		for esc in 3:
			prog.call(i * 4 + esc, total, "dash da Blade: %s (%d/3)" % [cr.nome, esc + 1])
			var d := pasta.path_join("%s%d" % [cr.nome, esc])
			DirAccess.make_dir_recursive_absolute(d)
			var env := "DISC=%s;GAMEDIR=%s;CARDDIR=%s" % [disco, gd, d]
			var out := []
			var cod := OS.execute(cap, [lib, env, str(rec.armadura), str(esc), d, str(cr.seq), str(cr.fotos[0]), str(cr.fotos[1])], out, true)
			if cod != 0 or not FileAccess.file_exists(d.path_join("estado.txt")):
				printerr("dash: a captura %s%d saiu com %d: %s" % [cr.nome, esc, cod, str(out).right(400)]); return -1
		prog.call(i * 4 + 3, total, "dash da Blade: montando %s" % cr.nome)
		if not colhe(pasta, str(cr.nome), int(cr.base), rec, op, ad): return -1
		for esc in 3: _apaga(pasta.path_join("%s%d" % [cr.nome, esc]))
	_apaga(pasta); DirAccess.remove_absolute(jogo.path_join(".captura"))
	var A := jogo.path_join("assets")
	var meta := base.path_join("assets")
	var n := 0
	for par in [[rec.saidas.op, op], [rec.saidas.ad, ad]]:
		var rel: String = par[0]
		var r := empacota(par[1], int(rec.largura))
		# a geometria tem que ser a da lista (frames.json nosso, do PC do dono)
		var ref: Array = load("res://pecas.gd").le_frames(meta.path_join(rel).path_join("frames.json"))
		var fr: Dictionary = r[3]
		for k in ref.size():
			var e = ref[k]
			if e == null and not fr.has(k): continue
			if e == null or not fr.has(k) or int(e.x) != fr[k].x or int(e.y) != fr[k].y or int(e.w) != fr[k].w or int(e.h) != fr[k].h \
					or int(e.ox) != fr[k].ox or int(e.oy) != fr[k].oy:
				printerr("dash: quadro %d de %s saiu diferente (%s / %s)" % [k, rel, str(e), str(fr.get(k))]); return -1
		if fr.size() != ref.filter(func(e): return e != null).size(): printerr("dash: quadros a mais em ", rel); return -1
		if not load("res://pecas.gd").grava_png(r[0], r[1], r[2], A.path_join(rel).path_join("atlas.png")): return -1
		DirAccess.copy_absolute(meta.path_join(rel).path_join("frames.json"), A.path_join(rel).path_join("frames.json"))
		n += 2
	prog.call(total, total, "pronto")
	return n

## apaga a pasta com tudo dentro (a recompilação deixa o cartão de memória e o registro em cada pasta)
func _apaga(d: String) -> void:
	var da := DirAccess.open(d)
	if da == null: return
	da.include_hidden = true
	for f in da.get_files(): da.remove(f)
	for s in da.get_directories(): _apaga(d.path_join(s))
	DirAccess.remove_absolute(d)
