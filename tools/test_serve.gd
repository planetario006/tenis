extends SceneTree
func _init():
	var p0 := Vector3(1.3, 1.95, 12.6)
	for name in ["serve_flat", "serve_kick", "serve_slice"]:
		for pw in [0.5, 0.8, 1.0]:
			for tz in [-4.5, -5.6]:
				var tgt := Vector3(-2.0, 0.0, tz)
				var pl := BallPhysics.plan(p0, tgt, Shots.TYPES[name], pw, 70.0 if name == "serve_slice" else 0.0)
				var tr := BallPhysics.trace(p0, pl.v, pl.w, 1.0 / 120.0, 3.0, 60.0)
				print("%-11s pw=%.1f tz=%.1f ok=%s v=%3.0f km/h th=%5.1f° clear=%.2f land=(%.2f,%.2f)" % [name, pw, tz, pl.ok, pl.speed * 3.6, rad_to_deg(pl.theta), tr.net_clear, tr.land.x, tr.land.z])
	quit()
