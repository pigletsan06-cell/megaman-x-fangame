extends SceneTree
func _init() -> void:
	var m = load("res://scenes/x4_original.tscn").instantiate()
	root.add_child(m)
	var t0 := Time.get_ticks_msec()
	var shots := [500, 2500, 6000, 9000, 12000, 14000]
	var i := 0
	while i < shots.size():
		await process_frame
		if Time.get_ticks_msec() - t0 >= shots[i]:
			root.get_texture().get_image().save_png("/tmp/mov_%d.png" % i)
			print("t=", shots[i], " video=", m.movie_on, " booted=", m.booted)
			i += 1
	quit()
