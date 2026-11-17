extends SceneTree
func _k(k: int, p := true) -> InputEventKey:
	var e := InputEventKey.new(); e.keycode = k; e.physical_keycode = k; e.pressed = p; return e
func _init() -> void:
	change_scene_to_file("res://scenes/title.tscn")
	await process_frame; await process_frame
	var tt = current_scene
	tt.t = 2.2; tt._update(0.0)
	await process_frame; await process_frame
	root.get_texture().get_image().save_png("/tmp/sha/tt_press.png")
	tt._unhandled_input(_k(KEY_ENTER))
	await process_frame; await process_frame
	root.get_texture().get_image().save_png("/tmp/sha/tt_menu.png")
	tt._unhandled_input(_k(KEY_DOWN)); tt._unhandled_input(_k(KEY_ENTER))
	await process_frame; await process_frame
	root.get_texture().get_image().save_png("/tmp/sha/tt_opt.png")
	for i in 5: tt._unhandled_input(_k(KEY_DOWN))
	tt._unhandled_input(_k(KEY_ENTER))
	tt._unhandled_input(_k(KEY_ENTER))
	await process_frame
	tt._input(_k(KEY_ENTER, false)); tt._input(_k(KEY_K))
	await process_frame; await process_frame
	root.get_texture().get_image().save_png("/tmp/sha/tt_bot.png")
	print("pulo agora: ", Opcoes.key_name("jump"), " ", InputMap.action_get_events("jump"))
	Opcoes.data = Opcoes.defaults(); Opcoes.save_file()
	quit()
