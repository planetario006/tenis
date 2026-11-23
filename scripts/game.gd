class_name Game
extends Node3D
## Partido 1 vs CPU. Reglas: saque con dos intentos, red/let, dentro/fuera, doble bote, marcador completo.
## Argumentos de línea de órdenes (tras --):  --auto  --surface=clay  --seconds=N  --sets=1  --gps=2  --speed=4

enum S { SERVE_READY, SERVE_TOSS, RALLY, POINT_OVER, MATCH_OVER }

const TOSS_APEX := 2.45

var world: World
var ball: Ball
var human: Player
var cpu: Player
var players: Array[Player] = []
var cam: Camera3D
var hud: HUD
var hub: InputHub
var ai_cpu: AIController
var ai_human: AIController              # sólo en --auto
var score := TennisScore.new()
var state := S.SERVE_READY
var surface_key := "hard"
var game_time := 0.0
var serve_attempt := 1
var x_sign := 1
var serving: Player = null
var let_pending := false
var difficulty := 0.6
var cross: MeshInstance3D          # X amarilla: dónde botará la pelota del rival EN TU campo
var auto_move := true              # el jugador corre solo a la pelota (M o botón + del mando lo alternan)
var invert_lat := false            # invierte recto/cruzado (tecla V)
var _timer := 0.0
var _retoss_t := -1.0
var _toss_pending := -1.0
var _bars := {}
var _args := {}
var _stats := {"points": [0, 0], "aces": 0, "faults": 0, "hits": 0}
var _auto := false
var _t_end := -1.0
var _last_result_e := 0.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=")
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_auto = _args.has("auto")
	surface_key = _args.get("surface", "hard")
	if _args.has("speed"):
		Engine.time_scale = float(_args.speed)
	if _args.has("seconds"):
		_t_end = float(_args.seconds)
	score.sets_to_win = int(_args.get("sets", 2))
	score.games_per_set = int(_args.get("gps", 6))
	_build()
	start_match()

func _build() -> void:
	world = World.new()
	add_child(world)
	world.build(surface_key)
	ball = Ball.new()
	add_child(ball)
	ball.surface = Court.SURFACES[surface_key]
	ball.bounced.connect(_on_ball_bounced)
	ball.net_touched.connect(_on_net_touched)
	ball.went_dead.connect(_on_ball_dead)
	human = Player.new()
	add_child(human)
	human.setup(1, true)
	cpu = Player.new()
	add_child(cpu)
	cpu.setup(-1, false, Color(1.0, 0.72, 0.72))
	players = [human, cpu]
	for p in players:
		p.swing_contact.connect(_on_swing_contact)
		p.serve_contact.connect(_on_serve_contact)
	cam = Camera3D.new()
	cam.fov = 48.0
	cam.position = Vector3(0, 12.0, 28.0)
	add_child(cam)
	cam.look_at(Vector3(0, 0.0, 2.0))
	cam.current = true
	hud = HUD.new()
	add_child(hud)
	hub = InputHub.new()
	add_child(hub)
	hub.swing_onset.connect(_on_hub_swing)
	hub.toss_pressed.connect(_on_hub_toss)
	hub.assist_toggled.connect(_toggle_assist)
	ai_cpu = AIController.new()
	add_child(ai_cpu)
	ai_cpu.setup(self, cpu, difficulty)
	ai_human = AIController.new()
	add_child(ai_human)
	ai_human.setup(self, human, 0.55)
	ai_human.auto_swing = _auto               # en modo normal sólo corre; el golpe lo das tú
	ai_human.assist = not _auto
	auto_move = not _args.has("manual")
	ai_human.enabled = _auto or auto_move
	_make_cross()
	for p in players:
		_make_bar(p)

# ----------------------------------------------------------------------------------------
# Elementos 3D de ayuda: cruz de apuntado y barras de cansancio
# ----------------------------------------------------------------------------------------
func _make_cross() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 64:
		for t in range(-4, 5):
			for pt in [Vector2i(i, clampi(i + t, 0, 63)), Vector2i(i, clampi(63 - i + t, 0, 63))]:
				img.set_pixelv(pt, Color(1.0, 0.92, 0.1, 1.0))
	cross = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.15, 1.15)
	cross.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	cross.material_override = m
	cross.rotation_degrees.x = -90
	cross.visible = false
	cross.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cross)

