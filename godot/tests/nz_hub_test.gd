extends SceneTree
## tela de status do hub com o cartão do Nightmare Zero escolhido -> /tmp/nz_hub.png
func _init() -> void:
	FangameSave.load_file(); FangameSave.select(0)
	var sv := FangameSave.cur()
	sv["zero"] = (sv.get("zero", []) as Array).filter(func(k): return not str(k).begins_with("NZ:"))
	var ks := OS.get_environment("NZKEYS")
	for k in (["helmet", "arms", "legs+"] if ks == "" else Array(ks.split(","))): sv.zero.append("NZ:" + k)
	change_scene_to_file("res://scenes/hub.tscn")
	for i in 5: await process_frame
	var h = current_scene
	h.jogo_open = false; h.in_page = true; h.page = h.GAMES.find("x6"); h.is_zero = true; h.zero_idx["x6"] = 2
	h.status_open = true; h.status_sel = h.STATUS_ARMORS.size() + 1
	h._refresh()
	for i in 30: await process_frame
	root.get_texture().get_image().save_png("/tmp/nz_hub.png")
	h.status_open = false; h._refresh()
	for i in 10: await process_frame
	root.get_texture().get_image().save_png("/tmp/nz_hub2.png")
	quit()
