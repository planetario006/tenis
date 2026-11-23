class_name World
extends Node3D
## Construye la pista, la red, el entorno y la iluminación por código.

var surface_key := "hard"
var _court_mesh: MeshInstance3D
var _outer_mesh: MeshInstance3D
var _marks: Node3D

func build(key: String) -> void:
	surface_key = key
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.76, 0.85)
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -25, 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	_outer_mesh = _box(Vector3(60, 0.1, 80), Vector3(0, -0.06, 0), Color.WHITE)
	_court_mesh = _box(Vector3(18.0, 0.1, 36.5), Vector3(0, -0.045, 0), Color.WHITE)
	_marks = Node3D.new()
	add_child(_marks)
	set_surface(key)
	_build_lines()
	_build_net()
	_build_surroundings()

func set_surface(key: String) -> void:
	surface_key = key
	var s: Dictionary = Court.SURFACES[key]
	(_court_mesh.material_override as StandardMaterial3D).albedo_color = s.court
	(_outer_mesh.material_override as StandardMaterial3D).albedo_color = s.outer
	for c in _marks.get_children():
		c.queue_free()

func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _box(size: Vector3, pos: Vector3, c: Color, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = pos
	(parent if parent else self).add_child(mi)
	return mi

func _line(x0: float, z0: float, x1: float, z1: float) -> void:
	var w := 0.06
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var sx := absf(x1 - x0) + (w if x0 == x1 else 0.0)
	var sz := absf(z1 - z0) + (w if z0 == z1 else 0.0)
	var mi := _box(Vector3(sx, 0.004, sz), Vector3(cx, 0.006, cz), Color(0.96, 0.96, 0.96))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_lines() -> void:
	var hl := Court.HALF_L
	var hw := Court.HALF_W
	var dw := Court.NET_HALF_W
	for s in [-1.0, 1.0]:
		_line(-dw, s * hl, dw, s * hl)                       # línea de fondo
		_line(-hw, s * Court.SERVICE_Z, hw, s * Court.SERVICE_Z)
		_line(0.0, s * hl, 0.0, s * (hl - 0.25))             # marca central
	_line(-hw, -hl, -hw, hl)
	_line(hw, -hl, hw, hl)
	_line(-dw, -hl, -dw, hl)
	_line(dw, -hl, dw, hl)
	_line(0.0, -Court.SERVICE_Z, 0.0, Court.SERVICE_Z)

func _build_net() -> void:
	var w := Court.NET_HALF_W * 2.0
	var img := Image.create(256, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in 256:
		for y in 32:
			if x % 6 < 1 or y % 6 < 1:
				img.set_pixel(x, y, Color(0.08, 0.08, 0.08, 0.85))
	var tex := ImageTexture.create_from_image(img)
	var qm := QuadMesh.new()
	qm.size = Vector2(w, 0.95)
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.position = Vector3(0, 0.5, 0)
	add_child(mi)
	_box(Vector3(w, 0.07, 0.03), Vector3(0, 0.96, 0), Color.WHITE)            # cinta superior
	for s in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.05
		cm.height = Court.NET_POST_H + 0.05
		post.mesh = cm
		post.material_override = _mat(Color(0.1, 0.1, 0.12))
		post.position = Vector3(s * (Court.NET_HALF_W + 0.05), cm.height * 0.5, 0)
		add_child(post)

func _build_surroundings() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wall_c := Color(0.07, 0.16, 0.14)
	for s in [-1.0, 1.0]:
		_box(Vector3(40, 1.1, 0.3), Vector3(0, 0.55, s * 17.5), wall_c)                 # fondo
		_box(Vector3(0.3, 1.1, 36), Vector3(s * 11.5, 0.55, 0), wall_c)                # lateral
		for i in 5:
			_box(Vector3(5.5, 0.8, 0.05), Vector3(-14.0 + i * 7.0, 0.55, s * 17.34), Color(0.95, 0.95, 0.95) if i % 2 == 0 else Color(0.9, 0.75, 0.1))
	# gradas (bloques escalonados con "público")
	for s in [-1.0, 1.0]:
		for row in 6:
			var y: float = 0.8 + row * 0.7
			var z: float = s * (18.5 + row * 0.9)
			var tier := _box(Vector3(40, 0.6, 0.9), Vector3(0, y, z), Color(0.18, 0.2, 0.25))
			tier.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for k in 28:
				var c := Color.from_hsv(rng.randf(), rng.randf_range(0.2, 0.6), rng.randf_range(0.35, 0.9))
				var h := _box(Vector3(0.35, 0.55, 0.3), Vector3(-19.0 + k * 1.4 + rng.randf() * 0.4, y + 0.55, z), c)
				h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# banquillo del juez de silla
	_box(Vector3(0.9, 2.4, 0.9), Vector3(-6.4, 1.2, 0.0), Color(0.25, 0.27, 0.3))

func add_mark(p: Vector3) -> void:
	if not Court.SURFACES[surface_key].marks:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.07
	cm.height = 0.002
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.2, 0.1, 0.6)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.position = Vector3(p.x, 0.008, p.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marks.add_child(mi)
	if _marks.get_child_count() > 60:
		_marks.get_child(0).queue_free()
