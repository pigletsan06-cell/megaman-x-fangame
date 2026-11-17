extends SceneTree
func _init() -> void:
	var bad := 0
	var t0 := Time.get_ticks_msec()
	for f in DirAccess.get_files_at("res://scripts/x4c/gen"):
		if not f.ends_with(".gd"): continue
		var s = load("res://scripts/x4c/gen/" + f)
		if s == null or not s.can_instantiate():
			bad += 1
			print("FALHOU ", f)
	print("ok, ruins=", bad, " ms=", Time.get_ticks_msec() - t0)
	quit()
