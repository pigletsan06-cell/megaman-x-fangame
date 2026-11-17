extends SceneTree
func _init() -> void:
	var mi := MeshInstance2D.new()
	var am := ArrayMesh.new()
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(0,0), Vector2(100,0), Vector2(0,100), Vector2(100,0), Vector2(100,100), Vector2(0,100)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0,0), Vector2(100,0), Vector2(0,100), Vector2(100,0), Vector2(100,100), Vector2(0,100)])
	var c := PackedFloat32Array()
	for i in 6: c.append_array([200.0, 0, 0, 100.0])
	arr[Mesh.ARRAY_CUSTOM0] = c
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	var m := ShaderMaterial.new(); m.shader = load("res://scripts/x4c/ct.gdshader")
	mi.material = m
	mi.mesh = am
	root.add_child(mi)
	for i in 3: await process_frame
	var img := root.get_texture().get_image()
	print(img.get_pixel(10, 10), img.get_pixel(90, 50))
	quit()
