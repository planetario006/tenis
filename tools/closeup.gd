extends SceneTree
# Captura de cerca del contacto del drive y del revés (para revisar la raqueta).
func _init():
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 30, 0); root.add_child(sun)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.25, 0.3, 0.4)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.8, 0.8, 0.85); e.ambient_light_energy = 0.6
	env.environment = e; root.add_child(env)
	var floor_mi := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(10, 10); floor_mi.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.15, 0.35, 0.65); floor_mi.material_override = fm; root.add_child(floor_mi)
	var cam := Camera3D.new(); cam.fov = 40; root.add_child(cam)
	await process_frame
	cam.position = Vector3(-2.6, 1.6, 2.2); cam.look_at(Vector3(0, 0.95, -0.3))
	cam.current = true
	var kinds := ["drive", "reves"]
	var idx := 0
	for kind in kinds:
		var pl := Player.new(); root.add_child(pl); pl.setup(1, true); pl.global_position = Vector3.ZERO
		await process_frame
		pl.begin_swing(kind, Vector3(0, 0.8, -0.6), false, {})
		var shot := false
		while pl.state == "swing" and not shot:
			await physics_frame
			if pl._swing_t >= pl._swing_tc + 0.012:
				await process_frame
				await process_frame
				root.get_viewport().get_texture().get_image().save_png("/tmp/closeup_%s.png" % kind)
				shot = true
		pl.queue_free()
		await process_frame
	quit()
