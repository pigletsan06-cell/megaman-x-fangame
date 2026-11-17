extends SceneTree
## fotos da tela de título com o estilo novo: opções (abrindo e aberta) e saves -> /tmp/titulo_NN_nome.png
var h
var n := 0
func _key(k: int) -> void:
	var ev := InputEventKey.new(); ev.keycode = k; ev.pressed = true
	h._unhandled_input(ev)
func _wait(f: int) -> void:
	for i in f: await process_frame
func _shot(nm: String) -> void:
	n += 1
	root.get_texture().get_image().save_png("/tmp/titulo_%02d_%s.png" % [n, nm])
func _init() -> void:
	change_scene_to_file("res://scenes/title.tscn")
	await _wait(6)
	h = current_scene
	await _wait(100)
	_key(KEY_ENTER); await _wait(20); _shot("menu")
	_key(KEY_DOWN); _key(KEY_DOWN); await _wait(4)
	_key(KEY_ENTER); await _wait(8); _shot("opcoes_abrindo")
	await _wait(40); _shot("opcoes")
	_key(KEY_ESCAPE); await _wait(30)
	_key(KEY_UP); await _wait(4)
	_key(KEY_ENTER); await _wait(10); _shot("saves_entrando")
	await _wait(50); _shot("saves")
	quit()
