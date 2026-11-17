## Estilo visual do jogo (copiado de godot/scripts/mmx_ui.gd, sem class_name: o launcher roda de uma pasta nova, sem .godot/)
extends RefCounted
## Estilo dos menus do fangame (desenho original): fonte de pixel própria (assets/fonte/mmx_ui.fnt, tools/fonte_mmx.py),
## painéis azul-metálicos com cantos cortados, faixa de título, barra de seleção pulsando e sons de menu
## (assets/sfx/menu_*.wav: move/ok gravados; open/close/back/equip/error/tab/full sintetizados em tools/sons_menu.py).

const C_BG_TOP := Color(0.035, 0.075, 0.19, 0.95)
const C_BG_BOT := Color(0.008, 0.02, 0.07, 0.95)
const C_EDGE_HI := Color(0.62, 0.9, 1.0)
const C_EDGE_LO := Color(0.13, 0.32, 0.66)
const C_EDGE_DK := Color(0.0, 0.015, 0.05)
const C_TEXT := Color(0.86, 0.92, 1.0)
const C_DIM := Color(0.48, 0.56, 0.74)
const C_SEL := Color(1.0, 0.86, 0.3)
const C_ACCENT := Color(0.3, 0.84, 1.0)
const C_GOLD := Color(1.0, 0.72, 0.18)
const C_GOOD := Color(0.45, 1.0, 0.55)
const C_WARN := Color(1.0, 0.55, 0.35)
const LINE := 10          # altura da linha da fonte (1x)
# sons dos menus: os do menu de pausa do X4 que o projeto já tem (menu_move = cursor, menu_ok = confirmar); só o erro
# continua o zumbido sintetizado (menu_error)
const SFX := {"menu_open": "menu_ok", "menu_close": "menu_move", "menu_back": "menu_move", "menu_equip": "menu_ok",
	"menu_full": "menu_ok", "menu_tab": "menu_move"}
const SIZE := 9           # tamanho da fonte (1x); 18 = 2x

static var _font: Font
static var _theme: Theme

static func font() -> Font:
	if _font == null:
		var f := FontFile.new()
		if f.load_bitmap_font("res://assets/fonte/mmx_ui.fnt") == OK:
			f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
			_font = f
		else:
			_font = ThemeDB.fallback_font
	return _font

## tema dos menus: a fonte de pixel em tudo (Label, LineEdit), sombra de 1 pixel
static func theme() -> Theme:
	if _theme == null:
		var t := Theme.new()
		t.default_font = font(); t.default_font_size = SIZE
		t.set_color("font_color", "Label", C_TEXT)
		t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.8))
		t.set_constant("shadow_offset_x", "Label", 1); t.set_constant("shadow_offset_y", "Label", 1)
		t.set_constant("line_spacing", "Label", 0)
		t.set_constant("outline_size", "Label", 0)
		var le := StyleBoxFlat.new(); le.bg_color = Color(0.0, 0.03, 0.1, 0.95); le.border_color = C_EDGE_LO
		le.set_border_width_all(1); le.content_margin_left = 3; le.content_margin_right = 3; le.content_margin_top = 1; le.content_margin_bottom = 0
		var lf := le.duplicate(); lf.border_color = C_SEL
		t.set_stylebox("normal", "LineEdit", le); t.set_stylebox("focus", "LineEdit", lf); t.set_stylebox("read_only", "LineEdit", le)
		t.set_color("font_color", "LineEdit", C_TEXT); t.set_color("font_placeholder_color", "LineEdit", C_DIM)
		t.set_color("caret_color", "LineEdit", C_SEL); t.set_color("selection_color", "LineEdit", Color(0.2, 0.5, 0.9, 0.6))
		t.set_constant("caret_width", "LineEdit", 1)
		_theme = t
	return _theme

static func ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

## contorno de cantos cortados (em cima à esquerda e embaixo à direita)
static func shape(r: Rect2, cut := 6.0) -> PackedVector2Array:
	var c := minf(cut, minf(r.size.x, r.size.y) * 0.5)
	var p := r.position; var q := r.end
	return PackedVector2Array([Vector2(p.x + c, p.y), Vector2(q.x, p.y), Vector2(q.x, q.y - c), Vector2(q.x - c, q.y),
		Vector2(p.x, q.y), Vector2(p.x, p.y + c)])

