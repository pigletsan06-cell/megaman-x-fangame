extends SceneTree
## Testa a vitória: X6 Yammark, começa antes do chefe, zera a vida do chefe e confere a volta ao hub
func _init() -> void:
	X4Machine.launch = {"game": "x6", "stage": 1, "char": 0, "armor": 0, "char_code": 0}
	change_scene_to_file("res://scenes/fase.tscn")
	for f in 6000:
		await process_frame
		var m = current_scene
		if m == null or not m.has_method("step_frame"):
			if m and m.name == "Hub": break
			continue
		var lf: int = m.lf
		if m.launch_phase == 1 and lf > 1450:
			ClassDB.class_call_static("PsxCore", "mem", 0xCCEEC, 0x0200, -2)   # ponto antes do chefe
		if m.launch_phase == 2:
			var b := 0
			if lf < 2600 or (lf >= 2900 and lf < 4800): b = (1 << 6) if lf % 30 < 3 else 0
			elif lf < 2900: b = 1 << 13
			else: b = (1 << 7) if lf % 16 < 4 else 0
			m.forced = b
			if lf >= 5000 and lf < 5010: ClassDB.class_call_static("PsxCore", "mem", 0x8EFA4, 0, -2)
		if f % 300 == 0: print(f, " lf=", lf, " fase=", m.launch_phase, " estado=", ClassDB.class_call_static("PsxCore", "mem", 0xCCED0, 0, 1), " venceu=", m.won)
	for i in 5: await process_frame
	print("cena final: ", current_scene.name if current_scene else "-", "  resultado: ", X4Machine.last_result)
	root.get_texture().get_image().save_png("/tmp/hub_win.png")
	quit()
