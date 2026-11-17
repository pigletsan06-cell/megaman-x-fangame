extends SceneTree
## fotos dos menus novos (MmxUI): escolha do jogo, tela dos chefes (barra, aviso), armadura (abrindo e aberta, X e
## Zero), status, finais e co-op -> /tmp/menu_NN_nome.png
var h
var n := 0
func _key(k: int) -> void:
	var ev := InputEventKey.new(); ev.keycode = k; ev.pressed = true
	h._unhandled_input(ev)
func _wait(f: int) -> void:
	for i in f: await process_frame
func _shot(nm: String) -> void:
	n += 1
	root.get_texture().get_image().save_png("/tmp/menu_%02d_%s.png" % [n, nm])
func _init() -> void:
	FangameSave.load_file(); FangameSave.select(0)
	change_scene_to_file("res://scenes/hub.tscn")
	await _wait(6)
	h = current_scene
	h.jogo_open = true; h.in_page = false; h.jogo_sel = 1; h._refresh()
	await _wait(8); _shot("jogo_entrando")
	await _wait(50); _shot("jogo")
	h.jogo_open = false; h.in_page = true; h.page = int(OS.get_environment("PAGE")) if OS.get_environment("PAGE") != "" else 1
	h._refresh(); await _wait(20); _shot("chefes")
	_key(KEY_W); await _wait(14); _shot("aviso_armadura")
	await _wait(120)
	_key(KEY_C); await _wait(5); _shot("arm_linha")
	await _wait(6); _shot("arm_abrindo")
	await _wait(14); _shot("arm_holograma_entrando")
	await _wait(60); _shot("arm_aberto")
	# montada: o conjunto até a "montada"
	for i in 6:
		if h._arm_is_custom(h.GAMES[h.page]): break
		_key(KEY_RIGHT); await _wait(3)
	await _wait(40); _shot("arm_montada")
	_key(KEY_DOWN); _key(KEY_DOWN); await _wait(30); _shot("arm_corpo")
	_key(KEY_RIGHT); await _wait(4); _shot("arm_trocou_flash")
	await _wait(60); _shot("arm_trocou")
	_key(KEY_ESCAPE); await _wait(4); _shot("arm_fechando"); await _wait(20)
	_key(KEY_V); await _wait(30); _key(KEY_RIGHT); await _wait(20); _shot("personagem_zero"); _key(KEY_V); await _wait(12)
	await _wait(120)
	_key(KEY_C); await _wait(70); _shot("arm_zero")
	_key(KEY_RIGHT); await _wait(60); _shot("arm_zero_bz")
	_key(KEY_ESCAPE); await _wait(20)
	_key(KEY_V); await _wait(10); _key(KEY_LEFT); _key(KEY_V); await _wait(10)
	_key(KEY_TAB); await _wait(40); _shot("status")
	for i in 7: _key(KEY_RIGHT)
	await _wait(30); _shot("status_bz")
	_key(KEY_TAB); await _wait(20)
	_key(KEY_BACKSPACE); await _wait(40); _shot("finais")
	_key(KEY_BACKSPACE); await _wait(20)
	_key(KEY_O); await _wait(40); _shot("coop")
	_key(KEY_ESCAPE); await _wait(20)
	quit()
