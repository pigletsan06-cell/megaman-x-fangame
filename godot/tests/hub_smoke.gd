extends SceneTree
## fumaça do hub novo: título -> continuar -> save 1 -> escolha do jogo (X5) -> pula a abertura -> começa a fase
var h
func _key(k: int) -> void:
	var ev := InputEventKey.new(); ev.keycode = k; ev.pressed = true
	current_scene._unhandled_input(ev)
func _wait(f: int) -> void:
	for i in f: await process_frame
func _init() -> void:
	change_scene_to_file("res://scenes/title.tscn")
	await _wait(110)
	_key(KEY_ENTER); await _wait(10)     # press start -> menu (continuar)
	_key(KEY_ENTER); await _wait(30)     # continuar -> saves
	_key(KEY_ENTER); await _wait(60)     # jogar o save
	print("cena: ", current_scene.name)
	await _wait(30)
	_key(KEY_RIGHT); await _wait(5)      # X5
	_key(KEY_ENTER); await _wait(20)     # entra (abertura)
	_key(KEY_Z); await _wait(20)         # pula a abertura
	print("página: ", current_scene.get("page"), " jogo aberto: ", current_scene.get("jogo_open"))
	_key(KEY_ENTER); await _wait(5)      # começa a fase
	print("depois do Enter: ", current_scene.name if current_scene else "-")
	for f in 2400:
		await process_frame
		var m = current_scene
		if m and m.get("launch_phase") == 2: print("fase rodando no quadro ", f); break
	root.get_texture().get_image().save_png("/tmp/smoke_fase.png")
	quit()
