class_name Fx
extends Node2D
## Efeito visual com animação do jogo original (tiros, brilho de carga, explosões).
## Os quadros vêm de assets/x/fx (extraídos do PL00_U.ARC do X4).
## Os sprites originais dos efeitos olham para a ESQUERDA; flip = virado para a direita.

static var _atlas: SpriteAtlas = null
static var _names := {}

## Animações tiradas de src/main/sprite_animations.c e visual_04_blast.c (mmx4).
## Cada passo: [duração, nome do quadro, evento]
const ANIMS := {
	"lemon": [[2, "lemon_0"], [1, "lemon_1"], [1, "lemon_2"], [1, "lemon_3"], [1, "lemon_4", true],
			[2, "lemon_5"], [2, "lemon_6"], [2, "lemon_7"], [2, "lemon_8"], [2, "lemon_9"]],
	"semi_muzzle": [[2, "semi_77"], [1, "semi_78"], [1, "semi_79"], [1, "semi_79", true], [2, "semi_7a"]],
	"semi": [[2, "semi_7b"], [2, "semi_7c"], [2, "semi_7d"], [2, "semi_7e"]],
	"full_muzzle": [[2, "full_21"], [1, "full_22"], [2, "full_23"], [1, "full_24"], [1, "full_24", true],
			[3, "full_25"], [3, "full_27"]],
	"full": [[3, "full_26"], [3, "full_28"], [3, "full_29"]],
	"glow_semi": [[2, "glow_5a"], [2, "glow_5b"], [2, "glow_5c"], [2, "glow_5d"], [2, "glow_5e"],
			[2, "glow_5f"], [2, "glow_60"], [2, "glow_61"], [2, "glow_62"], [2, "glow_63"]],
	"glow_full": [[1, "glow_64"], [1, "glow_68"], [1, "glow_65"], [1, "glow_68"], [1, "glow_66"],
			[1, "glow_68"], [1, "glow_67"], [1, "glow_68"]],
	"blast": [[2, "blast_2"], [2, "blast_3"], [2, "blast_4"], [2, "blast_5"], [2, "blast_6"],
			[2, "blast_7"], [2, "blast_8"], [2, "blast_9"], [2, "blast_a"], [2, "blast_b"], [2, "blast_c"],
			[3, "blast_d"], [3, "blast_e"], [4, "blast_f"], [5, "blast_10"], [6, "blast_11"]],
}

var anim_name := ""
var steps: Array = []
var step_i := 0
var timer := 0
var loop_to := -1            # -1 = some no fim
var flip := false
var vel := Vector2.ZERO
var follow: Node2D = null    # segue um nó (ex.: cano do buster)
var follow_offset := Vector2.ZERO
var event_fired := false
var on_event: Callable
var delay := 0               # quadros antes de aparecer

static func atlas() -> SpriteAtlas:
	if _atlas == null:
		_atlas = SpriteAtlas.load_from("res://assets/x/fx")
		var f := FileAccess.open("res://assets/x/fx/frames.json", FileAccess.READ)
		if f != null:
			_names = JSON.parse_string(f.get_as_text()).get("names", {})
	return _atlas

static func frame_index(n: String) -> int:
	atlas()
	return int(_names.get(n, -1))

static func make(anim: String, pos: Vector2, flip_right: bool, loop := -1) -> Fx:
	var e := Fx.new()
	e.position = pos
	e.flip = flip_right
	e.play(anim, loop)
	return e

func play(anim: String, loop := -1) -> void:
	anim_name = anim
	steps = ANIMS[anim]
	step_i = 0
	timer = 0
	loop_to = loop
	event_fired = false

func current_frame() -> int:
	if steps.is_empty():
		return -1
	return frame_index(steps[mini(step_i, steps.size() - 1)][1])

func _physics_process(_dt: float) -> void:
	advance()

## Um quadro de efeito. Retorna false quando o efeito acabou.
func advance() -> bool:
	if delay > 0:
		delay -= 1
		visible = false
		return true
	visible = true
	if follow != null and is_instance_valid(follow):
		position = follow.position + follow_offset
	position += vel
	timer += 1
	var st: Array = steps[step_i]
	if timer >= int(st[0]):
		timer = 0
		if st.size() > 2 and st[2] and not event_fired:
			event_fired = true
			if on_event.is_valid():
				on_event.call(self)
		step_i += 1
		if step_i >= steps.size():
			if loop_to < 0:
				step_i = steps.size() - 1
				visible = false
				queue_free()
				return false
			step_i = loop_to
	queue_redraw()
	return true

func _draw() -> void:
	atlas().draw(self, current_frame(), Vector2.ZERO, flip)
