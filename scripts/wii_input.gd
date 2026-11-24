class_name WiiInput
extends Node
## Recibe por UDP los paquetes JSON del puente Python (wii/wii_bridge.py) y reconoce los gestos.
## Paquete: {"t": seg, "a": [ax,ay,az] (g), "g": [wx,wy,wz] (°/s, ya en ejes del mando y sin sesgo), "b": botones}
##
## Ejes del mando (los fija wii_bridge.py con la calibración automática):
##   X = derecha · Y = hacia donde apunta el morro · Z = hacia arriba (cara de los botones)
##   Giro positivo = regla de la mano derecha (morro arriba = +X, a la izquierda visto desde arriba = +Z).
##
## Qué se obtiene del mando:
##   ORIENTACIÓN -> filtro complementario (Mahony): giroscopio + gravedad del acelerómetro.
##   FUERZA      -> velocidad angular pico del swing, con curva configurable.
##   MOMENTO     -> instante en que arranca el golpe (se confirma al superar `confirm_dps`).
##   DIRECCIÓN   -> hacia dónde apunta el mando cuando lo golpeas, respecto a tu posición de "listo":
##                  izquierda (-1) · centro (0) · derecha (+1).
##   LANZAR      -> levantar el morro del mando por encima de la posición de "listo".
##   TIPO DE GOLPE -> botones: ninguno = topspin, A = plano, B = cortado, A+B = globo (swing que sube) o dejada.

signal swing_onset(ctx: Dictionary)
signal toss_gesture()
signal recentered()
signal button_pressed(name: String)

const BTN := {"A": 1, "B": 2, "ONE": 4, "TWO": 8, "PLUS": 16, "MINUS": 32, "HOME": 64,
	"UP": 128, "DOWN": 256, "LEFT": 512, "RIGHT": 1024}

var cfg := {
	"port": 9876,
	# --- detección del swing ---
	"arm_dps": 260.0,            # a partir de aquí se "arma" un posible golpe (× sensibilidad)
	"confirm_dps": 460.0,        # hay que llegar a esto para confirmar el golpe (× sensibilidad)
	"confirm_hold": 0.02,        # s que debe mantenerse por encima de confirm_dps (descarta golpes secos y sacudidas)
	"rearm_ratio": 0.5,          # tras un golpe, el mando debe bajar de arm_dps × este ratio antes de poder armar otro
	"confirm_window": 0.14,      # s máx. entre armar y confirmar
	"end_ratio": 0.40,           # el swing acaba cuando la velocidad cae por debajo de este ratio del pico
	"swing_max_time": 0.45,
	"swing_cooldown": 0.40,      # s mínimos entre golpes
	# --- fuerza ---
	"power_min_dps": 380.0,      # swing suave -> fuerza mínima
	"power_max_dps": 1500.0,     # swing a tope -> fuerza máxima
	"power_curve": 0.85,         # <1 favorece los swings medios, >1 los endurece
	# --- dirección ---
	"lateral_range_deg": 38.0,   # grados respecto a la posición de listo que equivalen a ir a la esquina
	"lateral_deadzone_deg": 3.0,
	"lateral_gamma": 0.9,
	"invert_lateral": false,     # si en tu mano sale al revés
	"point_axis": [0.0, 1.0, 0.0],   # eje del mando que "apunta" (por defecto, el morro)
	# --- globo / dejada ---
	"lob_lift_deg": 22.0,        # el morro debe subir tantos grados durante el swing para que sea globo
	# --- lanzar la pelota ---
	"toss_rise_deg": 28.0,       # subida del morro sobre la posición de listo
	"toss_rate_dps": 70.0,       # velocidad mínima de esa subida
	"toss_cooldown": 1.2,
	# --- botones ---
	"button_lookback": 0.30,     # un botón pulsado hasta 0,30 s antes del swing cuenta
	# --- fusión ---
	"fusion_kp": 1.6,
	"fusion_acc_tolerance": 0.22,
	"calm_dps": 140.0,
}
var udp := PacketPeerUDP.new()
var listening := false
var last_packet_ms := -100000
var buttons := 0
var acc := Vector3(0, 0, 1)
var gyro := Vector3.ZERO           # °/s en ejes del mando
var q := Quaternion.IDENTITY       # mando -> nivel (X derecha, Y delante, Z arriba)
var elevation_deg := 0.0           # inclinación del morro sobre la horizontal
var azimuth_deg := 0.0             # hacia dónde apunta (+ = derecha)
var ref_azimuth := 0.0             # azimut de "listo" (se adapta mientras estás quieto)
var ref_elevation := 0.0
var speed_dps := 0.0               # |ω| suavizada
var last_gesture: Dictionary = {}  # resumen del último golpe (HUD de depuración)
var packets := 0
var sensitivity := 1               # 0 = baja, 1 = media, 2 = alta
const SENS_NAMES := ["BAJA", "MEDIA", "ALTA"]
const SENS_FACTOR := [1.35, 1.0, 0.75]   # multiplica los umbrales arm/confirm
var lat_profile: Dictionary = {}   # {"drive": {"c": °, "h": °}, "reves": {...}} del entrenamiento
var profile_info := ""             # texto para el menú
var gyro_bias := Vector3.ZERO      # re-cero automático del giroscopio
var _still_t := 0.0
var _hold_t := 0.0
var _rearmed := true