func _make_bar(p: Player) -> void:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	var bg := Sprite3D.new()
	bg.texture = tex
	bg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bg.pixel_size = 0.01
	bg.modulate = Color(0.05, 0.05, 0.05, 0.85)
	bg.scale = Vector3(36, 3.2, 1)
	bg.no_depth_test = true
	add_child(bg)
	var fill := Sprite3D.new()
	fill.texture = tex
	fill.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fill.pixel_size = 0.01
	fill.scale = Vector3(34, 2.2, 1)
	fill.no_depth_test = true
	fill.render_priority = 1
	add_child(fill)
	_bars[p] = [bg, fill]

func _update_bars() -> void:
	for p in players:
		var bars: Array = _bars[p]
		var pos := p.global_position + Vector3(0, 2.15, 0)
		bars[0].global_position = pos
		bars[1].global_position = pos + Vector3(0, 0.0, 0.0)
		var s := clampf(p.stamina, 0.0, 1.0)
		var fill := bars[1] as Sprite3D
		fill.scale = Vector3(34.0 * maxf(s, 0.01), 2.2, 1)
		fill.offset = Vector2(-(1.0 - s) * 1.0 / maxf(s, 0.01), 0.0)   # alinear a la izquierda
		fill.modulate = Color(0.2, 0.95, 0.25).lerp(Color(0.95, 0.15, 0.1), 1.0 - s)

# ----------------------------------------------------------------------------------------
# Flujo del partido
# ----------------------------------------------------------------------------------------
func start_match() -> void:
	score.reset(int(_args.get("first_server", 0)))
	_stats = {"points": [0, 0], "aces": 0, "faults": 0, "hits": 0}
	start_point()

func server_player() -> Player:
	return players[score.server]

func start_point() -> void:
	state = S.SERVE_READY
	ball.hide_ball()
	ball.is_serve = false
	let_pending = false
	serving = null
	_toss_pending = -1.0
	var sv := server_player()
	var rc: Player = players[1 - score.server]
	x_sign = sv.side * (1 if score.serve_right() else -1)
	for p in players:
		p.state = "idle"
		p.serve_phase = "none"
		p.vel = Vector3.ZERO
		p.move_dir = Vector2.ZERO
		p.stamina = minf(1.0, p.stamina + 0.22)
		p._cur_anim = ""
		p._play("idle", 0.0)
	# El sacador va SIEMPRE detrás de la línea de fondo y en la mitad que toca (derecha en puntos pares,
	# izquierda en impares); la zona legal impide pisar la pista o cruzar la marca central antes de golpear.
	for p in players:
		p.serve_zone = {}
	var xs := float(x_sign)
	sv.global_position = Vector3(xs * 1.3, 0.0, sv.side * (Court.HALF_L + 0.5))
	sv.serve_zone = {"xmin": minf(xs * 0.25, xs * (Court.NET_HALF_W - 0.1)), "xmax": maxf(xs * 0.25, xs * (Court.NET_HALF_W - 0.1)), "zb": Court.HALF_L + 0.1}
	rc.global_position = Vector3(-xs * 2.2, 0.0, rc.side * (Court.HALF_L + 1.2))
	if _args.has("debug"):
		print("SAQUE srv=%s lado=%s x=%.1f z=%.2f pts=%s juegos=%s intento=%d" % ["humano" if sv == human else "cpu", "derecha" if score.serve_right() else "izquierda", sv.global_position.x, sv.global_position.z, score.points, score.games, serve_attempt])
	_refresh_hud()
	var lado := "derecha" if score.serve_right() else "izquierda"
	if sv == human and not _auto:
		hud.flash("Tu saque desde la %s · 1/2 o ESPACIO para lanzar" % lado, Color(1, 1, 1), 2.8)
	elif not _auto:
		hud.flash("Saca la CPU (desde su %s)" % lado, Color(1, 1, 1), 1.6)
	ai_cpu.plan = {}
	if ai_human:
		ai_human.plan = {}
	_retoss_t = -1.0
	if sv == cpu:
		ai_cpu.start_serve()
	elif _auto:
		ai_human.start_serve()

func _refresh_hud() -> void:
	hud.update_score(score, ["TÚ", "CPU"], score.server)
	var wii_txt := "Wii: " + ("CONECTADO" if hub.wii.is_active() else "esperando mando (UDP %d)" % int(hub.wii.cfg.port))
	hud.status_lbl.text = "%s\n%s · dificultad %.1f\nMovimiento: %s (M / botón +)" % [wii_txt, Court.SURFACES[surface_key].name, difficulty, "AUTOMÁTICO" if auto_move else "MANUAL (flechas)"]

