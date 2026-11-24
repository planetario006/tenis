class_name Player
extends Node3D
## Jugador 3D basado en Barbarian.glb + tenista_animaciones.res + raqueta.glb.
##
## IMPORTANTE (alcance del personaje): no es una persona real. Brazo corto y cabeza grande:
## de hombro a mano hay 0.67 u frente a 2.2 u de altura (≈ 30 %; en una persona ≈ 44 %).
## Por eso NO se usa un "radio de golpeo" genérico: el punto de contacto de la raqueta se midió
## directamente sobre tus animaciones (CONTACT_HEAD, en unidades del modelo) y el jugador se
## desplaza (lunge) para que esa cabeza de raqueta coincida con la pelota en el instante exacto.

signal swing_contact(player: Player, ctx: Dictionary)
signal serve_contact(player: Player, ctx: Dictionary)

const SCALE := 0.9
const RACKET_SCALE := 0.72
const GRIP_OFFSET := 0.225             # centro del mango (unidades del glb de la raqueta)
const HEAD_CENTER := 0.42              # centro del aro (unidades del glb de la raqueta)
const SWING_START := 0.20              # s dentro de la animación donde empieza el golpe
const SWING_SPEED := 1.6               # velocidad de reproducción del golpe
const CONTACT_T := 0.55                # s dentro de la animación donde está el contacto
const FOLLOW_TIME := 0.24
const LUNGE_MAX := 1.9
## Posición de la cabeza de la raqueta en el contacto, espacio del modelo (x izq. del personaje, z frente).
const CONTACT_HEAD := {"drive": Vector3(-0.05, 0.96, 0.71), "reves": Vector3(0.69, 0.51, 0.77)}
## Giro de la raqueta sobre su eje del mango para que la cara mire al frente en cada golpe.
const RACKET_ROLL := {"drive": 1.675, "reves": 0.0, "idle": 0.75}
const SERVE_SWING_T := 0.30
const SERVE_HEAD := Vector3(-0.17, 1.92, 0.30)   # contacto del saque (m, espacio del modelo; medido con tools/serve_pose.gd)
const RUN_ANIMS := {"fwd": "correr_adelante", "back": "correr_atras", "right": "correr_derecha", "left": "correr_izquierda"}

var side := 1
var is_human := false
var yaw := 0.0
var vel := Vector3.ZERO
var move_dir := Vector2.ZERO           # entrada de movimiento en ejes del mundo (x, z)
var stamina := 1.0
var state := "idle"                    # idle | swing | serve | frozen
var anim: AnimationPlayer
var skeleton: Skeleton3D
var visual: Node3D
var model: Node3D
var racket_roll_node: Node3D
var racket_head: Node3D
var _roll_target := 0.75
var _swing_t := 0.0
var _swing_tc := 0.2
var _swing_from := Vector3.ZERO
var _swing_to := Vector3.ZERO
var _swing_ctx: Dictionary = {}
var _contact_done := false
var _cur_anim := ""
var swing_kind := ""
## Zona legal del sacador: {xmin, xmax, zb}. zb = distancia mínima |z| (siempre DETRÁS de la línea de fondo).
var serve_zone: Dictionary = {}
# --- saque procedural ---
var serve_phase := "none"              # none | raise | hold | swing | follow
var _serve_t := 0.0
var _serve_pose_from: Dictionary = {}
var _serve_blend := 0.0

func setup(p_side: int, human: bool, tint: Color = Color.WHITE) -> void:
	process_priority = 100        # que _process (poses del saque) corra DESPUÉS del AnimationPlayer
	side = p_side
	is_human = human
	yaw = PI if side > 0 else 0.0
	visual = Node3D.new()
	visual.name = "Visual"
	visual.scale = Vector3.ONE * SCALE
	visual.rotation.y = yaw
	add_child(visual)
	model = (load("res://assets/Barbarian.glb") as PackedScene).instantiate()
	model.name = "Barbarian"          # las pistas de la librería empiezan en "Barbarian/Rig_Medium/..."
	visual.add_child(model)
	anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	visual.add_child(anim)
	anim.root_node = anim.get_path_to(visual)
	anim.add_animation_library("", load("res://animaciones/tenista_animaciones.res"))
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	_build_racket()
	if tint != Color.WHITE:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D)
			for s in m.get_surface_override_material_count():
				var base := m.get_active_material(s)
				if base is StandardMaterial3D:
					var mm := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
					mm.albedo_color = mm.albedo_color * tint
					m.set_surface_override_material(s, mm)
	_play("idle", 0.0)

