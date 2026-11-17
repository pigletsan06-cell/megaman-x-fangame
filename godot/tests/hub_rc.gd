extends SceneTree
## hub: deixa o cursor parado (PAGINA, ESPERA quadros), aperta Start e mede até a fase começar
func _init() -> void:
	FangameSave.load_file(); FangameSave.select(0)
	change_scene_to_file("res://scenes/hub.tscn")
	for i in 5: await process_frame
	var h = current_scene
	h.jogo_open = false; h.in_page = true; h.page = int(OS.get_environment("PAGINA")); h.is_zero = OS.get_environment("ZERO") == "1"; h._refresh()
	var espera := int(OS.get_environment("ESPERA"))
	for f in espera:
		await process_frame
		if f % 60 == 0: print("hub ", f, " rotulo=", h.pre_label.text if h.pre_label else "", " lf=", h.pre_node.lf if h.pre_node else -1)
	root.get_texture().get_image().save_png("/tmp/hubpre_menu.png")
	h._start()
	for f in 600:
		await process_frame
		var m = current_scene
		if m and m.get("launch_phase") == 2:
			print("fase começou ", f, " quadros depois do Start")
			for k in 120: await process_frame
			root.get_texture().get_image().save_png("/tmp/hubpre_fase.png")
			if OS.get_environment("ANDA") != "":
				var x0 := int(m.core_mem(0x970A0 + 0x18, 2)) if m.has_method("core_mem") else 0
				for k in 200: await process_frame
				m.forced = 1 << 13
				for k in 120: await process_frame
				m.forced = 0
				root.get_texture().get_image().save_png("/tmp/hubpre_anda.png")
				print("som disponível: ", m.playback.get_frames_available() if m.playback else -1)
			break
	quit()