func _end_point(winner: Player, text: String) -> void:
	if state == S.POINT_OVER or state == S.MATCH_OVER:
		return
	state = S.POINT_OVER
	var wi := players.find(winner)
	_stats.points[wi] += 1
	if _auto:
		print("  rally: %d golpes" % (_stats.hits - _hits_at_point_start))
	_hits_at_point_start = _stats.hits
	var ev := score.point_won(wi)
	hud.flash(text, Color(0.4, 1.0, 0.5) if wi == 0 else Color(1.0, 0.5, 0.4), 2.2)
	if ev.match:
		hud.flash("%s GANA EL PARTIDO · R para reiniciar" % ("TÚ" if wi == 0 else "LA CPU"), Color(1, 0.9, 0.2), 99.0)
		state = S.MATCH_OVER
	_refresh_hud()
	cross.visible = false
	hud.set_timing(false, 0.0)
	_timer = 2.4
	if _auto:
		print("PUNTO -> %s (%s) | juegos %s sets %s pts %s" % ["humano" if wi == 0 else "cpu", text, score.games, score.sets, score.points])

func _serve_fault(server: Player, text: String) -> void:
	_stats.faults += 1
	if serve_attempt == 1:
		serve_attempt = 2
		hud.flash(text, Color(1, 0.8, 0.2), 1.6)
		state = S.POINT_OVER
		_timer = 1.6
		_second_serve = true
	else:
		serve_attempt = 1
		_end_point(players[1 - players.find(server)], "DOBLE FALTA")

var _second_serve := false
var _hits_at_point_start := 0
var _shot_done := false

func _process(delta: float) -> void:
	_update_bars()
	_update_camera(delta)
	_update_aim_and_timing()
	if Input.is_physical_key_pressed(KEY_R) and state == S.MATCH_OVER:
		serve_attempt = 1
		hud.flash("", Color.WHITE, 0.0)
		start_match()

func _physics_process(delta: float) -> void:
	game_time += delta
	if _args.has("shot") and game_time >= float(_args.get("shot_t", 4.0)) and not _shot_done:
		_shot_done = true
		get_viewport().get_texture().get_image().save_png(String(_args.shot))
		print("captura guardada")
	if _t_end > 0.0 and game_time >= _t_end:
		print("FIN prueba. marcador juegos=%s sets=%s stats=%s" % [score.games, score.sets, _stats])
		get_tree().quit()
		return
	if not ai_human.enabled:
		human.move_dir = Vector2(hub.move.x, -hub.move.y)
	# si la pelota lanzada cae sin que la golpees, no se queda botando: vuelves a tenerla
	if state == S.SERVE_TOSS and ball.active and serving != null and serving.serve_phase == "hold" \
			and ball.vel.y < 0.0 and ball.global_position.y < 1.2:
		_retoss()
	if _toss_pending > 0.0:
		_toss_pending -= delta
		if _toss_pending <= 0.0:
			_release_toss()
	if (state == S.POINT_OVER or state == S.MATCH_OVER) and _timer > 0.0:
		_timer -= delta
		if _timer <= 0.0 and state == S.POINT_OVER:
			if _second_serve:
				_second_serve = false
				start_point()
			else:
				serve_attempt = 1
				start_point()
	# la IA CPU reacciona cuando la pelota cambia
	if state == S.RALLY and ball.active and ball.last_hitter == human and ai_cpu.plan.is_empty() and _need_replan_cpu:
		_need_replan_cpu = false
		ai_cpu.on_ball_changed()

var _need_replan_cpu := false

func _update_camera(delta: float) -> void:
	var target := Vector3(human.global_position.x * 0.35, 12.0, 28.0)
	cam.position = cam.position.lerp(target, clampf(delta * 3.0, 0.0, 1.0))
	cam.look_at(Vector3(human.global_position.x * 0.2, 0.0, 2.0))

# ----------------------------------------------------------------------------------------
# Cruz de apuntado y barra de timing (sólo humano)
# ----------------------------------------------------------------------------------------
func _ideal_time(pl: Player, pred: Array) -> float:
	## Segundos (desde ahora) hasta el instante ideal de contacto: pelota ya botada, bajando a la altura
	## de contacto del golpe. -1 si no se puede devolver.
	var base := ball.bounce_count
	if base >= 2 or pred.is_empty():
		return -1.0
	var ref_p := Vector3.ZERO
	var have := false
	for s in pred:
		if base + int(s.b) >= 1 and s.p.y <= 1.0 and pl.side * s.p.z > 0.2:
			ref_p = s.p
			have = true
			break
	if not have:
		return -1.0
	var kind := "drive" if (ref_p - pl.global_position).dot(pl.right_vec()) >= 0.0 else "reves"
	var h_ref: float = Player.CONTACT_HEAD[kind].y * Player.SCALE
	var apex_t := -1.0
	var apex_y := -1.0
	for s in pred:
		if base + int(s.b) < 1:
			continue
		if base + int(s.b) > 1 or pl.side * s.p.z < 0.2:
			break
		if s.v.y <= 0.3 and s.p.y <= h_ref + 0.02:
			return float(s.t)
		if s.p.y > apex_y and s.p.y <= h_ref + 0.3:
			apex_y = s.p.y
			apex_t = float(s.t)
	return apex_t

