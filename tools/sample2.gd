extends SceneTree
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
	var hs_idx := sk.find_bone("handslot.r")
	var out := {}
	for an in ["drive_topspin", "reves_topspin"]:
		var frames := []
		var t := 0.40
		while t <= 0.70:
			ap.play(an); ap.seek(t, true)
			await process_frame
			var hs: Transform3D = sk.get_bone_global_pose(hs_idx)
			frames.append({"t": t, "o": [hs.origin.x, hs.origin.y, hs.origin.z],
				"x": [hs.basis.x.x, hs.basis.x.y, hs.basis.x.z],
				"y": [hs.basis.y.x, hs.basis.y.y, hs.basis.y.z],
				"z": [hs.basis.z.x, hs.basis.z.y, hs.basis.z.z],
				"hips": [sk.get_bone_global_pose(1).origin.x, sk.get_bone_global_pose(1).origin.y, sk.get_bone_global_pose(1).origin.z]})
			t += 0.005
		out[an] = frames
	var fa := FileAccess.open("res://tools/samples2.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(out)); fa.close()
	print("OK"); quit()
