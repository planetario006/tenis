extends SceneTree
func _init():
	var surf: Dictionary = Court.SURFACES.hard
	var p0 := Vector3(1.5, 0.75, 11.0)
	var target := Vector3(-2.0, 0.0, -10.0)
	for name in ["topspin", "flat", "slice", "lob", "drop"]:
		var shot: Dictionary = Shots.TYPES[name]
		for pw in [0.3, 0.7, 1.0]:
			var tgt := target
			if name == "drop":
				tgt = Vector3(-1.0, 0.0, -2.5)
			var t0 := Time.get_ticks_usec()
			var pl := BallPhysics.plan(p0, tgt, shot, pw)
			var dt_ms := (Time.get_ticks_usec() - t0) / 1000.0
			var tr := BallPhysics.trace(p0, pl.v, pl.w, 1.0 / 120.0, 4.0, 60.0)
			print("%-8s pw=%.1f ok=%s v=%.1f m/s (%.0f km/h) th=%.1f° clear=%.2f land=(%.2f,%.2f) err=%.2f  plan=%.0f ms" % [name, pw, pl.ok, pl.speed, pl.speed * 3.6, rad_to_deg(pl.theta), tr.net_clear, tr.land.x, tr.land.z, Vector2(tr.land.x - tgt.x, tr.land.z - tgt.z).length(), dt_ms])
	# efecto del espín en el rebote
	print("--- rebote tras caer con v=(0,-6,-18) ---")
	for sp in [-250.0, 0.0, 250.0]:
		var d := Vector3(0, 0, -1)
		var w := BallPhysics.spin_vector(d, sp)
		var rb := BallPhysics.bounce(Vector3(0, -6, -18), w, surf.e, surf.mu)
		var vv: Vector3 = rb[0]
		print("spin %+4.0f: v'=(%.1f, %.1f, %.1f) ángulo salida=%.1f° ω'=%.0f" % [sp, vv.x, vv.y, vv.z, rad_to_deg(atan2(vv.y, absf(vv.z))), (rb[1] as Vector3).length()])
	quit()
