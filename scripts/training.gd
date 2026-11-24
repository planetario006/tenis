class_name Training
extends Node
## Entrenamiento de golpes: una "máquina" (la CPU) lanza bolas a tu derecha (drive) o a tu izquierda (revés) y tú
## respondes con el mando. De cada golpe se guarda el pico de fuerza, la dirección del gesto y el momento.
##
## 4 bloques de 5 bolas:  DRIVE → derecha · DRIVE → izquierda · REVÉS → derecha · REVÉS → izquierda
## En cada bloque se pide una intensidad distinta (SUAVE, MEDIA, MEDIA, FUERTE, FUERTE): con eso se calibra
##   · el rango de fuerza (de tu swing más suave al más fuerte),
##   · el umbral de detección (por debajo de tu swing suave no es un golpe),
##   · tu "centro" y tu "rango" de dirección para drive y para revés por separado.
## El perfil se guarda en user://wii_profile.json y el partido lo usa automáticamente.

const BLOCKS := [
	{"kind": "drive", "dir": 1.0},
	{"kind": "drive", "dir": -1.0},
	{"kind": "reves", "dir": 1.0},
	{"kind": "reves", "dir": -1.0},
]
const INTENSITY := ["SUAVE", "MEDIA", "MEDIA", "FUERTE", "FUERTE"]
const PER_BLOCK := 5
const MAX_TRIES := 10

var game
var active := false
var samples: Array = []
var _block := 0
var _ball := 0                 # golpes válidos hechos en el bloque
var _tries := 0
var _phase := "idle"
var _t := 0.0
var _flight_t := 0.0
var _hit := false
var _missed := false
var _result := ""
var _cued := false
var _summary := ""

func setup(g) -> void:
	game = g

func start() -> void:
	active = true
	samples = []
	_block = 0
	_ball = 0
	_tries = 0
	_phase = "intro"
	_t = 4.0
	game.ball.hide_ball()
	_prep_human()
	_show_intro()

func stop() -> void:
	active = false
	_phase = "idle"
	if game and game.hud:
		game.hud.set_train("")
		game.hud.set_debug("")

func _name_of(b: Dictionary) -> String:
	return "%s hacia la %s" % ["DRIVE" if b.kind == "drive" else "REVÉS", "DERECHA" if float(b.dir) > 0.0 else "IZQUIERDA"]

func _show_intro() -> void:
	var b: Dictionary = BLOCKS[_block]
	game.hud.flash("BLOQUE %d/%d" % [_block + 1, BLOCKS.size()], Color(1, 0.9, 0.3), 3.5)
	game.hud.set_train("%s\n%d bolas · intensidades: %s\nGolpea sin botones (topspin) y apunta el mando hacia ese lado" % [_name_of(b), PER_BLOCK, " · ".join(INTENSITY)])

func _prompt() -> String:
	var b: Dictionary = BLOCKS[_block]
	var i := mini(_ball, PER_BLOCK - 1)
	return "%s  ·  bola %d/%d  ·  FUERZA %s" % [_name_of(b), i + 1, PER_BLOCK, INTENSITY[i]]

func _prep_human() -> void:
	var h: Player = game.human
	if h.state != "idle":
		return
	h.global_position = Vector3(0.0, 0.0, h.side * (Court.HALF_L + 0.4))
	h.move_dir = Vector2.ZERO
	game.ai_human.plan = {}

func _process(delta: float) -> void:
	if not active:
		return
	_t -= delta
	match _phase:
		"intro":
			if _t <= 0.0:
				_phase = "wait"
				_t = 1.2
		"wait":
			game.hud.set_train(_prompt() + "\n" + _result)
			if game.human.state == "idle":
				_prep_human()
			if _t <= 0.0 and game.human.state == "idle":
				_launch()
		"flight":
			_flight_t += delta
			if game.hud and _flight_t > 0.2:
				game.hud.set_train(_prompt() + "\n" + _result)
			if game._args.has("debug") and not _cued:
				_debug_cue()
			if _hit or _missed:
				_phase = "after"
				_t = 1.7 if _hit else 1.0
			elif _flight_t > 5.5:
				_result = "sin golpe"
				_tries += 1
				_phase = "after"
				_t = 0.4
		"after":
			if game.hud:
				game.hud.set_train(_prompt() + "\n" + _result)
			if _t <= 0.0:
				_advance()
		"block_end":
			if _t <= 0.0:
				_next_block()
		"done":
			pass

