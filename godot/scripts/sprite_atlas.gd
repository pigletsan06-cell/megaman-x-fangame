class_name SpriteAtlas
extends RefCounted
## Atlas extraído do jogo original: atlas.png + frames.json
## Cada quadro: x, y, w, h (posição no atlas) e ox, oy (origem do personagem dentro do quadro).

var texture: Texture2D
var frames: Array = []
var variants: Array = []   # mesmas posições, outras cores (ex.: X piscando ao carregar)

static func load_from(dir: String) -> SpriteAtlas:
	var a := SpriteAtlas.new()
	a.texture = _load_png(dir + "/atlas.png")
	var f := FileAccess.open(dir + "/frames.json", FileAccess.READ)
	if f == null:
		push_error("frames.json não encontrado: " + dir)
		return a
	var data = JSON.parse_string(f.get_as_text())
	a.frames = data["frames"]
	return a

static func _load_png(path: String) -> Texture2D:
	# Carrega o PNG direto, sem depender da importação do editor
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		push_error("imagem não encontrada: " + path)
		return null
	return ImageTexture.create_from_image(img)

## carrega variantes de cor (png com o mesmo layout): variante n = n-ésimo arquivo
func load_variants(paths: Array) -> void:
	variants = [texture]
	for p in paths:
		if FileAccess.file_exists(p): variants.append(_load_png(p))
		else: variants.append(texture)

func has_frame(i: int) -> bool:
	return i >= 0 and i < frames.size() and frames[i] != null

## Desenha o quadro i com a origem do personagem em `pos`. flip = virado para a esquerda.
func draw(ci: CanvasItem, i: int, pos: Vector2, flip: bool, modulate := Color.WHITE, variant := 0) -> void:
	if not has_frame(i) or texture == null:
		return
	var tex: Texture2D = variants[variant] if variant > 0 and variant < variants.size() else texture
	var fr: Dictionary = frames[i]
	var src := Rect2(fr["x"], fr["y"], fr["w"], fr["h"])
	var dst := Rect2(-float(fr["ox"]), -float(fr["oy"]), float(fr["w"]), float(fr["h"]))
	ci.draw_set_transform(pos.round(), 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	ci.draw_texture_rect_region(tex, dst, src, modulate)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Igual a draw, mas só as linhas do quadro entre y0 e y1 (coordenadas de quem desenha)
func draw_clip(ci: CanvasItem, i: int, pos: Vector2, flip: bool, modulate: Color, variant: int, y0: float, y1: float) -> void:
	if not has_frame(i) or texture == null: return
	var tex: Texture2D = variants[variant] if variant > 0 and variant < variants.size() else texture
	var fr: Dictionary = frames[i]
	var top := pos.round().y - float(fr["oy"])
	var a := clampf(y0 - top, 0.0, float(fr["h"])); var b := clampf(y1 - top, 0.0, float(fr["h"]))
	if b <= a: return
	var src := Rect2(fr["x"], float(fr["y"]) + a, fr["w"], b - a)
	var dst := Rect2(-float(fr["ox"]), -float(fr["oy"]) + a, float(fr["w"]), b - a)
	ci.draw_set_transform(pos.round(), 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	ci.draw_texture_rect_region(tex, dst, src, modulate)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func bounds(i: int, pos: Vector2) -> Rect2:   # retângulo do quadro na tela
	if not has_frame(i): return Rect2(pos, Vector2.ZERO)
	var fr: Dictionary = frames[i]
	return Rect2(pos.x - float(fr["w"]) / 2.0, pos.y - float(fr["oy"]), float(fr["w"]), float(fr["h"]))

## Distância da origem até a base (pés) do quadro.
func bottom_of(i: int) -> float:
	if not has_frame(i):
		return 0.0
	return float(frames[i]["h"]) - float(frames[i]["oy"])