func _build_racket() -> void:
	var att := BoneAttachment3D.new()
	att.bone_name = "handslot.r"
	skeleton.add_child(att)
	racket_roll_node = Node3D.new()
	att.add_child(racket_roll_node)
	var pivot := Node3D.new()
	pivot.scale = Vector3.ONE * RACKET_SCALE
	pivot.position = Vector3(0, GRIP_OFFSET * RACKET_SCALE, 0)
	racket_roll_node.add_child(pivot)
	var rk := (load("res://assets/raqueta.glb") as PackedScene).instantiate() as Node3D
	pivot.add_child(rk)
	var cols := {"Aro": Color(0.75, 0.08, 0.1), "Garganta": Color(0.12, 0.12, 0.14),
		"Cordaje": Color(0.95, 0.95, 0.95, 0.55), "Mango": Color(0.06, 0.06, 0.07)}
	for nm in cols:
		var n := rk.find_child(nm, true, false)
		if n is MeshInstance3D:
			var m := StandardMaterial3D.new()
			m.albedo_color = cols[nm]
			if nm == "Cordaje":
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
			(n as MeshInstance3D).material_override = m
	racket_head = Node3D.new()
	racket_head.position = Vector3(0, HEAD_CENTER, 0)
	rk.add_child(racket_head)
	racket_roll_node.rotation.y = RACKET_ROLL.idle

# ------------------------------------------------------------------------------------------
# Geometría
# ------------------------------------------------------------------------------------------
func clamp_to_serve_zone(p: Vector3) -> Vector3:
	if serve_zone.is_empty():
		return p
	p.x = clampf(p.x, float(serve_zone.xmin), float(serve_zone.xmax))
	if side > 0:
		p.z = clampf(p.z, float(serve_zone.zb), Court.HALF_L + 4.0)
	else:
		p.z = clampf(p.z, -(Court.HALF_L + 4.0), -float(serve_zone.zb))
	return p

func right_vec() -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3(-1, 0, 0)

func forward_vec() -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3(0, 0, 1)

func contact_delay() -> float:
	return (CONTACT_T - SWING_START) / SWING_SPEED

func contact_offset(kind: String) -> Vector3:
	return Basis(Vector3.UP, yaw) * (CONTACT_HEAD[kind] * SCALE)

func serve_offset() -> Vector3:
	return Basis(Vector3.UP, yaw) * SERVE_HEAD

func hand_world(left: bool) -> Vector3:
	var idx := skeleton.find_bone("handslot.l" if left else "handslot.r")
	return skeleton.global_transform * skeleton.get_bone_global_pose(idx).origin

## ¿Dónde tendría que estar la raíz del jugador para que su raqueta toque ball_p? (sólo plano XZ)
func reach_for(kind: String, ball_p: Vector3) -> Dictionary:
	var off := contact_offset(kind)
	var target := Vector3(ball_p.x - off.x, 0.0, ball_p.z - off.z)
	return {"target": target, "dist": Vector2(target.x - global_position.x, target.z - global_position.z).length()}

func reach_for_serve(ball_p: Vector3) -> Dictionary:
	var off := serve_offset()
	var target := Vector3(ball_p.x - off.x, 0.0, ball_p.z - off.z)
	return {"target": target, "dist": Vector2(target.x - global_position.x, target.z - global_position.z).length()}

# ------------------------------------------------------------------------------------------
# Movimiento
# ------------------------------------------------------------------------------------------
func max_speed() -> float:
	return 6.2 * (0.72 + 0.28 * clampf(stamina / 0.5, 0.0, 1.0))

