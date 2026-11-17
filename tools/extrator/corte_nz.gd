extends RefCounted
## Corte do Zero Nightmare (X6, chefe secreto da área secreta) para o Giga do Nightmare Zero: assets/zero/x6/giga
## (atlas.png + frames.json). Igual ao do PC do dono: a recompilação do X6 (a DLL que o launcher já monta) roda o
## roteiro de pecas/corte_nz.json duas vezes (tudo / sem a paleta do corte e da onda) e de cada quadro sai o pedaço
## ligado (8 vizinhos) dos pontos que mudam, acima de limite_y, que contém a semente. Os quadros em 1x vão para uma
## grade (celula x celula, colunas por linha) e o atlas inteiro é ampliado com o Scale3x (bordas repetidas).

var opcoes: Dictionary

func _init(o: Dictionary) -> void:
	opcoes = o

func _op(k: String, env: String, padrao: String) -> String:
	if str(opcoes.get(k, "")) != "": return str(opcoes[k])
	if env != "" and OS.get_environment(env) != "": return OS.get_environment(env)
	return padrao

## pedaço ligado à semente (8 vizinhos) dos pontos em que as duas telas diferem, só com y < lim
## → [pontos RGBA, largura, altura, x0, y0] ou [] se a semente não está num ponto que muda
static func pedaco(A: PackedByteArray, B: PackedByteArray, W: int, H: int, sx: int, sy: int, lim: int) -> Array:
	var muda := func(x: int, y: int) -> bool:
		if x < 0 or y < 0 or x >= W or y >= H or y >= lim: return false
		var p := (y * W + x) * 3
		return A[p] != B[p] or A[p + 1] != B[p + 1] or A[p + 2] != B[p + 2]
	if not muda.call(sx, sy): return []
	var visto := PackedByteArray(); visto.resize(W * H)
	var fila := PackedInt32Array([sy * W + sx]); visto[sy * W + sx] = 1
	var x0 := sx; var y0 := sy; var x1 := sx; var y1 := sy
	var i := 0
	while i < fila.size():
		var q := fila[i]; i += 1
		var x := q % W; var y := q / W
		x0 = mini(x0, x); y0 = mini(y0, y); x1 = maxi(x1, x); y1 = maxi(y1, y)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := x + dx; var ny := y + dy
				if (dx == 0 and dy == 0) or not muda.call(nx, ny): continue
				var nq := ny * W + nx
				if visto[nq]: continue
				visto[nq] = 1; fila.append(nq)
	var w := x1 - x0 + 1; var h := y1 - y0 + 1
	var px := PackedInt32Array(); px.resize(w * h)
	for yy in h:
		for xx in w:
			var q := (y0 + yy) * W + x0 + xx
			if not visto[q]: continue
			var p := q * 3
			px[yy * w + xx] = A[p] | (A[p + 1] << 8) | (A[p + 2] << 16) | (255 << 24)
	return [px, w, h, x0, y0]

## Scale3x (AdvMAME3x) da imagem inteira; fora da imagem vale o ponto da borda
static func scale3x(src: PackedInt32Array, W: int, H: int) -> PackedInt32Array:
	var out := PackedInt32Array(); out.resize(W * 3 * H * 3)
	var W3 := W * 3
	for y in H:
		var ya := maxi(y - 1, 0) * W; var yc := y * W; var yb := mini(y + 1, H - 1) * W
		for x in W:
			var xl := maxi(x - 1, 0); var xr := mini(x + 1, W - 1)
			var E := src[yc + x]
			var B := src[ya + x]; var Hh := src[yb + x]; var D := src[yc + xl]; var F := src[yc + xr]
			var o := (y * 3) * W3 + x * 3
			if B == Hh or D == F:
				for j in 3:
					out[o + j * W3] = E; out[o + j * W3 + 1] = E; out[o + j * W3 + 2] = E
				continue
			var A := src[ya + xl]; var C := src[ya + xr]; var G := src[yb + xl]; var I := src[yb + xr]
			out[o] = D if D == B else E
			out[o + 1] = B if (D == B and E != C) or (B == F and E != A) else E
			out[o + 2] = F if B == F else E
			out[o + W3] = D if (D == B and E != G) or (D == Hh and E != A) else E
			out[o + W3 + 1] = E
			out[o + W3 + 2] = F if (B == F and E != I) or (Hh == F and E != C) else E
			out[o + 2 * W3] = D if D == Hh else E
			out[o + 2 * W3 + 1] = Hh if (D == Hh and E != I) or (Hh == F and E != G) else E
			out[o + 2 * W3 + 2] = F if Hh == F else E
	return out