var _clock := 0.0
var _last_t := -1.0
var _state := "idle"               # idle · armed · swing
var _ctx: Dictionary = {}
var _t_arm := 0.0
var _t_onset := 0.0
var _peak := 0.0
var _peak_t := 0.0
var _az_acc := 0.0
var _az_w := 0.0
var _el_start := 0.0
var _last_end := -10.0
var _a_t := -10.0
var _b_t := -10.0
var _sm: Array[float] = []         # últimas velocidades para suavizar
var _toss_last := -10.0
var _toss_hist: Array = []         # [t, elevación]
var _suppress_until := -1.0
var _below_t := 0.0
var _initialized := false

func _ready() -> void:
	for path in ["res://wii/wii_config.json", "user://wii_config.json"]:
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				for k in parsed:
					cfg[k] = parsed[k]
	load_profile()
	start_listening()

func start_listening() -> void:
	var err := udp.bind(int(cfg.port), "0.0.0.0")
	listening = err == OK
	if not listening:
		push_warning("WiiInput: no se pudo abrir UDP %d (%s)" % [int(cfg.port), error_string(err)])

func is_active() -> bool:
	return Time.get_ticks_msec() - last_packet_ms < 700

func btn(name: String) -> bool:
	return (buttons & int(BTN[name])) != 0

func _process(_delta: float) -> void:
	if not listening:
		return
	while udp.get_available_packet_count() > 0:
		var d = JSON.parse_string(udp.get_packet().get_string_from_utf8())
		if d is Dictionary and d.has("g"):
			var a: Array = d.get("a", [0, 0, 1])
			var g: Array = d["g"]
			var t := float(d.get("t", _clock))
			var dt := 0.01 if _last_t < 0.0 or t < _last_t else clampf(t - _last_t, 0.0005, 0.05)
			_last_t = t
			last_packet_ms = Time.get_ticks_msec()
			ingest(Vector3(a[0], a[1], a[2]), Vector3(g[0], g[1], g[2]), int(d.get("b", 0)), dt)

func arm_eff() -> float:
	return float(cfg.arm_dps) * SENS_FACTOR[sensitivity]

func confirm_eff() -> float:
	return float(cfg.confirm_dps) * SENS_FACTOR[sensitivity]

func set_sensitivity(level: int) -> void:
	sensitivity = clampi(level, 0, 2)
	save_profile()

## Re-cero automático: con el mando quieto, el sesgo del giroscopio se actualiza solo.
func _update_bias(raw: Vector3, dt: float) -> void:
	if (raw - gyro_bias).length() < 22.0:
		_still_t += dt
		if _still_t > 0.4:
			gyro_bias = gyro_bias.lerp(raw, clampf(dt * 1.5, 0.0, 1.0))
	else:
		_still_t = 0.0

## Dirección (-1..1) de un golpe: con perfil de entrenamiento usa tu centro y tu rango para ese tipo de golpe.
func lateral_for(rel_deg: float, kind: String) -> float:
	if lat_profile.has(kind):
		var pr: Dictionary = lat_profile[kind]
		var h := float(pr.h)
		var v := clampf((rel_deg - float(pr.c)) / (h if absf(h) > 4.0 else (4.0 if h >= 0.0 else -4.0)), -1.0, 1.0)
		if absf(v) < 0.06:
			v = 0.0
		return -v if bool(cfg.invert_lateral) else v
	return _lateral_from(rel_deg)

func load_profile() -> void:
	var path := "user://wii_profile.json"
	if not FileAccess.file_exists(path):
		profile_info = "sin calibrar (haz el entrenamiento)"
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		return
	for k in ["power_min_dps", "power_max_dps", "arm_dps", "confirm_dps"]:
		if d.has(k):
			cfg[k] = float(d[k])
	if d.has("lat"):
		lat_profile = d.lat
	sensitivity = clampi(int(d.get("sensitivity", sensitivity)), 0, 2)
	profile_info = "calibrado" if not lat_profile.is_empty() else "sin calibrar (haz el entrenamiento)"