func _serve_ideal_time(pred: Array) -> float:
	for s in pred:
		if s.v.y < 0.0 and s.p.y <= Player.SERVE_HEAD.y:
			return float(s.t)
	return -1.0

func _update_aim_and_timing() -> void:
	if _auto and not _args.has("showaim"):
		return
	var serve_mode := (state == S.SERVE_READY or state == S.SERVE_TOSS) and server_player() == human
	var incoming := state == S.RALLY and ball.active and ball.last_hitter == cpu and human.state == "idle"
	var pred: Array = []
	var land := Vector3.ZERO
	var land_ok := false
	if incoming:
		pred = BallPhysics.predict(ball.global_position, ball.vel, ball.omega, ball.surface, 3.0, 1.0 / 60.0)
		if ball.bounce_count == 0:
			for s in pred:
				if int(s.b) >= 1:
					land = s.p
					land_ok = human.side * land.z > 0.0
					break
	# X amarilla = dónde va a botar la pelota que viene, en TU campo
	cross.visible = land_ok
	cross.position = Vector3(land.x, 0.03, land.z)
	# barra de timing: sólo la zona final + cursor lento
	var sp := cam.unproject_position(human.global_position + Vector3(0.0, 2.6, 0.0)) + Vector2(-170, -30)
	if serve_mode and state == S.SERVE_TOSS and ball.active and human.serve_phase == "hold":
		var sp_pred := BallPhysics.predict(ball.global_position, ball.vel, ball.omega, ball.surface, 2.0, 1.0 / 60.0)
		var th := _serve_ideal_time(sp_pred)
		if th >= 0.0:
			var e := Player.SERVE_SWING_T - th
			hud.set_timing(e > -1.6 and e < 0.3, e, sp)
		else:
			hud.set_timing(false, 0.0)
	elif incoming:
		var ti := _ideal_time(human, pred)
		if ti >= 0.0:
			var e2 := human.contact_delay() - ti
			hud.set_timing(e2 > -1.6 and e2 < 0.3, e2, sp)
		else:
			hud.set_timing(false, 0.0)
	else:
		hud.set_timing(false, 0.0)

# ----------------------------------------------------------------------------------------
# Predicción de contacto
# ----------------------------------------------------------------------------------------
func _sample(pred: Array, t: float) -> Dictionary:
	var n := pred.size()
	if n == 0:
		return {"p": Vector3.ZERO, "v": Vector3.ZERO, "b": 0, "dead": true}
	if t >= float(pred[n - 1].t):
		var last: Dictionary = pred[n - 1]
		return {"p": last.p, "v": last.v, "b": last.b, "dead": t > float(last.t) + 0.03}
	for i in range(1, n):
		if float(pred[i].t) >= t:
			var a: Dictionary = pred[i - 1]
			var b: Dictionary = pred[i]
			var f := (t - float(a.t)) / maxf(float(b.t) - float(a.t), 1e-6)
			return {"p": (a.p as Vector3).lerp(b.p, f), "v": (a.v as Vector3).lerp(b.v, f), "b": a.b, "dead": false}
	return {"p": pred[0].p, "v": pred[0].v, "b": pred[0].b, "dead": false}

func probe_contact(pl: Player) -> Dictionary:
	var tc := pl.contact_delay()
	var pred := BallPhysics.predict(ball.global_position, ball.vel, ball.omega, ball.surface, tc + 0.05, 1.0 / 90.0)
	var st := _sample(pred, tc)
	var Pc: Vector3 = st.p
	var Vc: Vector3 = st.v
	var rel := Pc - pl.global_position
	var kind := "drive" if rel.dot(pl.right_vec()) >= 0.0 else "reves"
	var h_ref: float = Player.CONTACT_HEAD[kind].y * Player.SCALE
	var dh := Pc.y - h_ref
	var vy := Vc.y if absf(Vc.y) > 0.6 else (0.6 if Vc.y >= 0.0 else -0.6)
	var rf := pl.reach_for(kind, Pc)
	var valid_side: bool = ball.active and ball.last_hitter != pl and pl.side * Pc.z > 0.2 and ball.bounce_count < 2
	if ball.is_serve and ball.bounce_count + int(st.b) < 1:
		valid_side = false                    # un saque no puede devolverse antes de botar
	var ok: bool = valid_side and not st.dead and Pc.y > 0.12 and Pc.y < 1.75 and float(rf.dist) <= Player.LUNGE_MAX
	return {"valid_side": valid_side, "ok": ok, "kind": kind, "Pc": Pc, "Vc": Vc, "dh": dh, "e": dh / vy, "dist": rf.dist}

