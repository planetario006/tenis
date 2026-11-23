extends SceneTree
# Muestrea las animaciones y vuelca posiciones de huesos en espacio del modelo
func _init():
	var vis := Node3D.new(); vis.name = "Visual"
	root.add_child(vis)
	var m: Node3D = (load("res://assets/Barbarian.glb") as PackedScene).instantiate()
	m.name = "Barbarian"
	vis.add_child(m)
	var ap := AnimationPlayer.new(); vis.add_child(ap)
	ap.root_node = ap.get_path_to(vis)
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	ap.add_animation_library("", load("res://animaciones/tenista_animaciones.res"))
	var sk: Skeleton3D = m.find_child("Skeleton3D", true, false)
	print("root_node=", ap.root_node, " sk path=", ap.get_path_to(sk))
	var out := {}
	for an in ap.get_animation_list():
		var L: float = ap.get_animation(an).length
		var frames := []
		var n := 27
		for i in n + 1:
			var t: float = L * i / n
			ap.play(an)
			ap.seek(t, true)
			await process_frame
			var f := {"t": t}
			for b in sk.get_bone_count():
				var p: Vector3 = sk.get_bone_global_pose(b).origin
				f[sk.get_bone_name(b)] = [p.x, p.y, p.z]
			var hs: Transform3D = sk.get_bone_global_pose(sk.find_bone("handslot.r"))
			f["racket_y"] = [hs.basis.y.x, hs.basis.y.y, hs.basis.y.z]
			f["racket_z"] = [hs.basis.z.x, hs.basis.z.y, hs.basis.z.z]
			f["racket_x"] = [hs.basis.x.x, hs.basis.x.y, hs.basis.x.z]
			frames.append(f)
		out[an] = {"length": L, "frames": frames}
	var fa := FileAccess.open("res://tools/samples.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(out))
	fa.close()
	print("OK")
	quit()
