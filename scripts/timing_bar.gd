class_name TimingBar
extends Control
## Barra de timing: sólo muestra la ZONA FINAL donde hay que iniciar el golpe.
## El cursor avanza despacio (ventana de 1,85 s) y entra en la zona verde justo en el momento ideal.
## e = (instante del contacto si inicias el golpe AHORA) - (instante ideal), en segundos:
## negativo = demasiado pronto, 0 = perfecto, positivo = tarde.

const E_MIN := -1.6
const E_MAX := 0.25
const ZONE_A := -0.12
const ZONE_B := 0.10
var e := E_MIN
var frozen := false

func _init() -> void:
	size = Vector2(340, 22)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _x(v: float) -> float:
	return clampf((v - E_MIN) / (E_MAX - E_MIN), 0.0, 1.0) * size.x

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.09, 0.55))
	var za := _x(ZONE_A)
	var zb := _x(ZONE_B)
	var inside := e >= ZONE_A and e <= ZONE_B
	draw_rect(Rect2(Vector2(za, 2), Vector2(zb - za, size.y - 4)), Color(0.2, 0.95, 0.3, 0.95 if inside else 0.75))
	var col := Color(1, 1, 1)
	if frozen:
		col = Color(0.3, 1.0, 0.4) if inside else Color(1.0, 0.35, 0.3)
	elif inside:
		col = Color(0.8, 1.0, 0.8)
	var cx := _x(e)
	draw_rect(Rect2(Vector2(cx - 2.5, -3), Vector2(5.0, size.y + 6)), col)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.35), false, 1.5)
	if inside and not frozen:
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(za - 6, -8), "¡AHORA!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.5, 1.0, 0.6))