func probe_serve(pl: Player) -> Dictionary:
	var tc := Player.SERVE_SWING_T
	var pred := BallPhysics.predict(ball.global_position, ball.vel, ball.omega, ball.surface, tc + 0.05, 1.0 / 90.0)
	var st := _sample(pred, tc)
	var Pc: Vector3 = st.p
	var Vc: Vector3 = st.v
	var dh := Pc.y - Player.SERVE_HEAD.y
	var vy := Vc.y if absf(Vc.y) > 0.6 else (0.6 if Vc.y >= 0.0 else -0.6)
	var rf := pl.reach_for_serve(Pc)
	var ok: bool = ball.active and not st.dead and absf(dh) < 0.6 and float(rf.dist) <= 0.9
	return {"ok": ok, "Pc": Pc, "dh": dh, "e": dh / vy, "dist": rf.dist}

func _quality(dh: float, dist: float, lunge: float, pl: Player, ball_speed: float, tol: float) -> float:
	var q_time := 1.0 - smoothstep(0.18, tol + 0.1, absf(dh))
	var q_reach := 1.0 - 0.55 * pow(clampf(dist / lunge, 0.0, 1.0), 2.0)
	var q_stam := 0.75 + 0.25 * clampf(pl.stamina / 0.6, 0.0, 1.0)
	var q_speed := 1.0 - clampf((ball_speed - 22.0) / 50.0, 0.0, 0.35)
	return clampf(q_time * q_reach * q_stam * q_speed, 0.02, 1.0)

# ----------------------------------------------------------------------------------------
# Golpes
# ----------------------------------------------------------------------------------------
func _on_hub_toss() -> void:
	if state == S.SERVE_READY and server_player() == human and not _auto:
		do_toss(human)

func _on_hub_swing(hctx: Dictionary) -> void:
	if _args.has("debug"):
		print("GESTO fuente=%s potencia=%.2f a=%s b=%s sube=%.2f aim=(%.2f,%.2f) estado=%d" % [hctx.source, float(hctx.power), hctx.a, hctx.b, float(hctx.upward), float(hctx.aim_x), float(hctx.aim_y), state])
	if _auto:
		return
	match state:
		S.SERVE_READY:
			if server_player() == human and hctx.source == "wii":
				_check_toss_gesture(hctx)          # levantar el mando = lanzar la pelota
		S.SERVE_TOSS:
			if serving == human and human.serve_phase == "hold":
				request_serve_swing(human, {"hub": hctx})
		S.RALLY:
			request_swing(human, {"hub": hctx})

func _toggle_assist() -> void:
	if _auto:
		return
	auto_move = not auto_move
	ai_human.enabled = auto_move
	human.move_dir = Vector2.ZERO
	_refresh_hud()
	hud.flash("Movimiento %s" % ("AUTOMÁTICO" if auto_move else "MANUAL (flechas / WASD)"), Color(0.8, 0.9, 1.0), 1.4)

## Lanzamiento fallido (no golpeaste o fallaste el swing): sin falta, se recupera la pelota y se repite.
func _retoss() -> void:
	var pl := serving
	ball.hide_ball()
	serving = null
	state = S.SERVE_READY
	_toss_pending = -1.0
	if pl == null:
		return
	if pl.serve_phase == "hold":
		pl.end_serve()
	if _args.has("debug"):
		print("RETOSS %s" % ("humano" if pl == human else "cpu"))
	if pl == human and not _auto:
		hud.flash("Sin golpe: vuelve a lanzar", Color(1, 0.9, 0.4), 1.6)
	else:
		(ai_cpu if pl == cpu else ai_human).start_serve()

func _check_toss_gesture(hctx: Dictionary) -> void:
	await get_tree().create_timer(0.07).timeout
	if state == S.SERVE_READY and server_player() == human \
			and float(hctx.upward) >= float(hub.wii.cfg.toss_up_ratio):
		do_toss(human)

func do_toss(pl: Player) -> void:
	if state != S.SERVE_READY or pl.state != "idle":
		return
	state = S.SERVE_TOSS
	serving = pl
	pl.begin_serve_raise()
	_toss_pending = 0.30