func _debug_cue() -> void:
	var pred := BallPhysics.predict(game.ball.global_position, game.ball.vel, game.ball.omega, game.ball.surface, 3.0, 1.0 / 60.0)
	var ti: float = game._ideal_time(game.human, pred)
	if ti >= 0.0 and ti - game.human.contact_delay() <= 0.22:   # el mando tarda ~0,1-0,2 s en confirmar el golpe:
		_cued = true
		print("CUE %s %s %s" % [BLOCKS[_block].kind, "R" if float(BLOCKS[_block].dir) > 0.0 else "L", INTENSITY[mini(_ball, PER_BLOCK - 1)]])

func _launch() -> void:
	var h: Player = game.human
	var cpu: Player = game.cpu
	var b: Dictionary = BLOCKS[_block]
	var sx := signf(h.right_vec().x)
	if sx == 0.0:
		sx = 1.0
	var tx := h.global_position.x + (sx if b.kind == "drive" else -sx) * 1.9
	var p0 := Vector3(cpu.global_position.x * 0.3, 1.1, cpu.global_position.z)
	var tgt := Vector3(tx, 0.0, h.side * 7.0)
	var pl := BallPhysics.plan(p0, tgt, Shots.TYPES["slice"], 0.05)   # bola lenta y bajita, fácil de llegar
	game.ball.surface = Court.SURFACES[game.surface_key]
	game.ball.launch(p0, pl.v, pl.w, cpu)
	game.ball.is_serve = false
	game.state = Game.S.RALLY
	game.ai_human.on_ball_changed()
	_phase = "flight"
	_flight_t = 0.0
	_hit = false
	_missed = false
	_cued = false
	_result = ""

func on_miss() -> void:
	if game._args.has("debug"):
		print("TRAIN miss fase=%s ball=%s" % [_phase, game.ball.global_position])
	if _phase == "flight" and not _hit:
		_missed = true
		_tries += 1
		_result = "FALLO: no llegaste a la bola (prueba a empezar el gesto antes)"

func on_human_hit(ctx: Dictionary, v: Vector3, dir_label: String) -> void:
	if _phase != "flight":
		return
	var h: Dictionary = ctx.hub
	_hit = true
	_tries += 1
	var kind := String(ctx.get("kind", "drive"))
	if bool(h.a) or bool(h.b):
		_result = "Con botón: aquí se golpea SIN botones (topspin). No cuenta."
		return
	var b: Dictionary = BLOCKS[_block]
	samples.append({"kind": kind, "target": float(b.dir), "intensity": INTENSITY[_ball], "peak": float(h.peak_dps),
		"az": float(h.az_rel_deg), "lift": float(h.lift_deg), "e": float(ctx.get("e_time", 0.0))})
	_ball += 1
	var lat := float(game.hub.wii.lateral_for(float(h.az_rel_deg), kind))
	_result = "Pico %.0f °/s · dirección del gesto %+.0f° → %s · %.0f km/h" % [float(h.peak_dps), float(h.az_rel_deg), dir_label, v.length() * 3.6]
	if kind != String(b.kind):
		_result += "\n(la bola se jugó como %s)" % ("DRIVE" if kind == "drive" else "REVÉS")
	game.hud.set_shot_info("")

func on_bounce(p: Vector3, count: int) -> void:
	if count == 1 and game.ball.last_hitter == game.human and _hit:
		_result += "  ·  " + ("DENTRO" if Court.in_singles(p) and p.z * game.human.side < 0.0 else "FUERA")

func on_button(n: String) -> void:
	if _phase == "done" and (n == "A" or n == "ONE" or n == "TWO"):
		game.show_menu()

func _advance() -> void:
	game.ball.hide_ball()
	if _ball >= PER_BLOCK or _tries >= MAX_TRIES:
		_phase = "block_end"
		_t = 1.6
		game.hud.set_train("Bloque %d completado (%d/%d golpes válidos)" % [_block + 1, _ball, PER_BLOCK])
		return
	_phase = "wait"
	_t = 1.0
	_result = ""

func _next_block() -> void:
	_block += 1
	_ball = 0
	_tries = 0
	_result = ""
	if _block >= BLOCKS.size():
		_finish()
		return
	_phase = "intro"
	_t = 3.5
	_prep_human()
	_show_intro()

# ----------------------------------------------------------------------------------------
# Resultados y calibración
# ----------------------------------------------------------------------------------------
static func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())