## fundo + moldura metálica (claro em cima/à esquerda, escuro embaixo/à direita) + detalhes na cor de destaque
static func frame(ci: CanvasItem, r: Rect2, accent := C_ACCENT, cut := 6.0, bg := true) -> void:
	if r.size.x < 2.0 or r.size.y < 2.0: return
	var pts := shape(r, cut)
	if bg:
		var cols := PackedColorArray()
		for v in pts: cols.append(C_BG_TOP.lerp(C_BG_BOT, clampf((v.y - r.position.y) / r.size.y, 0.0, 1.0)))
		ci.draw_polygon(pts, cols)
		var y := r.position.y + 2.0
		while y < r.end.y - 1.0:   # linhas de varredura
			ci.draw_line(Vector2(r.position.x + 1, y), Vector2(r.end.x - 1, y), Color(0.5, 0.8, 1.0, 0.035), 1.0)
			y += 3.0
	var dk := pts.duplicate(); dk.append(pts[0])
	ci.draw_polyline(_grow(dk, r, 1.0), C_EDGE_DK, 1.0)
	# claro: em cima e à esquerda; escuro: à direita e embaixo
	ci.draw_line(pts[5], pts[0], C_EDGE_HI, 1.0); ci.draw_line(pts[0], pts[1], C_EDGE_HI, 1.0)
	ci.draw_line(pts[4], pts[5], C_EDGE_HI.lerp(C_EDGE_LO, 0.35), 1.0)
	ci.draw_line(pts[1], pts[2], C_EDGE_LO, 1.0); ci.draw_line(pts[2], pts[3], C_EDGE_LO, 1.0); ci.draw_line(pts[3], pts[4], C_EDGE_LO, 1.0)
	var inner := shape(r.grow(-2.0), maxf(cut - 1.0, 2.0)); inner.append(inner[0])
	ci.draw_polyline(inner, Color(accent.r, accent.g, accent.b, 0.22), 1.0)
	# cantos cortados com brilho e marcas na borda
	ci.draw_line(pts[0], pts[5], accent, 1.0); ci.draw_line(pts[2], pts[3], accent.darkened(0.25), 1.0)
	for k in 3:
		var x := r.end.x - 8.0 - k * 4.0
		ci.draw_line(Vector2(x, r.end.y - 1.0), Vector2(x + 2.0, r.end.y - 1.0), Color(accent.r, accent.g, accent.b, 0.7), 1.0)

static func _grow(pts: PackedVector2Array, r: Rect2, d: float) -> PackedVector2Array:
	var c := r.get_center(); var o := PackedVector2Array()
	for v in pts:
		o.append(Vector2(v.x + (d if v.x > c.x else -d), v.y + (d if v.y > c.y else -d)))
	return o

## faixa do título (aba inclinada) em cima à esquerda do painel
static func title_tab(ci: CanvasItem, r: Rect2, text: String, accent := C_ACCENT) -> void:
	if text == "": return
	var f := font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x + 14.0
	var y0 := r.position.y - 5.0
	var p := PackedVector2Array([Vector2(r.position.x + 8, y0), Vector2(r.position.x + 8 + w, y0), Vector2(r.position.x + 8 + w + 6, y0 + 11),
		Vector2(r.position.x + 2, y0 + 11), Vector2(r.position.x + 2, y0 + 6)])
	var cols := PackedColorArray()
	for v in p: cols.append(accent.lerp(accent.darkened(0.55), clampf((v.y - y0) / 11.0, 0.0, 1.0)))
	ci.draw_polygon(p, cols)
	var pl := p.duplicate(); pl.append(p[0]); ci.draw_polyline(pl, C_EDGE_DK, 1.0)
	ci.draw_line(p[0], p[1], Color(1, 1, 1, 0.6), 1.0)
	ci.draw_string(f, Vector2(r.position.x + 13, y0 + 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, Color(0.02, 0.05, 0.14))
	# riscas depois da aba
	for k in 4:
		var x := r.position.x + 8 + w + 10 + k * 5
		ci.draw_line(Vector2(x, y0 + 10), Vector2(x + 4, y0 + 2), Color(accent.r, accent.g, accent.b, 0.55 - k * 0.12), 1.0)

## barra de seleção: degradê na cor de destaque, linhas finas e a seta ▶ que balança
static func sel_bar(ci: CanvasItem, r: Rect2, t: float, accent := C_ACCENT, arrow := true) -> void:
	var pulse := 0.5 + 0.5 * sin(t * TAU * 1.6)
	var a0 := 0.32 + 0.18 * pulse
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	ci.draw_polygon(pts, PackedColorArray([Color(accent.r, accent.g, accent.b, a0), Color(accent.r, accent.g, accent.b, 0.0),
		Color(accent.r, accent.g, accent.b, 0.0), Color(accent.r, accent.g, accent.b, a0)]))
	ci.draw_line(r.position, Vector2(r.end.x * 0.6 + r.position.x * 0.4, r.position.y), Color(1, 1, 1, 0.25 + 0.2 * pulse), 1.0)
	ci.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x * 0.6 + r.position.x * 0.4, r.end.y), Color(accent.r, accent.g, accent.b, 0.5), 1.0)
	if arrow:
		var bob := roundf(1.5 + 1.5 * sin(t * TAU * 2.2))
		ci.draw_string(font(), Vector2(r.position.x - 7 + bob, r.position.y + (r.size.y - LINE) * 0.5 + 8), "▶", HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, C_SEL)