func _physics_process(delta: float) -> void:
	match state:
		"swing":
			_process_swing(delta)
		"serve":
			_process_serve(delta)
		"frozen":
			vel = Vector3.ZERO
		_:
			_process_move(delta)
	racket_roll_node.rotation.y = lerp_angle(racket_roll_node.rotation.y, _roll_target, clampf(delta * 14.0, 0.0, 1.0))
	stamina = clampf(stamina, 0.0, 1.0)

func _process_move(delta: float) -> void:
	var want := Vector3(move_dir.x, 0.0, move_dir.y)
	if want.length() > 1.0:
		want = want.normalized()
	var target_v := want * max_speed()
	vel = vel.move_toward(target_v, 30.0 * delta)
	global_position += vel * delta
	var p := global_position
	p.x = clampf(p.x, -(Court.HALF_W + 4.5), Court.HALF_W + 4.5)
	if side > 0:
		p.z = clampf(p.z, 1.0, Court.HALF_L + 5.0)
	else:
		p.z = clampf(p.z, -(Court.HALF_L + 5.0), -1.0)
	global_position = clamp_to_serve_zone(p)
	var spd := vel.length()
	if spd > 0.75 * max_speed():
		stamina -= 0.075 * delta
	elif spd < 0.5:
		stamina += 0.10 * delta
	else:
		stamina += 0.02 * delta
	# animación
	if spd < 0.6:
		_play("idle", 0.2)
	else:
		var f := vel.dot(forward_vec())
		var r := vel.dot(right_vec())
		var key := "fwd"
		if absf(f) >= absf(r) * 0.8:
			key = "fwd" if f > 0.0 else "back"
		else:
			key = "right" if r > 0.0 else "left"
		_play(RUN_ANIMS[key], 0.15)
		anim.speed_scale = clampf(spd / 4.5, 0.7, 1.6)
	if _cur_anim == "idle":
		anim.speed_scale = 1.0
	_roll_target = RACKET_ROLL.idle

func _play(name: String, blend: float) -> void:
	if _cur_anim == name and anim.is_playing():
		return
	_cur_anim = name
	anim.play(name, blend)

# ------------------------------------------------------------------------------------------
# Golpe
# ------------------------------------------------------------------------------------------
func begin_swing(kind: String, contact_ball_p: Vector3, can_hit: bool, ctx: Dictionary) -> void:
	state = "swing"
	swing_kind = kind
	_swing_ctx = ctx
	_swing_t = 0.0
	_swing_tc = contact_delay()
	_contact_done = false
	_swing_from = global_position
	_swing_to = global_position
	if can_hit:
		var rf := reach_for(kind, contact_ball_p)
		var d := (rf.target as Vector3) - global_position
		if d.length() > LUNGE_MAX:
			d = d.normalized() * LUNGE_MAX
		_swing_to = global_position + d
	vel = Vector3.ZERO
	var an := "drive_topspin" if kind == "drive" else "reves_topspin"
	_cur_anim = an
	anim.play(an, 0.05, SWING_SPEED)
	anim.seek(SWING_START, true)
	_roll_target = RACKET_ROLL[kind]

func _process_swing(delta: float) -> void:
	_swing_t += delta
	var k := clampf(_swing_t / _swing_tc, 0.0, 1.0)
	global_position = _swing_from.lerp(_swing_to, k * k * (3.0 - 2.0 * k))
	if not _contact_done and _swing_t >= _swing_tc:
		_contact_done = true
		swing_contact.emit(self, _swing_ctx)
	if _swing_t >= _swing_tc + FOLLOW_TIME:
		state = "idle"
		_cur_anim = ""
		_roll_target = RACKET_ROLL.idle
		_play("idle", 0.25)

