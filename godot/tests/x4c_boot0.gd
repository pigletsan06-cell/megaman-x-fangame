extends SceneTree
func _init() -> void:
	X4R.init(); X4R.gpu_init(); X4R.tk_limit = 2000000
	printerr("init ok")
	X4M_godot_frame.c_godot_boot()
	printerr("boot ok")
	for f in int(OS.get_environment("FRAMES") if OS.get_environment("FRAMES") != "" else "3"):
		X4R.vsync_count += 1; X4R.prims.clear()
		var t0 := Time.get_ticks_msec()
		X4M_godot_frame.c_godot_frame()
		printerr("quadro ", f, " ms=", Time.get_ticks_msec() - t0, " prims=", X4R.prims.size(), " cd_lba=", X4R.cd_lba, " lendo=", X4R.cd_reading)
	printerr("faltando: ", X4R.missing.keys().slice(0, 30))
	quit()
