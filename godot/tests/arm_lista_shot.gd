extends SceneTree
## fotos do menu da armadura (lista): conjunto, montada (peça do corpo, trocando) e Zero -> /tmp/arm_NN_nome.png
## PAGE = 0 X4, 1 X5, 2 X6
var h
var n := 0
func _key(k: int) -> void:
	var ev := InputEventKey.new(); ev.keycode = k; ev.pressed = true
	h._unhandled_input(ev)
func _wait(f: int) -> void:
	for i in f: await process_frame
func _shot(nm: String) -> void:
	n += 1
	root.get_texture().get_image().save_png("/tmp/arm_%02d_%s.png" % [n, nm])
func _init() -> void:
	FangameSave.load_file(); FangameSave.select(0)
	change_scene_to_file("res://scenes/hub.tscn")
	await _wait(6)
	h = current_scene
	h.jogo_open = false; h.in_page = true; h.page = int(OS.get_environment("PAGE")) if OS.get_environment("PAGE") != "" else 1
	h._refresh(); await _wait(20)
	var g: String = h.GAMES[h.page]
	h.is_zero = false; h.arm_row = 0
	h.armor_idx[g] = 1
	_key(KEY_C); await _wait(10); _shot("abrindo")
	await _wait(70); _shot("conjunto")
	_key(KEY_DOWN); _key(KEY_RIGHT); await _wait(20); _shot("aviso_conjunto")
	for i in h._armors(g).size():
		if h._arm_is_custom(g): break
		h.armor_idx[g] = i
	h.arm_row = 2; h.arm_change_t = h.t_anim
	await _wait(50); _shot("montada_corpo")
	_key(KEY_RIGHT); await _wait(5); _shot("trocando")
	await _wait(60); _shot("trocou")
	_key(KEY_LEFT); await _wait(10)
	_key(KEY_ESCAPE); await _wait(30)
	# Zero: algumas peças ganhas só para a foto (não grava)
	var sv: Dictionary = FangameSave.cur()
	var z: Array = sv.get("zero", []).duplicate()
	for k in ["BZ:helmet", "BZ:helmet+", "BZ:arms", "NZ:body", "NZ:legs", "NZ:legs+"]: if not k in z: z.append(k)
	sv["zero"] = z
	h.is_zero = true; h.zero_idx[g] = 1; h.arm_row = 0
	_key(KEY_C); await _wait(80); _shot("zero_bz")
	_key(KEY_DOWN); await _wait(40); _shot("zero_bz_capacete")
	_key(KEY_RIGHT); await _wait(40); _shot("zero_bz_capacete_melhoria")
	_key(KEY_DOWN); _key(KEY_DOWN); await _wait(40); _shot("zero_bz_bracos_melhoria")
	_key(KEY_UP); _key(KEY_UP); _key(KEY_UP); await _wait(10)
	_key(KEY_RIGHT); await _wait(40); _shot("zero_nz")
	_key(KEY_DOWN); _key(KEY_DOWN); await _wait(40); _shot("zero_nz_corpo")
	_key(KEY_ESCAPE); await _wait(30)
	h.is_zero = false
	quit()
