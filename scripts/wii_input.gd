class_name WiiInput
extends Node
## Recibe por UDP los paquetes JSON del puente Python (wii/wii_bridge.py) y detecta el golpe.
## Paquete: {"t": seg, "a": [ax,ay,az] (g), "g": [gx,gy,gz] (°/s, sin sesgo), "b": máscara de botones}
##
## Del gesto se extrae:
##   FUERZA     -> velocidad angular pico del giroscopio (MotionPlus)
##   MOMENTO    -> instante del inicio del gesto (onset), lo compara el juego con la pelota
##   DIRECCIÓN  -> barrido lateral del gesto (guiñada integrada): recto = paralelo, cruzado = cruzado
##   SAQUE      -> gesto de levantar el mando (cabeceo hacia arriba) lanza la pelota; luego se golpea
##   GOLPE      -> botones: ninguno = topspin, A = plano, B = cortado, A+B = globo/dejada
##                 (globo si el gesto sube, dejada si es corto/plano)

signal swing_onset(ctx: Dictionary)
signal toss_pressed()
signal recentered()
signal assist_toggled()

const BTN := {"A": 1, "B": 2, "ONE": 4, "TWO": 8, "PLUS": 16, "MINUS": 32, "HOME": 64,
	"UP": 128, "DOWN": 256, "LEFT": 512, "RIGHT": 1024}

var cfg := {
	"port": 9876,
	"onset_dps": 350.0,
	"power_min_dps": 350.0,
	"power_max_dps": 1500.0,
	"yaw_axis": 2, "yaw_sign": 1.0,
	"pitch_axis": 0, "pitch_sign": 1.0,
	"accel_pitch_num": 1, "accel_pitch_den": 2,
	"aim_gain_deg": 35.0,
	"pitch_range_deg": 45.0,
	"swing_cooldown": 0.45,
	"button_lookback": 0.25,
	"cross_min_deg": 15.0,       # barrido lateral (°) a partir del cual el golpe empieza a "cruzar"
	"cross_max_deg": 80.0,       # barrido con el que el golpe es totalmente cruzado
	"invert_lateral": false,     # invierte recto/cruzado si en tu mano sale al revés
	"toss_up_ratio": 0.5,        # cuánto debe ser "hacia arriba" el gesto de lanzar la pelota
}
var udp := PacketPeerUDP.new()
var listening := false
var last_packet_ms := -100000
var buttons := 0
var acc := Vector3(0, 0, 1)
var gyro := Vector3.ZERO
var yaw_deg := 0.0
var pitch_deg := 0.0
var pitch_neutral := 0.0
var aim := Vector2(0.0, 0.7)       # x: -1..1 lateral, y: 0..1 profundidad (en vivo)
var _state := "idle"
var _ctx: Dictionary = {}
var _peak := 0.0
var _peak_t := 0.0
var _peak_g := Vector3.ZERO
var _yaw_sweep := 0.0
var _pitch_sweep := 0.0
var _t_onset := 0.0
var _last_end := -10.0
var _still_t := 0.0
var _a_t := -10.0
var _b_t := -10.0
var _hist: Array = []              # historial de aim para "congelar" el apuntado antes del gesto
var _last_t := -1.0
var _clock := 0.0

func _ready() -> void:
	for path in ["res://wii/wii_config.json", "user://wii_config.json"]:
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				for k in parsed:
					cfg[k] = parsed[k]
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

func _process(delta: float) -> void:
	_clock += delta
	if not listening:
		return
	while udp.get_available_packet_count() > 0:
		var txt := udp.get_packet().get_string_from_utf8()
		var d = JSON.parse_string(txt)
		if d is Dictionary and d.has("g"):
			var a: Array = d.get("a", [0, 0, 1])
			var g: Array = d["g"]
			var t := float(d.get("t", _clock))
			var dt := 0.01 if _last_t < 0.0 else clampf(t - _last_t, 0.0005, 0.05)
			_last_t = t
			last_packet_ms = Time.get_ticks_msec()
			ingest(Vector3(a[0], a[1], a[2]), Vector3(g[0], g[1], g[2]), int(d.get("b", 0)), dt)