func roda(jogo: String, base: String, prog: Callable) -> int:
	var rec = JSON.parse_string(FileAccess.get_file_as_string(base.path_join("corte_nz.json")))
	if not rec is Dictionary: printerr("receita do corte do Zero Nightmare estragada"); return -1
	var win := OS.get_name() == "Windows"
	var cap := _op("captura_rc", "FUSION_CAPTURA_RC", "")
	var lib := _op("recomp", "FUSION_RECOMP_X6", jogo.path_join("bin/x6recomp.dll" if win else "bin/libx6recomp.so"))
	var gd := _op("gamedir", "FUSION_GAMEDIR_X6", jogo.path_join("bin/recomp_x6"))
	var disco := _op("disco_x6", "", "")
	for par in [["a captura da recompilação", cap], ["a recompilação do X6", lib], ["o disco do X6", disco], ["a pasta da recompilação", gd.path_join("game.toml")]]:
		if par[1] == "" or not FileAccess.file_exists(par[1]): printerr("corte_nz: falta %s (%s)" % par); return -1
	var pasta := jogo.path_join(".captura/corte_nz")
	var fotos: Array = rec.fotos
	var dirs := []
	for k in 2:
		prog.call(k, 4, "corte do Zero Nightmare: luta no X6 (%d/2)" % (k + 1))
		var d := pasta.path_join("ab"[k])
		_apaga(d); DirAccess.make_dir_recursive_absolute(d)
		var env := "DISC=%s;GAMEDIR=%s;CARDDIR=%s" % [disco, gd, d]
		var ops: String = str(rec.opcoes) + (";esconde=" + str(rec.esconde) if k == 1 else "")
		var out := []
		var cod := OS.execute(cap, [lib, env, str(rec.armadura), "0", d, str(rec.seq), str(fotos[0]), str(fotos[1]), ops], out, true)
		if cod != 0 or not FileAccess.file_exists(d.path_join("f%03d.ppm" % int(fotos[1]))):
			printerr("corte_nz: a captura %d saiu com %d: %s" % [k, cod, str(out).right(400)]); return -1
		dirs.append(d)
	prog.call(2, 4, "corte do Zero Nightmare: montando")
	var meta := base.path_join("assets").path_join(str(rec.saida))
	var ref: Array = load("res://pecas.gd").le_frames(meta.path_join("frames.json"))
	var qs: Array = rec.quadros
	if ref.size() != qs.size(): printerr("corte_nz: a lista de quadros não bate com frames.json"); return -1
	var cel := int(rec.celula); var col := int(rec.colunas)
	var W1 := cel * col; var H1 := cel * ((qs.size() + col - 1) / col)
	var um := PackedInt32Array(); um.resize(W1 * H1)
	var dash = load("res://dash.gd")
	var telas := {}
	for f in qs.size():
		var q: Array = qs[f]
		var t := int(q[0])
		if not telas.has(t):
			var a: Array = dash.ppm(dirs[0].path_join("f%03d.ppm" % t)); var b: Array = dash.ppm(dirs[1].path_join("f%03d.ppm" % t))
			if a.is_empty() or b.is_empty() or a[1] != b[1] or a[2] != b[2]: printerr("corte_nz: falta a tela do quadro ", t); return -1
			telas[t] = [a, b]
		var A: Array = telas[t][0]; var B: Array = telas[t][1]
		var p := pedaco(A[0], B[0], A[1], A[2], int(q[1]), int(q[2]), int(rec.limite_y))
		if p.is_empty(): printerr("corte_nz: o quadro %d (tela %d) não tem o corte na semente" % [f, t]); return -1
		var w: int = p[1]; var h: int = p[2]; var x0: int = p[3]; var y0: int = p[4]
		var ax := x0 if int(q[3]) < 0 else int(q[3])
		var cx := (f % col) * cel; var cy := (f / col) * cel
		var e = ref[f]
		# a geometria tem que ser a da lista (frames.json nosso, do PC do dono)
		if e == null or int(e.x) != cx * 3 or int(e.y) != cy * 3 or int(e.w) != w * 3 or int(e.h) != h * 3 \
				or int(e.ox) != (ax - x0) * 3 or int(e.oy) != (int(q[4]) - y0) * 3 or w > cel or h > cel:
			printerr("corte_nz: quadro %d saiu diferente (%s / %d,%d %dx%d em %d,%d)" % [f, str(e), cx, cy, w, h, x0, y0]); return -1
		var src: PackedInt32Array = p[0]
		for yy in h:
			for xx in w: um[(cy + yy) * W1 + cx + xx] = src[yy * w + xx]
	prog.call(3, 4, "corte do Zero Nightmare: ampliando")
	var tres := scale3x(um, W1, H1)
	var dst := jogo.path_join("assets").path_join(str(rec.saida))
	if not load("res://pecas.gd").grava_png(tres, W1 * 3, H1 * 3, dst.path_join("atlas.png")): return -1
	DirAccess.copy_absolute(meta.path_join("frames.json"), dst.path_join("frames.json"))
	for d in dirs: _apaga(d)
	_apaga(pasta); DirAccess.remove_absolute(jogo.path_join(".captura"))
	prog.call(4, 4, "pronto")
	return 2

## apaga a pasta com tudo dentro (a recompilação deixa o cartão de memória e o registro em cada pasta)
func _apaga(d: String) -> void:
	var da := DirAccess.open(d)
	if da == null: return
	da.include_hidden = true
	for f in da.get_files(): da.remove(f)
	for s in da.get_directories(): _apaga(d.path_join(s))
	DirAccess.remove_absolute(d)