## texto com sombra (desenho direto)
static func text(ci: CanvasItem, pos: Vector2, s: String, col := C_TEXT, size := SIZE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var f := font()
	ci.draw_string(f, pos + Vector2(1, 1) * (size / SIZE), s, align, width, size, Color(0, 0, 0, 0.8 * col.a))
	ci.draw_string(f, pos, s, align, width, size, col)

static func text_width(s: String, size := SIZE) -> float:
	return font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

## botão (letra num quadradinho) + ação, para as dicas; devolve a largura usada
static func hint(ci: CanvasItem, pos: Vector2, key: String, action: String, accent := C_ACCENT) -> float:
	var kw := text_width(key) + 4.0
	var r := Rect2(pos.x, pos.y - 8.0, kw, 9.0)
	ci.draw_rect(r, Color(accent.r * 0.35, accent.g * 0.35, accent.b * 0.45, 0.95))
	ci.draw_rect(r, Color(accent.r, accent.g, accent.b, 0.8), false, 1.0)
	ci.draw_string(font(), Vector2(pos.x + 2, pos.y), key, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, Color(1, 1, 1))
	var x := pos.x + kw + 3.0
	text(ci, Vector2(x, pos.y), action, C_TEXT)
	return kw + 3.0 + text_width(action) + 8.0

## uma linha de dicas "tecla:ação" separadas por |, centralizada em [x, x + w]
static func hints(ci: CanvasItem, pos: Vector2, w: float, items: Array, accent := C_ACCENT) -> void:
	var tot := 0.0
	for it in items: tot += text_width(str(it[0])) + 4.0 + 3.0 + text_width(str(it[1])) + 8.0
	var x := pos.x + maxf(0.0, (w - tot + 8.0) * 0.5)
	for it in items: x += hint(ci, Vector2(x, pos.y), str(it[0]), str(it[1]), accent)

## quebra o texto em linhas que cabem na largura (fonte 1x)
static func wrap(s: String, width: float) -> PackedStringArray:
	var out := PackedStringArray()
	for para in s.split("\n"):
		var line := ""
		for w in para.split(" "):
			var cand := w if line == "" else line + " " + w
			if line != "" and text_width(cand) > width:
				out.append(line); line = w
			else:
				line = cand
		out.append(line)
	return out

## corta com "…" se passar da largura
static func fit(s: String, width: float) -> String:
	if text_width(s) <= width: return s
	while s.length() > 1 and text_width(s + "…") > width: s = s.substr(0, s.length() - 1)
	return s + "…"

## painel de vidro escuro simples (caixas internas)
static func inset(ci: CanvasItem, r: Rect2, accent := C_ACCENT) -> void:
	ci.draw_rect(r, Color(0.0, 0.02, 0.08, 0.75))
	ci.draw_rect(r, Color(accent.r, accent.g, accent.b, 0.35), false, 1.0)
	ci.draw_line(r.position + Vector2(1, 1), Vector2(r.end.x - 1, r.position.y + 1), Color(1, 1, 1, 0.06), 1.0)

# ---- holograma da armadura (boneco genérico de peças geométricas, desenho original) ----
const ARM_COL := {
	"": [Color(0.3, 0.36, 0.48), Color(0.5, 0.62, 0.8)],
	"Fourth_X4": [Color(0.88, 0.92, 1.0), Color(0.25, 0.45, 1.0)],
	"Fourth_X4P": [Color(0.88, 0.92, 1.0), Color(0.62, 0.35, 1.0)],
	"Fourth_X5": [Color(0.84, 0.88, 0.98), Color(1.0, 0.74, 0.25)],
	"Falcon_X5": [Color(0.96, 0.96, 1.0), Color(0.95, 0.25, 0.25)],
	"Gaea_X5": [Color(0.42, 0.45, 0.5), Color(0.35, 0.85, 0.7)],
	"Falcon_X6": [Color(0.95, 0.95, 0.98), Color(1.0, 0.48, 0.2)],
	"Blade_X6": [Color(0.24, 0.32, 0.52), Color(0.35, 0.85, 1.0)],
	"Shadow_X6": [Color(0.36, 0.2, 0.5), Color(0.92, 0.38, 0.92)],
	"Ultimate_X4": [Color(0.2, 0.24, 0.56), Color(1.0, 0.8, 0.3)],
	"Ultimate_X5": [Color(0.2, 0.24, 0.56), Color(1.0, 0.8, 0.3)],
	"Ultimate_X6": [Color(0.2, 0.24, 0.56), Color(1.0, 0.8, 0.3)],
	"zero": [Color(0.9, 0.2, 0.22), Color(1.0, 0.9, 0.85)],
	"bz": [Color(0.13, 0.13, 0.17), Color(1.0, 0.8, 0.3)],
	"nz": [Color(0.42, 0.16, 0.56), Color(0.86, 0.52, 1.0)],
}

# boneco do holograma (pés na origem, ~120 px de altura): peça -> polígonos
# emblema de cada armadura (símbolos simples, desenho original): Fourth = 4 losangos, Falcon = asa, Gaea = montanha,
# Blade = lâmina, Shadow = lua crescente, Ultimate = estrela, Zero = corte em arco
static func emblem_kind(key: String) -> String:
	if key.begins_with("Fourth"): return "fourth"
	if key.begins_with("Falcon"): return "falcon"
	if key.begins_with("Gaea"): return "gaea"
	if key.begins_with("Blade"): return "blade"
	if key.begins_with("Shadow"): return "shadow"
	if key.begins_with("Ultimate"): return "ultimate"
	if key in ["zero", "bz", "nz"]: return "zero"
	return ""

static func _quad(a: Vector2, b: Vector2, w: float) -> PackedVector2Array:
	var n := (b - a).normalized().orthogonal() * w * 0.5
	return PackedVector2Array([a + n, b + n, b - n, a - n])

static func emblem(ci: CanvasItem, key: String, c: Vector2, s: float, col: Color, bg: Color) -> void:
	var P := func(x: float, y: float) -> Vector2: return c + Vector2(x, y) * s
	match emblem_kind(key):
		"fourth":
			for q in [Vector2(-0.36, -0.36), Vector2(0.36, -0.36), Vector2(-0.36, 0.36), Vector2(0.36, 0.36)]:
				ci.draw_colored_polygon(PackedVector2Array([P.call(q.x, q.y - 0.24), P.call(q.x + 0.24, q.y), P.call(q.x, q.y + 0.24), P.call(q.x - 0.24, q.y)]), col)
		"falcon":
			for f in [[Vector2(-0.62, 0.22), Vector2(0.62, -0.42), 0.2], [Vector2(-0.46, 0.48), Vector2(0.48, -0.06), 0.17], [Vector2(-0.3, 0.7), Vector2(0.3, 0.28), 0.14]]:
				ci.draw_colored_polygon(_quad(P.call(f[0].x, f[0].y), P.call(f[1].x, f[1].y), float(f[2]) * s), col)
		"gaea":
			ci.draw_colored_polygon(PackedVector2Array([P.call(-0.7, 0.5), P.call(-0.08, -0.6), P.call(0.18, -0.15), P.call(0.32, -0.36), P.call(0.72, 0.5)]), col)
			ci.draw_colored_polygon(PackedVector2Array([P.call(-0.3, 0.5), P.call(-0.08, 0.1), P.call(0.14, 0.5)]), bg)
		"blade":
			ci.draw_colored_polygon(PackedVector2Array([P.call(-0.32, 0.32), P.call(0.6, -0.6), P.call(0.42, -0.24), P.call(-0.2, 0.44)]), col)
			ci.draw_colored_polygon(_quad(P.call(-0.5, 0.12), P.call(-0.12, 0.5), 0.14 * s), col)
			ci.draw_colored_polygon(_quad(P.call(-0.36, 0.36), P.call(-0.6, 0.6), 0.12 * s), col)
		"shadow":
			ci.draw_circle(c, 0.6 * s, col)
			ci.draw_circle(c + Vector2(0.26, -0.16) * s, 0.5 * s, bg)
			ci.draw_colored_polygon(PackedVector2Array([P.call(0.42, 0.2), P.call(0.5, 0.36), P.call(0.66, 0.42), P.call(0.5, 0.48), P.call(0.42, 0.64), P.call(0.34, 0.48), P.call(0.18, 0.42), P.call(0.34, 0.36)]), col)
		"ultimate":
			var st := PackedVector2Array()
			for k in 10:
				var a := -PI / 2.0 + k * PI / 5.0
				var r := 0.66 if k % 2 == 0 else 0.28
				st.append(c + Vector2(cos(a), sin(a)) * r * s)
			ci.draw_colored_polygon(st, col)
		"zero":
			var arc := PackedVector2Array()
			for k in 9: var a := deg_to_rad(200.0 + k * 17.5); arc.append(c + Vector2(cos(a), sin(a)) * 0.66 * s)
			for k in 9: var a := deg_to_rad(340.0 - k * 17.5); arc.append(c + Vector2(cos(a), sin(a) * 0.55 + 0.18) * 0.48 * s)
			ci.draw_colored_polygon(arc, col)
		_:
			ci.draw_circle(c, 0.14 * s, col)

## hexágono dividido na diagonal com as duas cores de uma armadura (a cor principal em cima, a de detalhe embaixo)
static func color_chip(ci: CanvasItem, c: Vector2, r: float, prim: Color, sec: Color, rot := PI / 6.0, a := 1.0) -> void:
	var hx := hexagon(c, r, rot)
	var p := prim if prim.get_luminance() > 0.12 else prim.lightened(0.18)
	ci.draw_colored_polygon(PackedVector2Array([hx[2], hx[3], hx[4], hx[5]]), Color(p, a))
	ci.draw_colored_polygon(PackedVector2Array([hx[5], hx[0], hx[1], hx[2]]), Color(sec, a))
	ci.draw_line(hx[2], hx[5], Color(0, 0.02, 0.06, 0.55 * a), 1.0)
	ci.draw_line(hx[3].lerp(hx[4], 0.25), hx[4].lerp(hx[5], 0.6), Color(1, 1, 1, 0.35 * a), 1.0)   # brilho

## hexágono (pontas para os lados), raio r, girado a radianos
static func hexagon(c: Vector2, r: float, rot := 0.0) -> PackedVector2Array:
	var p := PackedVector2Array()
	for k in 6: p.append(c + Vector2(cos(rot + k * PI / 3.0), sin(rot + k * PI / 3.0)) * r)
	return p

## distintivo da armadura: hexágono dividido em 4 (capacete em cima, corpo à direita, pernas embaixo, braços à
## esquerda) com as cores das peças; com as 4 da mesma armadura, o emblema dela no meio
static func badge(ci: CanvasItem, c: Vector2, r: float, cols: Dictionary, full_key := "", glow := 0.0) -> void:
	var dirs := {"helmet": -PI / 2.0, "body": 0.0, "legs": PI / 2.0, "arms": PI}
	for slot in dirs:
		var cc: Array = cols[slot]
		var on: bool = cc[2]
		var a0: float = dirs[slot] - PI / 4.0
		var pts := PackedVector2Array([c])
		for k in 7:
			var a := a0 + k * (PI / 2.0) / 6.0
			var rel := fposmod(a, PI / 3.0) - PI / 6.0   # distância até a borda do hexágono nesse ângulo
			pts.append(c + Vector2(cos(a), sin(a)) * r * cos(PI / 6.0) / cos(rel))
		var col: Color = (cc[0] as Color) if on else Color(0.06, 0.13, 0.26)
		ci.draw_colored_polygon(pts, col)
	var hx := hexagon(c, r); var hl := hx.duplicate(); hl.append(hx[0])
	ci.draw_line(c + Vector2(-r * 0.86, 0), c + Vector2(r * 0.86, 0), Color(0, 0.02, 0.06, 0.8), 1.0)
	ci.draw_line(c + Vector2(0, -r * 0.86), c + Vector2(0, r * 0.86), Color(0, 0.02, 0.06, 0.8), 1.0)
	ci.draw_polyline(hl, C_EDGE_HI.lerp(C_GOLD, glow), 1.0)
	if full_key != "":   # armadura completa: as duas cores dela no meio
		var fc: Array = ARM_COL.get(full_key, ARM_COL[""])
		ci.draw_colored_polygon(hexagon(c, r * 0.55), Color(0.02, 0.05, 0.12, 0.9))
		color_chip(ci, c, r * 0.45, fc[0], fc[1], 0.0)
