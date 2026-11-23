class_name AIController
extends Node
## IA de la CPU (también puede jugar por el humano en modo --auto para pruebas).

var game
var pl: Player
var difficulty := 0.6
var plan: Dictionary = {}
var enabled := true            # false = el humano se mueve a mano
var auto_swing := true         # false = sólo corre a la pelota; el golpe lo da el jugador
var assist := false            # modo ayuda del humano: llega justo a tiempo, sin fallos de timing
var _serve_wait := -1.0
var _serve_swung := false

func setup(g, p: Player, diff: float) -> void:
	game = g
	pl = p
	difficulty = diff

## La pelota acaba de ser golpeada o ha botado: recalcular dónde y cuándo se la puede devolver.
func on_ball_changed() -> void:
	plan = {}
	var ball: Ball = game.ball
	if not ball.active or ball.last_hitter == pl:
		return
	var pred := BallPhysics.predict(ball.global_position, ball.vel, ball.omega, ball.surface, 3.5, 1.0 / 60.0)
	var base := ball.bounce_count           # botes ya ocurridos desde el último golpe
	if base >= 2:
		return
	var first_b := -1
	if base >= 1:
		first_b = 0                         # ya botó: la fase útil empieza ahora
	else:
		for i in pred.size():
			if pred[i].b >= 1:
				first_b = i
				break
		if first_b == -1:
			return                          # no bota (red) -> no perseguir
		var land: Vector3 = pred[first_b].p
		if not Court.in_singles(land) or land.z * pl.side < 0.0:
			return                          # irá fuera: no perseguir
	# tipo de golpe por el lado en que pasará la bola, y altura ideal de contacto de ese golpe
	var ref_p: Vector3 = pred[first_b].p
	for i in range(first_b, pred.size()):
		if pred[i].p.y <= 1.0 and (base + int(pred[i].b)) <= 1:
			ref_p = pred[i].p
			break
	var kind0 := "drive" if (ref_p - pl.global_position).dot(pl.right_vec()) >= 0.0 else "reves"
	var h_ref: float = Player.CONTACT_HEAD[kind0].y * Player.SCALE
	var best := -1
	for i in range(first_b, pred.size()):
		var s: Dictionary = pred[i]
		if base + int(s.b) > 1 or pl.side * s.p.z < 0.2:
			break
		if s.v.y <= 0.3 and s.p.y <= h_ref + 0.02:
			best = i
			break
	if best == -1:
		var bi := -1
		var by := -1.0
		for i in range(first_b, pred.size()):
			if base + int(pred[i].b) > 1:
				break
			if pred[i].p.y > by and pred[i].p.y <= h_ref + 0.3:
				by = pred[i].p.y
				bi = i
		best = bi
	if best == -1:
		return
	var P: Vector3 = pred[best].p
	var kind := "drive" if (P - pl.global_position).dot(pl.right_vec()) >= 0.0 else "reves"
	plan = {"t_ideal": game.game_time + float(pred[best].t), "P": P, "kind": kind, "swung": false,
		"jitter": 0.0 if assist else randfn(0.0, lerpf(0.07, 0.02, difficulty))}

func start_serve() -> void:
	_serve_wait = 1.1
	_serve_swung = false

func _physics_process(delta: float) -> void:
	if pl == null or game == null or not enabled:
		return
	match game.state:
		Game.S.SERVE_READY:
			pl.move_dir = Vector2.ZERO
			if _serve_wait > 0.0:
				_serve_wait -= delta
				if _serve_wait <= 0.0 and game.server_player() == pl:
					game.do_toss(pl)
		Game.S.SERVE_TOSS:
			if auto_swing and game.serving == pl and not _serve_swung and pl.serve_phase == "hold":
				_try_serve_swing()
		Game.S.RALLY:
			_rally(delta)
		_:
			pl.move_dir = Vector2.ZERO

func _try_serve_swing() -> void:
	var ball: Ball = game.ball
	if not ball.active:
		return
	var tc := Player.SERVE_SWING_T
	var pred := BallPhysics.predict(ball.global_position, ball.vel, ball.omega, ball.surface, 1.2, 1.0 / 90.0)
	var t_h := -1.0
	for s in pred:
		if s.v.y < 0.0 and s.p.y <= Player.SERVE_HEAD.y:
			t_h = s.t
			break
	if t_h < 0.0:
		return
	if t_h - tc <= randfn(0.0, lerpf(0.05, 0.015, difficulty)):
		_serve_swung = true
		var second: bool = game.serve_attempt == 2
		var r := randf()
		var shot := "serve_kick" if second else ("serve_flat" if r < 0.45 else ("serve_slice" if r < 0.75 else "serve_kick"))
		var power := randf_range(0.55, 0.8) if second else randf_range(0.65, 0.97)
		power *= lerpf(0.85, 1.0, difficulty)
		var box := Court.service_box_center(pl.side, game.x_sign)
		var tgt := Vector3(box.x + randf_range(-1.6, 1.6), 0.0, box.z + (-pl.side) * randf_range(-1.0, 1.2))
		game.request_serve_swing(pl, {"shot": shot, "power": power, "aim": tgt})

func _rally(delta: float) -> void:
	if plan.is_empty():
		_recover(delta)
		return
	if pl.state != "idle":
		return
	var kind: String = plan.kind
	var rf := pl.reach_for(kind, plan.P)
	var d: Vector3 = (rf.target as Vector3) - pl.global_position
	var dist := Vector2(d.x, d.z).length()
	var tc := pl.contact_delay()
	var tts: float = plan.t_ideal - game.game_time - tc + float(plan.jitter)
	if not plan.swung:
		if dist > 0.25:
			var dir := Vector2(d.x, d.z).normalized() * minf(1.0, dist * 3.0)
			pl.move_dir = dir
		else:
			pl.move_dir = Vector2.ZERO
		if tts <= 0.0 and auto_swing:
			plan.swung = true
			pl.move_dir = Vector2.ZERO
			game.request_swing(pl, _choose_ctx())
	else:
		pl.move_dir = Vector2.ZERO

func _recover(delta: float) -> void:
	if pl.state != "idle":
		return
	var ball: Ball = game.ball
	var tx := clampf(ball.global_position.x * 0.35, -2.2, 2.2)
	var tz: float = pl.side * (Court.HALF_L + 0.4)
	var d := Vector2(tx - pl.global_position.x, tz - pl.global_position.z)
	pl.move_dir = d.normalized() * minf(0.7, d.length() * 0.6) if d.length() > 0.3 else Vector2.ZERO

func _choose_ctx() -> Dictionary:
	var h: Player = game.human
	var r := randf()
	var shot := "topspin"
	if r < 0.22:
		shot = "flat"
	elif r < 0.36:
		shot = "slice"
	elif r < 0.42 and absf(h.global_position.z) < 6.0:
		shot = "lob"
	elif r < 0.47 and absf(h.global_position.z) > 8.0:
		shot = "drop"
	var power := randf_range(0.5, 0.85) * lerpf(0.85, 1.0, difficulty)
	var ax := clampf(-h.global_position.x * 0.5 + randf_range(-3.0, 3.0), -3.6, 3.6)
	var tz: float = -pl.side * randf_range(6.0, 10.6)
	return {"shot": shot, "power": power, "aim": Vector3(ax, 0.0, tz)}
