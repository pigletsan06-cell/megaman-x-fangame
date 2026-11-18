extends RefCounted
## Fontes originais dos menus do X4/X5/X6 -> atlas PNG + BMFont (assets/fonte/mmx_x4|x5|x6), para os textos grandes
## e as abas dos menus do fangame (MmxUI.skin_font). As letras ficam numa página de 256x256 de 4 bits, em células de
## 16x16 (no X4 dentro de ARC/LOAD_U.ARC; no X5/X6 na VRAM 960,256 com o menu de pausa aberto). Os acentos não existem
## nas fontes dos jogos: são desenhados aqui (2 a 4 pontos em cima, cedilha embaixo).
## Mesmas contas do research/fontes.py do PC do dono.

const GRAY := [0, 0, 0, 8, 24, 82, 90, 98, 123, 139, 172, 197, 213, 230, 255, 0]   # rampa do X5 (CLUT 0,480); 1/2 = contorno preto
const X6G := {2: 235, 3: 55, 4: 190, 5: 205, 6: 255, 12: 85, 13: 55, 14: 110}
const ACC := {"´": [[1, 0], [0, 1]], "`": [[0, 0], [1, 1]], "^": [[1, 0], [0, 1], [2, 1]], "~": [[0, 1], [1, 0], [2, 1], [3, 0]], "¨": [[0, 0], [2, 0]]}
const COMP := {"á": ["a", "´"], "à": ["a", "`"], "â": ["a", "^"], "ã": ["a", "~"], "é": ["e", "´"], "ê": ["e", "^"], "í": ["i", "´"],
	"ó": ["o", "´"], "ô": ["o", "^"], "õ": ["o", "~"], "ú": ["u", "´"], "ü": ["u", "¨"], "Á": ["A", "´"], "À": ["A", "`"],
	"Â": ["A", "^"], "Ã": ["A", "~"], "É": ["E", "´"], "Ê": ["E", "^"], "Í": ["I", "´"], "Ó": ["O", "´"], "Ô": ["O", "^"],
	"Õ": ["O", "~"], "Ú": ["U", "´"], "Ç": ["C", ","], "ç": ["c", ","]}

static func cellmap(g: String) -> Dictionary:
	var m := {}
	var row := func(r: int, s: String, c0: int) -> void:
		for i in s.length():
			if s[i] != " ": m[s[i]] = Vector2i(c0 + i, r)
	if g == "x4":
		row.call(4, "0123456789ABCDEF", 0); row.call(5, "GHIJKLMNOPQRSTUV", 0); row.call(6, "WXYZabcdefghijkl", 0); row.call(7, "mnopqrstuvwxyz/↓", 0)
		row.call(8, "↑←→+-,.!?“”’ …", 0)
	else:
		row.call(12, "ABCDEFGHIJKLMNOP", 0); row.call(13, "QRSTUVWXYZ456789", 0); row.call(11, "0123", 8)
		row.call(7, "abcdefg", 0); row.call(8, "hijklmn", 0); row.call(9, "opqrstu", 0); row.call(10, "vwxyz-?", 0)
		row.call(14, "+-!?. …:' &%\"", 0)
	return m

