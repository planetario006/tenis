extends SceneTree
# Vuelca las poses del saque procedural para revisarlas y medir el punto de contacto.
func _init():
	var pl := Player.new()
	root.add_child(pl)
	pl.setup(1, true)
	pl.global_position = Vector3.ZERO
	await process_frame
	pl.begin_serve_raise()
	var out := []
	var frames := 0
	var phase_done := {}
	while pl.serve_phase != "none" and frames < 400:
		await process_frame
		frames += 1
		if pl.serve_phase == "hold" and not phase_done.has("hold"):
			phase_done["hold"] = true
			_cap(pl, "trophy", out)
			pl.begin_serve_swing(Vector3(0, 2, 0), false, {})
		if pl.serve_phase == "swing" and pl._swing_t >= pl._swing_tc - 0.02:
			if not phase_done.has("contact"):
				phase_done["contact"] = true
				_cap(pl, "contact", out)
		if pl.serve_phase == "follow" and pl._serve_t > 0.25 and not phase_done.has("follow"):
			phase_done["follow"] = true
			_cap(pl, "follow", out)
		if pl.serve_phase == "raise" and pl._serve_t > 0.2 and not phase_done.has("toss"):
			phase_done["toss"] = true
			_cap(pl, "toss", out)
	var fa := FileAccess.open("res://tools/serve_poses.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(out)); fa.close()
	print("done frames=", frames)
	quit()
func _cap(pl: Player, tag: String, out: Array) -> void:
	var d := {"tag": tag}
	var sk := pl.skeleton
	for i in sk.get_bone_count():
		var p: Vector3 = pl.to_local(sk.global_transform * sk.get_bone_global_pose(i).origin)
		d[sk.get_bone_name(i)] = [p.x, p.y, p.z]
	var h: Vector3 = pl.to_local(pl.racket_head.global_position)
	d["racket_head"] = [h.x, h.y, h.z]
	var g := pl.racket_head.global_transform.basis
	d["racket_y"] = [g.y.x, g.y.y, g.y.z]
	d["racket_z"] = [g.z.x, g.z.y, g.z.z]
	out.append(d)
	print(tag, " racket_head(local)=", h)