func _release_toss() -> void:
	var p := serving.hand_world(true)
	p.y = maxf(p.y, 1.1)
	var vy := sqrt(2.0 * BallPhysics.G * maxf(TOSS_APEX - p.y, 0.3))
	ball.surface = Court.SURFACES[surface_key]
	ball.launch(p, Vector3(0, vy, 0), Vector3.ZERO, null)
	ball.is_serve = true

func request_serve_swing(pl: Player, ctx: Dictionary) -> bool:
	if state != S.SERVE_TOSS or pl.serve_phase != "hold" or not ball.active:
		return false
	var pv := probe_serve(pl)
	ctx["can_hit"] = pv.ok
	ctx["quality"] = _quality(pv.dh, pv.dist, 1.8, pl, 0.0, 0.6)
	ctx["q_time"] = 1.0 - smoothstep(0.18, 0.7, absf(pv.dh))
	ctx["e_time"] = pv.e
	ctx["serve"] = true
	pl.begin_serve_swing(pv.Pc, pv.ok, ctx)
	if pl == human and not _auto:
		hud.freeze_timing(clampf(pv.e, -0.45, 0.25))
	return true

func request_swing(pl: Player, ctx: Dictionary) -> bool:
	if pl.state != "idle" or state != S.RALLY:
		return false
	var pr := probe_contact(pl)
	ctx["can_hit"] = pr.ok
	ctx["kind"] = pr.kind
	ctx["e_time"] = pr.e
	ctx["quality"] = _quality(pr.dh, pr.dist, Player.LUNGE_MAX, pl, (pr.Vc as Vector3).length(), 0.5)
	ctx["q_time"] = 1.0 - smoothstep(0.18, 0.6, absf(pr.dh))
	ctx["contact_p"] = pr.Pc
	pl.begin_swing(pr.kind, pr.Pc, pr.ok, ctx)
	if pl == human and not _auto:
		hud.freeze_timing(clampf(pr.e, -0.45, 0.25))
		cross.visible = false
	return true

func _finalize_ctx(pl: Player, ctx: Dictionary, serve: bool) -> void:
	if ctx.has("hub"):
		var h: Dictionary = ctx.hub
		ctx["power"] = float(h.power)
		if serve:
			ctx["shot"] = Shots.serve_from_buttons(bool(h.a), bool(h.b))
		else:
			ctx["shot"] = Shots.from_buttons(bool(h.a), bool(h.b), float(h.upward))

func _on_swing_contact(pl: Player, ctx: Dictionary) -> void:
	_finalize_ctx(pl, ctx, false)
	if not ctx.can_hit or not ball.active or ball.last_hitter == pl:
		if pl == human:
			hud.flash("FALLO", Color(1, 0.4, 0.3), 0.8)
		return
	if ball.global_position.distance_to(ctx.contact_p) > 0.9:
		if pl == human:
			hud.flash("FALLO", Color(1, 0.4, 0.3), 0.8)
		return
	_execute_hit(pl, ctx)

func _on_serve_contact(pl: Player, ctx: Dictionary) -> void:
	_finalize_ctx(pl, ctx, true)
	if _args.has("debug"):
		print("  contacto saque: pies z=%.2f (línea de fondo %.2f) x=%.2f" % [pl.global_position.z, pl.side * Court.HALF_L, pl.global_position.x])
	if not ctx.can_hit or not ball.active:
		_retoss()                                 # sin falta: recuperas la pelota y repites
		return
	_execute_hit(pl, ctx)

## Cuánto "cruza" el golpe (0 = recto/paralelo, 1 = totalmente cruzado), según el gesto del mando.
func _cross_amount(ctx: Dictionary) -> float:
	var h: Dictionary = ctx.get("hub", {})
	if h.has("cross_c"):
		return float(h.cross_c)
	if h.has("yaw_sweep"):
		# derecha: el barrido natural es derecha->izquierda (yaw +); revés: izquierda->derecha (yaw -)
		var dirsign := -1.0 if ctx.get("kind", "drive") == "reves" else 1.0
		var cfg: Dictionary = hub.wii.cfg
		return clampf((float(h.yaw_sweep) * dirsign - float(cfg.cross_min_deg)) / (float(cfg.cross_max_deg) - float(cfg.cross_min_deg)), 0.0, 1.0)
	return 0.5

