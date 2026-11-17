extends SceneTree
## Testa o hub: LANCAR="x5:5:0:1" (jogo:fase:personagem:código) e tira fotos
func _init() -> void:
	var p := OS.get_environment("LANCAR").split(":")
	X4Machine.launch = {"game": p[0], "stage": int(p[1]), "char": int(p[2]), "armor": int(p[3]), "char_code": int(p[3])}
	if p.size() > 4: X4Machine.launch["pokes"] = [[p[4].hex_to_int(), p[5].hex_to_int(), 1]]
	change_scene_to_file("res://scenes/fase.tscn")
	var n := int(OS.get_environment("FRAMES") if OS.get_environment("FRAMES") != "" else "600")
	var dir := OS.get_environment("SHOTDIR") if OS.get_environment("SHOTDIR") != "" else "/tmp"
	for f in n:
		await process_frame
		var m = current_scene
		if f % 60 == 0 and m:
			var ph = m.get("launch_phase")
			print(f, " cena=", m.name, " fase_hub=", ph, " lf=", m.get("lf"))
			root.get_texture().get_image().save_png(dir + "/hub_%d.png" % f)
		if m and m.has_method("step_frame") and m.get("launch_phase") == 2:
			m.forced = (1 << 13) if (f / 90) % 2 == 0 else 0
	quit()
