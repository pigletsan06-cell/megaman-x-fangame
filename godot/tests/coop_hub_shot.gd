extends SceneTree
## menu do co-op no hub (O / L1) com a sala criada -> /tmp/coop_hub.png
func _init() -> void:
	FangameSave.load_file(); FangameSave.select(0)
	change_scene_to_file("res://scenes/hub.tscn")
	for i in 5: await process_frame
	var h = current_scene
	h.jogo_open = false; h.in_page = true; h.page = h.GAMES.find("x6")
	var ev := InputEventKey.new(); ev.keycode = KEY_O; ev.pressed = true
	h._unhandled_input(ev)
	for i in 10: await process_frame
	root.get_texture().get_image().save_png("/tmp/coop_hub0.png")
	var en := InputEventKey.new(); en.keycode = KEY_ENTER; en.pressed = true
	h._unhandled_input(en)
	for i in 240: await process_frame
	root.get_texture().get_image().save_png("/tmp/coop_hub.png")
	Coop.me.leave()
	quit()