## Objetivo del humano a partir del GESTO y de la calidad del timing (no hay cruz de apuntado).
func _human_target(pl: Player, ctx: Dictionary, shot_name: String, qt: float) -> Array:
	var c := _cross_amount(ctx)
	var inv: bool = bool(hub.wii.cfg.invert_lateral) != invert_lat
	var width_k := lerpf(0.45, 1.0, pow(qt, 0.7))      # mal timing -> más al centro; bueno -> ajustado a la línea
	var power_g := float(ctx.power)
	if shot_name.begins_with("serve"):
		var xs := -float(x_sign)                        # el cuadro de saque es el diagonal opuesto
		var edge := lerpf(0.7, Court.HALF_W - 0.55, (1.0 - c) if inv else c)   # barrido grande = abierto, pequeño = a la T
		var x := lerpf(xs * 2.2, xs * edge, width_k)
		var z := -float(pl.side) * lerpf(4.4, Court.SERVICE_Z - 0.5, qt)
		return [Vector3(x, 0.0, z), c, 0.0]
	var cp: Vector3 = ctx.get("contact_p", pl.global_position)
	var hs := signf(cp.x) if absf(cp.x) > 1.0 else signf(pl.right_vec().x) * (1.0 if ctx.get("kind", "drive") == "drive" else -1.0)
	if hs == 0.0:
		hs = 1.0
	var lat := 1.0 - 2.0 * c                            # +1 recto (paralelo, mismo lado), -1 cruzado
	if inv:
		lat = -lat
	var x2 := hs * lat * 3.45 * width_k
	var depth := clampf(0.30 + 0.70 * (0.55 * power_g + 0.45 * qt), 0.0, 1.0)
	var z2 := -float(pl.side) * lerpf(5.5, Court.HALF_L - 0.9, depth)
	return [Vector3(x2, 0.0, z2), c, lat]

func _execute_hit(pl: Player, ctx: Dictionary) -> void:
	var shot_name: String = ctx.shot
	var shot: Dictionary = Shots.TYPES[shot_name]
	var is_serve := shot_name.begins_with("serve")
	var q: float = ctx.quality
	var qt: float = float(ctx.get("q_time", q))
	var power := clampf(float(ctx.power) * (0.82 + 0.18 * clampf(pl.stamina / 0.6, 0.0, 1.0)), 0.06, 1.0)
	var p0 := ball.global_position
	var tgt: Vector3
	var dir_label := ""
	if ctx.has("aim"):
		tgt = ctx.aim                                   # CPU
	else:
		var ht := _human_target(pl, ctx, shot_name, qt)  # humano: gesto + timing
		tgt = ht[0]
		power = clampf(power * lerpf(0.7, 1.0, qt), 0.06, 1.0)   # mal timing = menos fuerza
		var lat: float = ht[2]
		dir_label = "al centro" if absf(lat) < 0.3 and not is_serve else ("paralelo" if lat > 0.0 else "cruzado")
		if is_serve:
			dir_label = "abierto" if float(ht[1]) > 0.55 else ("a la T" if float(ht[1]) < 0.35 else "centro")
	if shot_name == "lob":
		tgt.z = -float(pl.side) * (Court.HALF_L - 1.4)
	elif shot_name == "drop":
		tgt.z = -float(pl.side) * randf_range(2.4, 3.4)
	# El error crece con la potencia (riesgo/recompensa) y baja con la calidad del golpe
	var risk := (0.6 + 0.4 * power) if is_serve else (0.7 + 0.6 * power)
	var kind_sign := 1.0
	if not is_serve and ctx.get("kind", "drive") == "reves":
		kind_sign = -1.0
	var bias := 0.0
	if not is_serve:
		# tarde -> la bola se va hacia la derecha del jugador en derecha (izquierda en revés); pronto, al contrario
		bias = clampf(float(ctx.e_time) * 5.0, -2.0, 2.0) * kind_sign * pl.right_vec().x
	var sx := lerpf(1.2, 0.08, q) if is_serve else lerpf(1.8, 0.08, q)
	var sz := lerpf(1.5, 0.10, q) if is_serve else lerpf(2.6, 0.15, q)
	tgt.x += randfn(0.0, sx * risk) + bias
	tgt.z += randfn(0.0, sz * risk)
	var side_spin := 0.0
	if shot_name == "serve_slice":
		side_spin = 70.0 * float(x_sign)
	var pl_plan := BallPhysics.plan(p0, tgt, shot, power, side_spin)
	var v: Vector3 = pl_plan.v
	var err_k := 0.5 if is_serve else 1.0
	var el_err := randfn(0.0, (1.0 - q) * deg_to_rad(3.0) * err_k)
	var az_err := randfn(0.0, (1.0 - q) * deg_to_rad(2.0) * err_k)
	var hv := Vector3(v.x, 0.0, v.z)
	var ang := atan2(v.y, hv.length()) + el_err
	var hd := hv.normalized().rotated(Vector3.UP, az_err)
	v = (hd * cos(ang) + Vector3.UP * sin(ang)) * v.length()
	if _args.has("debug"):
		print("HIT %s %-12s q=%.2f qt=%.2f pw=%.2f e=%.3f plan_ok=%s v=%.0f km/h clear=%.2f %s tgt=(%.1f,%.1f)" % [("H" if pl == human else "C"), shot_name, q, qt, power, float(ctx.get("e_time", 0.0)), pl_plan.ok, v.length() * 3.6, float(pl_plan.clear), dir_label, tgt.x, tgt.z])
	ball.launch(p0, v, pl_plan.w, pl)
	ball.is_serve = is_serve
	if is_serve:
		pl.serve_zone = {}
	let_pending = false
	pl.stamina -= float(shot.stamina) * (0.6 + 0.8 * power)
	_stats.hits += 1
	state = S.RALLY
	# el que acaba de golpear deja de perseguir: vuelve a su posición
	if pl == human:
		ai_human.plan = {}
	else:
		ai_cpu.plan = {}
	if pl == human:
		_need_replan_cpu = true
		var kmh := v.length() * 3.6
		hud.set_shot_info("%s · %d km/h%s" % [shot.label, int(kmh), (" · " + dir_label) if dir_label != "" else ""])
		var e: float = ctx.e_time
		var txt := "PERFECTO" if qt > 0.85 else ("BIEN" if qt > 0.55 else ("TARDE" if e > 0 else "PRONTO"))
		hud.flash(txt, Color(0.3, 1, 0.4) if qt > 0.85 else (Color(1, 1, 0.3) if qt > 0.55 else Color(1, 0.55, 0.2)), 0.7)
		ai_cpu.on_ball_changed()
	else:
		hud.set_shot_info("CPU: %s · %d km/h" % [shot.label, int(v.length() * 3.6)])
		ai_human.on_ball_changed()

