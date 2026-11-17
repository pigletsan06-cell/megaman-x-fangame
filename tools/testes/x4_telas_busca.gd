extends SceneTree
## busca: tela de seleção do X4 (cena mission-briefing do x4core) com o cursor em cada chefe -> /tmp/x4t/c<cursor>_<quadro>.png
func _init() -> void:
	X4R.env["MMX4_ORACLE_SCENE"] = "mission-briefing"; X4R.env["MMX4_DIRECT_STAGE"] = "1"; X4R.env["MMX4_DIRECT_CHARACTER"] = "0"
	var m := X4Machine.new(); root.add_child(m); await process_frame; m.set_process(false)
	var cur := 0
	for f in 1200:
		if f == 60: ClassDB.class_call_static("X4Core", "mem", 8, 0, -1)
		if f >= 200 and f % 120 == 80:
			cur = (f - 200) / 120
			ClassDB.class_call_static("X4Core", "mem", 9, cur, -1)
		m.step_frame(true)
		if f >= 200 and f % 120 == 60:
			await process_frame
			root.get_texture().get_image().save_png("/tmp/x4t/c%d_%d.png" % [cur, f])
	quit()
