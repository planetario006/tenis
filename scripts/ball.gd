class_name Ball
extends Node3D
## Pelota: integra la física real (arrastre + Magnus + rebote con fricción) a 120 Hz.

signal bounced(pos: Vector3, count: int)
signal net_touched(tape: bool)
signal went_dead()

const VISUAL_SCALE := 2.2        # sólo visual: la bola real mide 6,7 cm y no se vería

var vel := Vector3.ZERO
var omega := Vector3.ZERO
var active := false
var surface: Dictionary = Court.SURFACES.hard
var last_hitter: Node = null
var bounce_count := 0            # botes desde el último golpe
var net_hit := false
var is_serve := false
var _mesh: MeshInstance3D
var _shadow: MeshInstance3D
var _trail: Array[Vector3] = []

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = Court.BALL_R * VISUAL_SCALE
	sm.height = sm.radius * 2.0
	sm.radial_segments = 20
	sm.rings = 10
	_mesh.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.95, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.6, 0.05)
	mat.emission_energy_multiplier = 0.6
	_mesh.material_override = mat
	add_child(_mesh)
	_shadow = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.1
	cm.bottom_radius = 0.1
	cm.height = 0.002
	_shadow.mesh = cm
	var sm2 := StandardMaterial3D.new()
	sm2.albedo_color = Color(0, 0, 0, 0.45)
	sm2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow.material_override = sm2
	_shadow.top_level = true
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)
	visible = false

func launch(p: Vector3, v: Vector3, w: Vector3, hitter: Node) -> void:
	global_position = p
	vel = v
	omega = w
	active = true
	visible = true
	last_hitter = hitter
	bounce_count = 0
	net_hit = false

func hide_ball() -> void:
	active = false
	visible = false

func _physics_process(delta: float) -> void:
	if not active:
		return
	var p := global_position
	var r := BallPhysics.step(p, vel, omega, delta)
	var np: Vector3 = r[0]
	var nv: Vector3 = r[1]
	var nw: Vector3 = r[2]
	# --- red ---
	if p.z * np.z < 0.0 and absf(p.x) < Court.NET_HALF_W:
		var f := p.z / (p.z - np.z)
		var yc := lerpf(p.y, np.y, f)
		var xc := lerpf(p.x, np.x, f)
		var top := Court.net_height(xc)
		var rel := yc - Court.BALL_R - top
		if rel < 0.03:
			if rel > -0.02 and randf() < 0.5:   # cinta: se arrastra por encima
				nv *= 0.45
				nv.y = absf(nv.y) * 0.5 + 1.2
				net_hit = true
				net_touched.emit(true)
			else:                                  # se queda en la red
				net_hit = true
				np = Vector3(xc, maxf(yc, Court.BALL_R), signf(p.z) * 0.04)
				nv = Vector3(nv.x * 0.25, minf(nv.y, 0.0) * 0.2, -nv.z * 0.12)
				nw *= 0.3
				net_touched.emit(false)
	# --- suelo ---
	if np.y <= Court.BALL_R and nv.y < 0.0:
		var f2 := (p.y - Court.BALL_R) / maxf(p.y - np.y, 1e-6)
		var bp := p.lerp(np, f2)
		var rb := BallPhysics.bounce(v_lerp(vel, nv, f2), nw, surface.e, surface.mu)
		np = bp
		np.y = Court.BALL_R
		nv = rb[0]
		nw = rb[1]
		bounce_count += 1
		global_position = np
		vel = nv
		omega = nw
		bounced.emit(np, bounce_count)
	else:
		global_position = np
		vel = nv
		omega = nw
	if vel.length() < 0.25 and global_position.y < Court.BALL_R + 0.02:
		active = false
		went_dead.emit()
	if absf(global_position.z) > 40.0 or absf(global_position.x) > 30.0:
		active = false
		went_dead.emit()
	_mesh.rotate(omega.normalized() if omega.length() > 0.1 else Vector3.UP, omega.length() * delta * 0.15)

static func v_lerp(a: Vector3, b: Vector3, f: float) -> Vector3:
	return a.lerp(b, f)

func _process(_delta: float) -> void:
	if _shadow:
		var h := maxf(global_position.y, 0.0)
		_shadow.global_position = Vector3(global_position.x, 0.012, global_position.z)
		var s := 1.0 + h * 0.15
		_shadow.scale = Vector3(s, 1.0, s)
		(_shadow.material_override as StandardMaterial3D).albedo_color.a = clampf(0.5 - h * 0.05, 0.12, 0.5)
		_shadow.visible = visible
