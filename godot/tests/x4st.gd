extends SceneTree
func _init() -> void:
	for k in ["MMX4_ORACLE_SCENE", "MMX4_DIRECT_STAGE", "MMX4_DIRECT_CHARACTER", "MMX4_DIRECT_LOADOUT"]:
		if OS.get_environment(k) != "": X4R.env[k] = OS.get_environment(k)
	var m := X4Machine.new()
	root.add_child(m)
	await process_frame
	m.set_process(false)
	var last := ""
	for f in 6000:
		m.forced = (1 << 13) if (f / 120) % 2 == 0 else (1 << 6)
		m.step_frame(false)
		var s := "%d/%d st%d" % [ClassDB.class_call_static("X4Core", "mem", 0, 0, 1), ClassDB.class_call_static("X4Core", "mem", 1, 0, 1), ClassDB.class_call_static("X4Core", "mem", 2, 0, 1)]
		if s != last: print(f, " ", s); last = s
	quit()