## pag: a página de 256x256 pontos de 4 bits, 128 bytes por linha
static func monta(g: String, pag: PackedByteArray, saida: String) -> bool:
	if pag.size() < 128 * 256: printerr("fonte %s: página curta" % g); return false
	var m := cellmap(g)
	var raw := {}
	for ch in m:
		var c: Vector2i = m[ch]
		var px := {}
		for y in 16:
			for x in 16:
				var X := c.x * 16 + x; var Y := c.y * 16 + y
				var b := pag[Y * 128 + (X >> 1)]
				var i := (b >> 4) if X & 1 else (b & 15)
				if i == 0: continue
				if g == "x4": px[Vector2i(x, y)] = 255
				elif g == "x6": px[Vector2i(x, y)] = int(X6G.get(i, 200))
				else: px[Vector2i(x, y)] = GRAY[i]
		raw[ch] = px
	var ref: Dictionary = raw["H"] if raw.has("H") else raw["E"]
	var base := -99; var top := 99
	for p in ref: base = maxi(base, p.y); top = mini(top, p.y)
	var xtop := top
	if raw.has("x"):
		xtop = 99
		for p in raw["x"]: xtop = mini(xtop, p.y)
	for ch in COMP:
		var bch: String = COMP[ch][0]; var a: String = COMP[ch][1]
		if not raw.has(bch): continue
		var px: Dictionary = (raw[bch] as Dictionary).duplicate()
		var t := 99; var x0 := 99; var x1 := -99; var bot := -99
		for p in px: t = mini(t, p.y); x0 = mini(x0, p.x); x1 = maxi(x1, p.x); bot = maxi(bot, p.y)
		var cx := (x0 + x1) / 2
		if a == ",":   # cedilha: dois pontos embaixo
			for d in [Vector2i(0, 1), Vector2i(0, 2), Vector2i(-1, 2)]: px[Vector2i(cx + d.x, bot + d.y)] = 255
		else:
			var pts: Array = ACC[a]
			var w := 0
			for q in pts: w = maxi(w, int(q[0]) + 1)
			for q in pts: px[Vector2i(cx - w / 2 + int(q[0]) + (1 if g != "x6" else 0), t - 3 + int(q[1]))] = 255
			if bch == "i":   # o pingo do i sai e o acento fica no lugar dele
				for p in px.keys():
					if p.y < xtop: px.erase(p)
				for q in pts: px[Vector2i(cx - w / 2 + int(q[0]) + 1, xtop - 3 + int(q[1]))] = 255
		raw[ch] = px
	var chars := raw.keys()
	chars.sort_custom(func(p: String, q: String) -> bool: return p.unicode_at(0) < q.unicode_at(0))
	var cols := 16; var cw := 18; var chh := 16 + 4 + 3
	var ymin := 99
	for ch in chars:
		for p in raw[ch]: ymin = mini(ymin, p.y)
	var im := Image.create_empty(cols * cw, ((chars.size() + cols - 1) / cols) * chh, false, Image.FORMAT_RGBA8)
	var lines := []
	for k in chars.size():
		var px: Dictionary = raw[chars[k]]
		if px.is_empty(): continue
		var x0 := 99; var x1 := -99; var y1 := -99
		for p in px: x0 = mini(x0, p.x); x1 = maxi(x1, p.x); y1 = maxi(y1, p.y)
		var ax := (k % cols) * cw; var ay := (k / cols) * chh
		for p in px:
			var v := float(px[p]) / 255.0
			im.set_pixel(ax + p.x - x0, ay + p.y - ymin, Color(v, v, v, 1.0))
		lines.append([String(chars[k]).unicode_at(0), ax, ay, x1 - x0 + 1, y1 - ymin + 1, x1 - x0 + (1 if g == "x5" else 2)])
	lines.append([32, 0, 0, 0, 0, 4 if g == "x4" else 5])
	var nome := saida.get_file()
	var f := PackedStringArray([
		'info face="%s" size=9 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=0,0' % nome,
		"common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0" % [base - ymin + 3, base - ymin + 1, im.get_width(), im.get_height()],
		'page id=0 file="%s.png"' % nome, "chars count=%d" % lines.size()])
	for l in lines:
		f.append("char id=%d x=%d y=%d width=%d height=%d xoffset=0 yoffset=0 xadvance=%d page=0 chnl=15" % [l[0], l[1], l[2], l[3], l[4], l[5]])
	DirAccess.make_dir_recursive_absolute(saida.get_base_dir())
	if im.save_png(saida + ".png") != OK: printerr("não gravei ", saida, ".png"); return false
	var fa := FileAccess.open(saida + ".fnt", FileAccess.WRITE)
	if fa == null: printerr("não gravei ", saida, ".fnt"); return false
	fa.store_string("\n".join(f) + "\n"); fa.close()
	return true

## a página da fonte de dentro da VRAM (1024x512 de 16 bits): x = 960 palavras, y = 256
static func pagina_da_vram(vram: PackedByteArray) -> PackedByteArray:
	var p := PackedByteArray()
	for y in 256:
		var o := ((256 + y) * 1024 + 960) * 2
		p.append_array(vram.slice(o, o + 128))
	return p
