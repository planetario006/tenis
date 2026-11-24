class_name InputHub
extends Node
## Única fuente de entrada: el mando de Wii (Remote Plus con MotionPlus integrado).
##
##   GESTO .................. golpe: momento, fuerza y dirección (izquierda / centro / derecha)
##   Ningún botón ........... topspin      A ... plano      B ... cortado
##   A + B .................. globo (el swing sube) o dejada (swing que no sube)
##   SAQUE .................. levanta el morro del mando para lanzar la pelota y golpea a tiempo
##   1 / 2 .................. lanzar la pelota (alternativa al gesto) · reiniciar al acabar el partido
##   + ...................... movimiento automático / manual (en manual, la cruceta mueve al jugador)
##   - ...................... panel de depuración del gesto
##   HOME ................... re-centrar la posición de "listo"
##   Cruceta ↑/↓ ............ dificultad · ←/→ superficie (sólo con movimiento automático, antes de sacar)

signal swing_onset(ctx: Dictionary)
signal toss_requested()
signal button_pressed(name: String)

var wii: WiiInput
var move := Vector2.ZERO           # x derecha de pantalla, y hacia la red (sólo en manual)

func _ready() -> void:
	wii = WiiInput.new()
	add_child(wii)
	wii.swing_onset.connect(func(c): swing_onset.emit(c))
	wii.toss_gesture.connect(func(): toss_requested.emit())
	wii.button_pressed.connect(_on_button)

func _on_button(n: String) -> void:
	if n == "ONE" or n == "TWO":
		toss_requested.emit()
	button_pressed.emit(n)

func _process(_delta: float) -> void:
	var m := Vector2.ZERO
	if wii.is_active():
		if wii.btn("RIGHT"): m.x += 1.0
		if wii.btn("LEFT"): m.x -= 1.0
		if wii.btn("UP"): m.y += 1.0
		if wii.btn("DOWN"): m.y -= 1.0
	move = m.limit_length(1.0)