static func _std(a: Array) -> float:
	if a.size() < 2:
		return 0.0
	var m := _mean(a)
	var s := 0.0
	for v in a:
		s += (float(v) - m) * (float(v) - m)
	return sqrt(s / float(a.size() - 1))

static func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	var n := b.size()
	return float(b[n / 2]) if n % 2 == 1 else 0.5 * (float(b[n / 2 - 1]) + float(b[n / 2]))

func _vals(kind: String, dir: float, key: String, intensity: String = "") -> Array:
	var out := []
	for s in samples:
		if s.kind == kind and (dir == 0.0 or float(s.target) == dir) and (intensity == "" or s.intensity == intensity):
			out.append(float(s[key]))
	return out

## Calcula el perfil a partir de las muestras. Estático en lo posible para poder probarlo.
func compute_profile() -> Dictionary:
	var prof := {}
	var soft := []
	var mid := []
	var strong := []
	for s in samples:
		match s.intensity:
			"SUAVE": soft.append(float(s.peak))
			"MEDIA": mid.append(float(s.peak))
			"FUERTE": strong.append(float(s.peak))
	if soft.size() >= 3 and strong.size() >= 3:
		var lo := _median(soft) * 0.85
		var hi := _median(strong) * 1.05
		hi = maxf(hi, lo + 250.0)
		prof["power_min_dps"] = lo
		prof["power_max_dps"] = hi
		var conf := clampf(_median(soft) * 0.8, 400.0, 800.0)   # por debajo de tu swing más suave no es un golpe
		prof["confirm_dps"] = conf
		prof["arm_dps"] = conf * 0.6
	var lat := {}
	for kind in ["drive", "reves"]:
		var l := _vals(kind, -1.0, "az")
		var r := _vals(kind, 1.0, "az")
		if l.size() >= 2 and r.size() >= 2 and absf(_mean(r) - _mean(l)) >= 8.0:
			lat[kind] = {"c": 0.5 * (_mean(r) + _mean(l)), "h": 0.5 * (_mean(r) - _mean(l)),
				"n": l.size() + r.size(), "std_l": _std(l), "std_r": _std(r)}
	if not lat.is_empty():
		prof["lat"] = lat
	return prof

func _finish() -> void:
	_phase = "done"
	game.ball.hide_ball()
	game.hud.flash("ENTRENAMIENTO COMPLETO", Color(0.4, 1, 0.5), 4.0)
	var prof := compute_profile()
	var t := ""
	for b in BLOCKS:
		var az := _vals(b.kind, float(b.dir), "az")
		var pk := _vals(b.kind, float(b.dir), "peak")
		if az.is_empty():
			t += "%s: sin datos\n" % _name_of(b)
		else:
			t += "%s: %d golpes · pico medio %.0f °/s · dirección %+.0f° (±%.0f°)\n" % [_name_of(b), az.size(), _mean(pk), _mean(az), _std(az)]
	if prof.has("power_min_dps"):
		t += "Fuerza guardada: de %.0f (suave) a %.0f °/s (fuerte)\n" % [float(prof.power_min_dps), float(prof.power_max_dps)]
	else:
		t += "Faltan golpes suaves/fuertes para calibrar la fuerza\n"
	for k in ["drive", "reves"]:
		if prof.has("lat") and prof.lat.has(k):
			t += "%s calibrado: centro %+.0f° · rango ±%.0f°\n" % ["DRIVE" if k == "drive" else "REVÉS", float(prof.lat[k].c), absf(float(prof.lat[k].h))]
		else:
			t += "%s: poco contraste izquierda/derecha, se usa el ajuste general\n" % ("DRIVE" if k == "drive" else "REVÉS")
	var es := []
	for sm in samples:
		es.append(float(sm.e))
	if not es.is_empty():
		var me := _mean(es)
		t += "Timing medio: %s (%.2f s)\n" % ["TARDE" if me > 0.08 else ("PRONTO" if me < -0.08 else "bien ajustado"), me]
	t += "Pulsa A para volver al menú"
	prof["samples"] = samples
	prof["date"] = Time.get_datetime_string_from_system()
	game.hub.wii.save_profile(prof)
	_summary = t
	game.hud.set_train("")
	game.hud.set_menu(t)
	if game._args.has("debug"):
		print("PERFIL ", JSON.stringify(prof.get("lat", {})), " ", prof.get("power_min_dps", -1), " ", prof.get("power_max_dps", -1))
