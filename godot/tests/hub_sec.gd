extends SceneTree
## hub: Black Zero no X6 escolhido pelo menu, depois lança e fotografa
func _init() -> void:
	change_scene_to_file("res://scenes/hub.tscn")
	for i in 5: await process_frame
	var h = current_scene
	h.page = int(OS.get_environment("PAGINA"))
	h.is_zero = OS.get_environment("ZERO") == "1"
	for i in int(OS.get_environment("ARM")): h._cycle_armor(h.GAMES[h.page], 1)
	h._refresh()
	await process_frame; await process_frame
	root.get_texture().get_image().save_png("/tmp/hubsec_menu.png")
	h._start()
	for f in int(OS.get_environment("FRAMES")):
		await process_frame
		var m = current_scene
		if m and m.get("launch_phase") == 2 and f % 100 == 0:
			root.get_texture().get_image().save_png("/tmp/hubsec_%d.png" % f)
	print("launch=", X4Machine.launch)
	quit()