# ------------------------------------------------------------------------------------------
# Saque procedural (la librería de animaciones no trae saque)
# Poses expresadas como direcciones de huesos en espacio del modelo (x = izquierda del
# personaje, y = arriba, z = frente). Se resuelven con rotación de arco mínimo por hueso.
# ------------------------------------------------------------------------------------------
const SERVE_POSES := {
	"toss": {
		"chest": Vector3(0, 1, -0.05), "uparm_l": Vector3(0.35, 0.85, 0.40), "lowarm_l": Vector3(0.30, 0.93, 0.20),
		"uparm_r": Vector3(-0.25, -0.95, 0.05), "lowarm_r": Vector3(-0.15, -0.9, 0.35), "racket": Vector3(0.1, 0.2, 0.97),
		"upleg": Vector3(0, -1, 0.0), "lowleg": Vector3(0, -1, 0.0), "drop": 0.0},
	"trophy": {
		"chest": Vector3(0.05, 0.97, -0.25), "uparm_l": Vector3(0.30, 0.95, 0.40), "lowarm_l": Vector3(0.20, 1.0, 0.25),
		"uparm_r": Vector3(-0.95, 0.15, -0.25), "lowarm_r": Vector3(-0.15, 0.85, -0.5), "racket": Vector3(0.0, -0.55, -0.83),
		"upleg": Vector3(0, -0.88, 0.45), "lowleg": Vector3(0, -0.92, -0.38), "drop": 0.07},
	"contact": {
		"chest": Vector3(0, 0.97, 0.22), "uparm_l": Vector3(0.5, -0.7, 0.45), "lowarm_l": Vector3(0.3, -0.4, 0.85),
		"uparm_r": Vector3(-0.12, 0.95, 0.28), "lowarm_r": Vector3(-0.08, 0.98, 0.18), "racket": Vector3(-0.03, 0.9, 0.42),
		"upleg": Vector3(0, -1, 0.05), "lowleg": Vector3(0, -1, -0.02), "drop": -0.03},
	"follow": {
		"chest": Vector3(0.1, 0.95, 0.3), "uparm_l": Vector3(0.3, -0.9, 0.1), "lowarm_l": Vector3(0.2, -0.9, 0.3),
		"uparm_r": Vector3(0.35, -0.75, 0.55), "lowarm_r": Vector3(0.6, -0.6, 0.5), "racket": Vector3(0.8, -0.2, 0.5),
		"upleg": Vector3(0, -0.96, 0.25), "lowleg": Vector3(0, -0.98, -0.15), "drop": 0.02},
}
var _cur_pose: Dictionary = {}

func begin_serve_raise() -> void:
	state = "serve"
	serve_phase = "raise"
	_serve_t = 0.0
	_cur_pose = {}
	anim.play("idle", 0.1)
	_cur_anim = "idle"

func begin_serve_swing(contact_ball_p: Vector3, can_hit: bool, ctx: Dictionary) -> float:
	_swing_ctx = ctx
	_contact_done = false
	_swing_t = 0.0
	_swing_tc = SERVE_SWING_T
	serve_phase = "swing"
	_serve_t = 0.0
	_serve_pose_from = _cur_pose.duplicate()
	_swing_from = global_position
	_swing_to = global_position
	if can_hit:
		var rf := reach_for_serve(contact_ball_p)
		var d := (rf.target as Vector3) - global_position
		if d.length() > 0.9:
			d = d.normalized() * 0.9
		_swing_to = clamp_to_serve_zone(global_position + d)   # nunca pisar la pista antes de golpear
	return _swing_tc

func end_serve() -> void:
	serve_phase = "none"
	state = "idle"
	_cur_anim = ""
	_roll_target = RACKET_ROLL.idle
	_play("idle", 0.25)

func _process_serve(delta: float) -> void:
	_serve_t += delta
	match serve_phase:
		"raise":
			var u := clampf(_serve_t / 0.55, 0.0, 1.0)
			_cur_pose = _blend_pose(SERVE_POSES.toss, SERVE_POSES.trophy, (u - 0.35) / 0.65) if u > 0.35 else _blend_pose({}, SERVE_POSES.toss, u / 0.35)
			if _serve_t >= 0.55:
				serve_phase = "hold"
		"hold":
			_cur_pose = SERVE_POSES.trophy
		"swing":
			_swing_t += delta
			var k := clampf(_swing_t / _swing_tc, 0.0, 1.0)
			global_position = _swing_from.lerp(_swing_to, k * k * (3.0 - 2.0 * k))
			_cur_pose = _blend_pose(_serve_pose_from, SERVE_POSES.contact, minf(k * 1.1, 1.0))
			if not _contact_done and _swing_t >= _swing_tc:
				_contact_done = true
				serve_contact.emit(self, _swing_ctx)
			if _swing_t >= _swing_tc:
				serve_phase = "follow"
				_serve_t = 0.0
				_serve_pose_from = _cur_pose.duplicate()
		"follow":
			var u2 := clampf(_serve_t / 0.28, 0.0, 1.0)
			_cur_pose = _blend_pose(_serve_pose_from, SERVE_POSES.follow, u2)
			if _serve_t >= 0.45:
				end_serve()
	vel = Vector3.ZERO