## Procesa una muestra (también la usan los tests para simular un mando).
func ingest(acc_g: Vector3, gyro_dps: Vector3, btn_mask: int, dt: float) -> void:
	_clock += 0.0
	acc = acc_g
	gyro = gyro_dps
	var pressed := btn_mask & ~buttons
	buttons = btn_mask
	if pressed & int(BTN.HOME):
		recenter()
	if pressed & int(BTN.PLUS):
		assist_toggled.emit()
	if pressed & (int(BTN.ONE) | int(BTN.TWO)):
		toss_pressed.emit()
	if buttons & int(BTN.A):
		_a_t = _clock
	if buttons & int(BTN.B):
		_b_t = _clock
	yaw_deg += float(cfg.yaw_sign) * gyro[int(cfg.yaw_axis)] * dt
	var den: float = acc[int(cfg.accel_pitch_den)]
	pitch_deg = lerpf(pitch_deg, rad_to_deg(atan2(acc[int(cfg.accel_pitch_num)], den)), 0.2)
	aim.x = clampf(yaw_deg / float(cfg.aim_gain_deg), -1.0, 1.0)
	aim.y = clampf(0.7 + (pitch_deg - pitch_neutral) / float(cfg.pitch_range_deg), 0.05, 1.0)
	_hist.append([_clock, aim.x, aim.y])
	while _hist.size() > 0 and _clock - float(_hist[0][0]) > 0.35:
		_hist.pop_front()
	var gm := gyro.length()
	match _state:
		"idle":
			if gm > float(cfg.onset_dps) and _clock - _last_end > float(cfg.swing_cooldown):
				_begin(gm)
		"swing":
			_yaw_sweep += float(cfg.yaw_sign) * gyro[int(cfg.yaw_axis)] * dt
			_pitch_sweep += float(cfg.pitch_sign) * gyro[int(cfg.pitch_axis)] * dt
			_ctx.yaw_sweep = _yaw_sweep
			_ctx.pitch_sweep = _pitch_sweep
			if gm > _peak:
				_peak = gm
				_peak_t = _clock
				_peak_g = gyro
			_ctx.peak_dps = _peak
			_ctx.power = _power_from(_peak)
			_ctx.upward = _upward()
			if buttons & int(BTN.A):
				_ctx.a = true
			if buttons & int(BTN.B):
				_ctx.b = true
			var elapsed := _clock - _t_onset
			if (gm < 0.45 * _peak and _clock - _peak_t > 0.02) or elapsed > 0.32:
				_ctx.finalized = true
				_state = "cool"
				_last_end = _clock
		"cool":
			if gm < 40.0:
				_still_t += dt
				if _still_t > 0.35:
					yaw_deg = 0.0          # re-centrar la guiñada tras el golpe
					_state = "idle"
			else:
				_still_t = 0.0

func _begin(gm: float) -> void:
	_state = "swing"
	_t_onset = _clock
	_peak = gm
	_peak_t = _clock
	_peak_g = gyro
	_still_t = 0.0
	_yaw_sweep = float(cfg.yaw_sign) * gyro[int(cfg.yaw_axis)] * 0.01
	_pitch_sweep = float(cfg.pitch_sign) * gyro[int(cfg.pitch_axis)] * 0.01
	# apuntado: el que había ~0.1 s antes (el propio gesto ya mueve la guiñada)
	var ax := aim.x
	var ay := aim.y
	for h in _hist:
		if _clock - float(h[0]) <= 0.12:
			ax = float(h[1])
			ay = float(h[2])
			break
	var lb := float(cfg.button_lookback)
	_ctx = {"source": "wii", "t_onset": _clock, "aim_x": ax, "aim_y": ay, "power": _power_from(gm),
		"upward": _upward(), "yaw_sweep": _yaw_sweep, "pitch_sweep": _pitch_sweep, "a": _clock - _a_t < lb, "b": _clock - _b_t < lb, "finalized": false, "peak_dps": gm}
	swing_onset.emit(_ctx)

func _power_from(peak: float) -> float:
	return clampf(inverse_lerp(float(cfg.power_min_dps), float(cfg.power_max_dps), peak), 0.1, 1.0)

func _upward() -> float:
	return float(cfg.pitch_sign) * _peak_g[int(cfg.pitch_axis)] / maxf(_peak_g.length(), 1.0)

func recenter() -> void:
	yaw_deg = 0.0
	pitch_neutral = pitch_deg
	recentered.emit()