# ----------------------------------------------------------------------------------------
# Eventos de la pelota
# ----------------------------------------------------------------------------------------
func _on_net_touched(tape: bool) -> void:
	if ball.is_serve and tape:
		let_pending = true

func _on_ball_bounced(p: Vector3, count: int) -> void:
	world.add_mark(p)
	if state != S.RALLY:
		return
	var hitter := ball.last_hitter as Player
	if hitter == null:
		return
	var opp: Player = players[1 - players.find(hitter)]
	# el rebote tras recuperarse de la ia: recalcular plan de quien debe devolver
	if count == 1:
		var ball_side := 1 if p.z > 0.0 else -1
		if ball.is_serve:
			if ball_side == hitter.side or not Court.in_service_box(p, hitter.side, x_sign):
				_serve_fault(hitter, "FALTA" if not ball.net_hit else "RED")
				return
			if let_pending:
				hud.flash("LET", Color(1, 1, 0.4), 1.4)
				state = S.POINT_OVER
				_second_serve = true
				_timer = 1.4
				return
		else:
			if ball_side == hitter.side:
				_end_point(opp, "RED" if ball.net_hit else "CORTA")
				return
			if not Court.in_singles(p):
				_end_point(opp, "FUERA")
				return
		var receiver: Player = opp
		if receiver == cpu:
			ai_cpu.on_ball_changed()
		elif ai_human:
			ai_human.on_ball_changed()
	elif count >= 2:
		if ball.is_serve:
			_stats.aces += 1
			_end_point(hitter, "¡ACE!")
		else:
			_end_point(hitter, "PUNTO")

func _on_ball_dead() -> void:
	if state != S.RALLY:
		return
	var hitter := ball.last_hitter as Player
	if hitter == null:
		return
	if ball.bounce_count == 0:
		_end_point(players[1 - players.find(hitter)], "FUERA")
	else:
		_end_point(hitter, "PUNTO")

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_M:
				_toggle_assist()
			KEY_V:
				invert_lat = not invert_lat
				hud.flash("Recto/cruzado %s" % ("INVERTIDO" if invert_lat else "normal"), Color(0.8, 0.9, 1.0), 1.4)
			KEY_C:
				if state == S.SERVE_READY:
					surface_key = "clay" if surface_key == "hard" else "hard"
					world.set_surface(surface_key)
					ball.surface = Court.SURFACES[surface_key]
					_refresh_hud()
			KEY_F1, KEY_F2, KEY_F3:
				difficulty = {KEY_F1: 0.3, KEY_F2: 0.6, KEY_F3: 0.95}[event.physical_keycode]
				ai_cpu.difficulty = difficulty
				_refresh_hud()