func _blend_pose(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	## Mezcla dos poses. Si `a` está vacía se mezcla desde la pose de la animación (idle) con peso u.
	var out := {}
	if a.is_empty():
		out = b.duplicate()
		out["w"] = u
		return out
	for k in b:
		if k == "drop":
			out[k] = lerpf(float(a.get("drop", 0.0)), float(b[k]), u)
		elif k == "w":
			continue
		else:
			out[k] = (a[k] as Vector3).lerp(b[k], u).normalized()
	out["w"] = 1.0
	return out

func _process(_delta: float) -> void:
	if state == "serve" and not _cur_pose.is_empty():
		_apply_pose(_cur_pose)

func _aim(bone: String, dir_model: Vector3, weight: float = 1.0) -> void:
	var i := skeleton.find_bone(bone)
	var parent := skeleton.get_bone_parent(i)
	var rest_g := skeleton.get_bone_global_rest(i)
	var cur_y := rest_g.basis.y.normalized()
	var arc := Quaternion(cur_y, dir_model.normalized())
	var new_g := Basis(arc) * rest_g.basis
	var parent_g := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var local_b := parent_g.inverse() * new_g
	var q := local_b.get_rotation_quaternion()
	if weight < 1.0:
		q = skeleton.get_bone_pose_rotation(i).slerp(q, weight)
	skeleton.set_bone_pose_rotation(i, q)

func _apply_pose(p: Dictionary) -> void:
	var w := float(p.get("w", 1.0))
	var hips := skeleton.find_bone("hips")
	var hp := skeleton.get_bone_pose_position(hips)
	var rest_y := skeleton.get_bone_rest(hips).origin.y
	hp.y = lerpf(hp.y, rest_y - float(p.get("drop", 0.0)) / SCALE, w)
	skeleton.set_bone_pose_position(hips, hp)
	_aim("spine", p.chest, w)
	_aim("chest", p.chest, w)
	for s in ["l", "r"]:
		_aim("upperarm." + s, p["uparm_" + s], w)
		_aim("lowerarm." + s, p["lowarm_" + s], w)
		_aim("wrist." + s, p["lowarm_" + s], w)
	for s in ["l", "r"]:
		_aim("upperleg." + s, p.upleg, w)
		_aim("lowerleg." + s, p.lowleg, w)
	# orientar la raqueta: su eje (Y del handslot) a lo largo de p.racket
	var shaft: Vector3 = (p.racket as Vector3).normalized()
	var face_hint := Vector3(0, -0.4, 0.9) if shaft.y > 0.3 else Vector3(0.9, 0.2, 0.2)
	var zz := (face_hint - shaft * shaft.dot(face_hint)).normalized()
	var xx := shaft.cross(zz).normalized()
	var s_des := Basis(xx, shaft, zz)
	var hand := skeleton.find_bone("hand.r")
	var slot := skeleton.find_bone("handslot.r")
	var slot_local := skeleton.get_bone_rest(slot).basis
	var hand_g := s_des * slot_local.inverse()
	var wrist_g := skeleton.get_bone_global_pose(skeleton.get_bone_parent(hand)).basis
	var qh := (wrist_g.inverse() * hand_g).get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(hand, skeleton.get_bone_pose_rotation(hand).slerp(qh, w))
	_roll_target = lerpf(RACKET_ROLL.idle, 0.0, w)
