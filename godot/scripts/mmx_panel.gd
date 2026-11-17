class_name MmxPanel
extends Control
## Painel dos menus com abertura animada (desenho original): uma linha de luz estica na horizontal, o painel abre na
## vertical a partir dela e o conteúdo aparece por último (com uma varredura de luz descendo). Fechar faz o caminho de
## volta, mais rápido. O conteúdo vai em `content` (coordenadas do painel) e é recortado pela moldura durante a animação.

signal closed

var title := ""
var accent := MmxUI.C_ACCENT
var cut := 6.0
var t := 0.0              # 0 fechado, 1 aberto
var dir := 0              # 1 abrindo, -1 fechando
var opened_at := 0.0      # relógio quando terminou de abrir (para animações do conteúdo)
var clock := 0.0
var content: Control
var _clip: Control
const T_OPEN := 0.3
const T_CLOSE := 0.16
const SPLIT := 0.36       # parte da abertura em que só a linha estica

static func make(parent: Node, rect: Rect2, ttl := "", acc := MmxUI.C_ACCENT) -> MmxPanel:
	var p := MmxPanel.new()
	p.position = rect.position; p.size = rect.size; p.title = ttl; p.accent = acc
	parent.add_child(p)
	return p

func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip = Control.new(); _clip.clip_contents = true; _clip.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_clip)
	content = Control.new(); content.mouse_filter = Control.MOUSE_FILTER_IGNORE; _clip.add_child(content)
	set_process(false)

func open() -> void:
	if visible and dir >= 0 and t > 0.0: return
	visible = true; dir = 1
	set_process(true); _layout()

func close() -> void:
	if not visible or dir == -1: return
	dir = -1; set_process(true)

func shown() -> bool:
	return visible and dir != -1

## quanto do conteúdo já apareceu (0..1)
func reveal() -> float:
	return clampf((t - 0.55) / 0.45, 0.0, 1.0)

func _cur() -> Rect2:
	var a := MmxUI.ease_out(t / SPLIT)
	var b := MmxUI.ease_out((t - SPLIT) / (1.0 - SPLIT))
	var w := roundf(maxf(4.0, size.x * a)); var h := roundf(maxf(2.0, size.y * b))
	return Rect2(Vector2(roundf((size.x - w) * 0.5), roundf((size.y - h) * 0.5)), Vector2(w, h))

func _process(dt: float) -> void:
	clock += dt
	if dir > 0:
		t = minf(1.0, t + dt / T_OPEN)
		if t >= 1.0: dir = 0; opened_at = clock
	elif dir < 0:
		t = maxf(0.0, t - dt / T_CLOSE)
		if t <= 0.0:
			dir = 0; visible = false; set_process(false); closed.emit()
	_layout(); queue_redraw()
	for c in content.get_children():
		if c is CanvasItem: (c as CanvasItem).queue_redraw()

func _layout() -> void:
	var r := _cur()
	_clip.position = r.position; _clip.size = r.size
	content.position = -r.position; content.size = size
	content.modulate.a = reveal()

func _draw() -> void:
	var r := _cur()
	if t < SPLIT:   # a linha de luz esticando
		var y := roundf(size.y * 0.5)
		draw_rect(Rect2(r.position.x, y - 3, r.size.x, 6), Color(accent.r, accent.g, accent.b, 0.25))
		draw_rect(Rect2(r.position.x, y - 1, r.size.x, 2), Color(1, 1, 1, 0.95))
		return
	MmxUI.frame(self, r, accent, cut)
	if t > 0.8 and title != "": MmxUI.title_tab(self, Rect2(Vector2.ZERO, size), title, accent)
	if dir == 1 and t > 0.55:   # varredura de luz descendo enquanto o conteúdo aparece
		var sy := roundf(r.position.y + r.size.y * (t - 0.55) / 0.45)
		draw_rect(Rect2(r.position.x + 2, sy - 2, r.size.x - 4, 2), Color(accent.r, accent.g, accent.b, 0.35))
		draw_rect(Rect2(r.position.x + 2, sy, r.size.x - 4, 1), Color(1, 1, 1, 0.6))
