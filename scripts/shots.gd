class_name Shots
extends RefCounted
## Tipos de golpe. spin>0 = topspin, spin<0 = backspin (rad/s; 100 rad/s ≈ 950 rpm).
## Mapeo de botones del mando (como pediste): ninguno = topspin, A = plano, B = cortado,
## A+B = globo o dejada según el gesto.

const TYPES := {
	"topspin": {"label": "TOPSPIN", "mode": "angle", "v_min": 17.0, "v_max": 33.0, "spin_min": 110.0, "spin_max": 300.0, "net_margin": 0.30, "stamina": 0.05},
	"flat":    {"label": "PLANO",   "mode": "angle", "v_min": 20.0, "v_max": 41.0, "spin_min": 15.0,  "spin_max": 55.0,  "net_margin": 0.12, "stamina": 0.07},
	"slice":   {"label": "CORTADO", "mode": "angle", "v_min": 13.0, "v_max": 27.0, "spin_min": -110.0, "spin_max": -240.0, "net_margin": 0.22, "stamina": 0.04},
	"lob":     {"label": "GLOBO",   "mode": "speed", "angle": 56.0, "spin_min": 60.0, "spin_max": 110.0, "stamina": 0.04},
	"drop":    {"label": "DEJADA",  "mode": "speed", "angle": 16.0, "spin_min": -180.0, "spin_max": -260.0, "stamina": 0.03},
	# saques
	"serve_flat":  {"label": "SAQUE PLANO",   "mode": "angle", "v_min": 30.0, "v_max": 52.0, "spin_min": 10.0, "spin_max": 40.0, "net_margin": 0.22, "stamina": 0.06},
	"serve_kick":  {"label": "SAQUE KICK",    "mode": "angle", "v_min": 24.0, "v_max": 42.0, "spin_min": 150.0, "spin_max": 320.0, "net_margin": 0.35, "stamina": 0.06},
	"serve_slice": {"label": "SAQUE CORTADO", "mode": "angle", "v_min": 26.0, "v_max": 46.0, "spin_min": -60.0, "spin_max": -170.0, "net_margin": 0.18, "stamina": 0.06},
}

## Elige el golpe según los botones (A, B) y el gesto (subida del mando) en el mando.
static func from_buttons(a: bool, b: bool, upward: float = 0.0) -> String:
	if a and b:
		return "lob" if upward >= 0.5 else "drop"
	if a:
		return "flat"
	if b:
		return "slice"
	return "topspin"

static func serve_from_buttons(a: bool, b: bool) -> String:
	if a:
		return "serve_flat"
	if b:
		return "serve_slice"
	return "serve_kick"