## Guarda el perfil personal (resultado del entrenamiento + sensibilidad) en user://wii_profile.json.
func save_profile(extra: Dictionary = {}) -> void:
	var d := {}
	if FileAccess.file_exists("user://wii_profile.json"):
		var old = JSON.parse_string(FileAccess.get_file_as_string("user://wii_profile.json"))
		if old is Dictionary:
			d = old
	for k in extra:
		d[k] = extra[k]
	d["sensitivity"] = sensitivity
	for k in ["power_min_dps", "power_max_dps", "arm_dps", "confirm_dps"]:
		if extra.has(k):
			cfg[k] = float(extra[k])
	if extra.has("lat"):
		lat_profile = extra.lat
		profile_info = "calibrado"
	var f := FileAccess.open("user://wii_profile.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d, "  "))

## Impide detectar golpes durante `seconds` (p. ej. mientras dura el gesto de lanzar la pelota).
func suppress_swings(seconds: float) -> void:
	_suppress_until = maxf(_suppress_until, _clock + seconds)

func recenter() -> void:
	ref_azimuth = azimuth_deg
	ref_elevation = elevation_deg
	recentered.emit()

## Procesa una muestra (también la usan los tests para simular un mando).
func ingest(acc_g: Vector3, gyro_dps: Vector3, btn_mask: int, dt: float) -> void:
	_clock += dt
	acc = acc_g
	_update_bias(gyro_dps, dt)
	gyro = gyro_dps - gyro_bias
	packets += 1
	var pressed := btn_mask & ~buttons
	buttons = btn_mask
	for n in BTN:
		if pressed & int(BTN[n]):
			button_pressed.emit(n)
	if pressed & int(BTN.HOME):
		recenter()
	if buttons & int(BTN.A):
		_a_t = _clock
	if buttons & int(BTN.B):
		_b_t = _clock
	_fuse(dt)
	_sm.append(gyro.length())
	if _sm.size() > 3:
		_sm.pop_front()
	var s := 0.0
	for v in _sm:
		s += v
	speed_dps = s / float(_sm.size())
	if speed_dps < arm_eff() * float(cfg.rearm_ratio):
		_rearmed = true
	_update_reference(dt)
	_detect_toss()
	_detect_swing(dt)

# ----------------------------------------------------------------------------------------
# Orientación (Mahony)
# ----------------------------------------------------------------------------------------
func _fuse(dt: float) -> void:
	var w := gyro * (PI / 180.0)
	var am := acc.length()
	if not _initialized and am > 0.5:
		q = _quat_up(acc / am)                   # arranque: alinear el nivel con la gravedad medida
		_initialized = true
	if am > 0.5 and absf(am - 1.0) < float(cfg.fusion_acc_tolerance):
		var v := q.inverse() * Vector3(0, 0, 1)  # "arriba" estimado, en ejes del mando
		w += (acc / am).cross(v) * float(cfg.fusion_kp)
	var dq := Quaternion(w.x * 0.5 * dt, w.y * 0.5 * dt, w.z * 0.5 * dt, 0.0)
	var qn := q + _qmul(q, dq)                   # q' = q + q ⊗ (0, ω)·dt/2
	q = qn.normalized()
	var p: Vector3 = q * _point_axis()
	elevation_deg = rad_to_deg(asin(clampf(p.z, -1.0, 1.0)))
	var hor := Vector2(p.x, p.y)
	if hor.length() > 0.3:
		azimuth_deg = rad_to_deg(atan2(hor.x, hor.y))

func _point_axis() -> Vector3:
	var a: Array = cfg.point_axis
	return Vector3(a[0], a[1], a[2]).normalized()

static func _qmul(a: Quaternion, b: Quaternion) -> Quaternion:
	return Quaternion(
		a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
		a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
		a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
		a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z)

## Cuaternión mando->nivel (guiñada 0) dada la dirección de "arriba" medida en ejes del mando.
static func _quat_up(up_body: Vector3) -> Quaternion:
	var z := Vector3(0, 0, 1)
	var axis := up_body.cross(z)
	var s := axis.length()
	if s < 1e-6:
		return Quaternion.IDENTITY if up_body.z > 0.0 else Quaternion(1, 0, 0, 0)
	return Quaternion(axis / s, atan2(s, up_body.dot(z)))

static func _wrap(deg: float) -> float:
	return fposmod(deg + 180.0, 360.0) - 180.0

# ----------------------------------------------------------------------------------------
# Posición de "listo": el azimut/elevación de referencia sigue a la mano mientras está quieta
# ----------------------------------------------------------------------------------------
func _update_reference(dt: float) -> void:
	if _state == "idle" and speed_dps < float(cfg.calm_dps):
		var k := clampf(dt * 2.0, 0.0, 1.0)
		ref_azimuth += _wrap(azimuth_deg - ref_azimuth) * k
		ref_elevation = lerpf(ref_elevation, elevation_deg, k)

# ----------------------------------------------------------------------------------------
# Lanzar la pelota: levantar el morro por encima de la posición de listo
# ----------------------------------------------------------------------------------------
func _detect_toss() -> void:
	_toss_hist.append([_clock, elevation_deg])
	while _toss_hist.size() > 0 and _clock - float(_toss_hist[0][0]) > 0.35:
		_toss_hist.pop_front()
	if _clock - _toss_last < float(cfg.toss_cooldown) or _toss_hist.size() < 4:
		return
	var rise := elevation_deg - ref_elevation
	var rate := (elevation_deg - float(_toss_hist[0][1])) / maxf(_clock - float(_toss_hist[0][0]), 0.05)
	if rise >= float(cfg.toss_rise_deg) and rate >= float(cfg.toss_rate_dps):
		_toss_last = _clock
		toss_gesture.emit()

# ----------------------------------------------------------------------------------------
# Golpe
# ----------------------------------------------------------------------------------------
func _detect_swing(dt: float) -> void:
	var gm := speed_dps
	match _state:
		"idle":
			if _clock < _suppress_until or _clock - _last_end < float(cfg.swing_cooldown) or not _rearmed:
				return
			if gm > arm_eff():
				_state = "armed"
				_hold_t = 0.0
				_t_arm = _clock
				_el_start = elevation_deg
				_peak = gm
				_peak_t = _clock
		"armed":
			if _clock < _suppress_until:
				_state = "idle"
				return
			_peak = maxf(_peak, gm)
			if gm >= confirm_eff():
				_hold_t += dt
				if _hold_t >= float(cfg.confirm_hold):
					_confirm()
			else:
				_hold_t = 0.0
			if _state == "armed" and (_clock - _t_arm > float(cfg.confirm_window) or gm < 0.5 * arm_eff()):
				_state = "idle"                 # era sólo un movimiento del brazo, no un golpe
		"swing":
			_track(gm, dt)

func _confirm() -> void:
	_state = "swing"
	_t_onset = _t_arm
	_az_acc = 0.0
	_az_w = 0.0
	_below_t = 0.0
	_peak_t = _clock
	var lb := float(cfg.button_lookback)
	_ctx = {"source": "wii", "t_onset": _t_onset, "power": _power_from(_peak), "peak_dps": _peak,
		"lateral": 0.0, "upward": 0.0, "lift_deg": 0.0,
		"a": _clock - _a_t < lb, "b": _clock - _b_t < lb, "finalized": false}
	_accumulate_direction(speed_dps)
	_refresh_ctx()
	swing_onset.emit(_ctx)

func _track(gm: float, dt: float) -> void:
	if gm > _peak:
		_peak = gm
		_peak_t = _clock
	_accumulate_direction(gm)
	if buttons & int(BTN.A):
		_ctx.a = true
	if buttons & int(BTN.B):
		_ctx.b = true
	_refresh_ctx()
	if gm < float(cfg.end_ratio) * _peak:
		_below_t += dt
	else:
		_below_t = 0.0
	if _below_t > 0.025 or _clock - _t_onset > float(cfg.swing_max_time):
		_finish()

## El azimut que cuenta es el de la parte rápida del swing (donde está el contacto), ponderado por la velocidad.
func _accumulate_direction(gm: float) -> void:
	if gm < 0.55 * _peak:
		return
	var w := gm * gm
	_az_acc += _wrap(azimuth_deg - ref_azimuth) * w
	_az_w += w

func _refresh_ctx() -> void:
	_ctx.peak_dps = _peak
	_ctx.power = _power_from(_peak)
	var rel := _az_acc / maxf(_az_w, 1.0)
	_ctx.az_rel_deg = rel
	_ctx.lateral = _lateral_from(rel)
	var lift := elevation_deg - _el_start
	_ctx.lift_deg = lift
	_ctx.upward = clampf(lift / (2.0 * float(cfg.lob_lift_deg)), -1.0, 1.0)

func _finish() -> void:
	_ctx.finalized = true
	_refresh_ctx()
	_state = "idle"
	_last_end = _clock
	_rearmed = false
	last_gesture = _ctx.duplicate()

func _power_from(peak: float) -> float:
	var x := clampf(inverse_lerp(float(cfg.power_min_dps), float(cfg.power_max_dps), peak), 0.0, 1.0)
	return clampf(pow(x, float(cfg.power_curve)) * 0.9 + 0.1, 0.1, 1.0)

func _lateral_from(rel_deg: float) -> float:
	var dz := float(cfg.lateral_deadzone_deg)
	var m := maxf(absf(rel_deg) - dz, 0.0)
	var v := signf(rel_deg) * pow(clampf(m / maxf(float(cfg.lateral_range_deg) - dz, 1.0), 0.0, 1.0), float(cfg.lateral_gamma))
	return -v if bool(cfg.invert_lateral) else v
