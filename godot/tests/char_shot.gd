extends SceneTree
## fotos da escolha do personagem (△ / V) -> /tmp/char_NN_nome.png
var h
var n := 0
func _key(k: int) -> void:
	var ev := InputEventKey.new(); ev.keycode = k; ev.pressed = true
	h._unhandled_input(ev)
func _wait(f: int) -> void:
	for i in f: await process_frame
func _shot(nm: String) -> void:
	n += 1
	root.get_texture().get_image().save_png("/tmp/char_%02d_%s.png" % [n, nm])
func _init() -> void:
	FangameSave.load_file(); FangameSave.select(0)
	change_scene_to_file("res://scenes/hub.tscn")
	await _wait(6)
	h = current_scene
	h.jogo_open = false; h.in_page = true; h.page = int(OS.get_environment("PAGE")) if OS.get_environment("PAGE") != "" else 1
	h.is_zero = false
	h._refresh(); await _wait(20)
	_key(KEY_V); await _wait(8); _shot("abrindo")
	await _wait(40); _shot("x")
	_key(KEY_RIGHT); await _wait(4); _shot("trocando")
	await _wait(30); _shot("zero")
	print("is_zero depois da seta: ", h.is_zero)
	_key(KEY_V); await _wait(30); _shot("fechado")
	print("menu aberto? ", h.char_open, " is_zero: ", h.is_zero)
	_key(KEY_V); await _wait(20); _key(KEY_LEFT); await _wait(10); _key(KEY_ESCAPE); await _wait(20)
	print("depois de voltar pro X: ", h.is_zero, " aberto: ", h.char_open, " jogo_open: ", h.jogo_open)
	quit()
