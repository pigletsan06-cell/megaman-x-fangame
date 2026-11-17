extends SceneTree
func _init() -> void:
	X4R.env["MMX4_ORACLE_SCENE"] = "mission-briefing"; X4R.env["MMX4_DIRECT_STAGE"] = "1"; X4R.env["MMX4_DIRECT_CHARACTER"] = "0"
	var m := X4Machine.new(); root.add_child(m); await process_frame; m.set_process(false)
	var last := ""
	for f in 1500:
		m.forced = (1 << 6) if f % 40 < 3 and f > 300 else 0
		m.step_frame(false)
		var s := "%d/%d" % [ClassDB.class_call_static("X4Core", "mem", 0, 0, 1), ClassDB.class_call_static("X4Core", "mem", 1, 0, 1)]
		if s != last: print(f, " ", s, " movie=", ClassDB.class_call_static("X4Core", "movie_request")); last = s
	quit()
