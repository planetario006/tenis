class_name InputHub
extends Node
## Unifica teclado / mando de consola / mando de Wii.
##
## MANDO DE WII
##   Gesto de golpe ........ fuerza, momento y dirección (recto = paralelo, cruzado = cruzado)
##   Ningún botón .......... topspin     A ...... plano     B ...... cortado
##   A + B ................. globo (gesto hacia arriba) o dejada (gesto corto)
##   Saque ................. levanta el mando (morro arriba) para lanzar la pelota y golpea a tiempo
##   + ..................... activa/desactiva el movimiento automático      HOME ... re-centrar
## TECLADO
##   Flechas / WASD mover (si el movimiento automático está desactivado) · ESPACIO golpear / lanzar
##   Q = paralelo, E = cruzado (sin tecla = al centro) · J plano · K cortado · J+K(+I) globo/dejada
##   Shift fuerte · Ctrl suave · M movimiento automático · V invertir recto/cruzado

signal swing_onset(ctx: Dictionary)
signal toss_pressed()
signal assist_toggled()

var wii: WiiInput
var move := Vector2.ZERO           # x derecha de pantalla, y hacia la red
var _prev_space := false

func _ready() -> void:
	wii = WiiInput.new()
	add_child(wii)
	wii.swing_onset.connect(func(c): swing_onset.emit(c))
	wii.toss_pressed.connect(func(): toss_pressed.emit())
	wii.assist_toggled.connect(func(): assist_toggled.emit())

func _process(_delta: float) -> void:
	var m := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): m.x += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): m.x -= 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): m.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): m.y -= 1.0
	if wii.is_active():
		if wii.btn("RIGHT"): m.x += 1.0
		if wii.btn("LEFT"): m.x -= 1.0
		if wii.btn("UP"): m.y += 1.0
		if wii.btn("DOWN"): m.y -= 1.0
	var js := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), -Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if js.length() > 0.2:
		m += js
	move = m.limit_length(1.0)
	var space := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_X) \
		or Input.is_joy_button_pressed(0, JOY_BUTTON_A) or Input.is_joy_button_pressed(0, JOY_BUTTON_B) \
		or Input.is_joy_button_pressed(0, JOY_BUTTON_Y)
	if space and not _prev_space:
		var a := Input.is_physical_key_pressed(KEY_J) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)
		var b := Input.is_physical_key_pressed(KEY_K) or Input.is_joy_button_pressed(0, JOY_BUTTON_B)
		var up := 1.0 if (Input.is_physical_key_pressed(KEY_I) or Input.is_joy_button_pressed(0, JOY_BUTTON_Y)) else 0.0
		var pw := 0.78
		if Input.is_physical_key_pressed(KEY_SHIFT): pw = 1.0
		if Input.is_physical_key_pressed(KEY_CTRL): pw = 0.4
		var c := 0.5
		if Input.is_physical_key_pressed(KEY_Q): c = 0.0
		if Input.is_physical_key_pressed(KEY_E): c = 1.0
		toss_pressed.emit()
		swing_onset.emit({"source": "kb", "aim_x": 0.0, "aim_y": 0.7, "power": pw, "upward": up, "cross_c": c,
			"a": a, "b": b, "finalized": true, "peak_dps": 0.0})
	_prev_space = space
