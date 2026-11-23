class_name Court
extends RefCounted
## Dimensiones reglamentarias ITF (metros). Eje Z = largo de la pista, eje X = ancho, Y = altura.
## La red está en z = 0. El jugador humano juega en z > 0 (cámara detrás), la CPU en z < 0.

const LENGTH := 23.77
const HALF_L := 11.885
const SINGLES_W := 8.23
const HALF_W := 4.115
const SERVICE_Z := 6.40
const NET_CENTER_H := 0.914
const NET_POST_H := 1.07
const NET_HALF_W := 5.485
const BALL_R := 0.0335

## e = coeficiente de restitución normal, mu = fricción de deslizamiento bola-suelo
const SURFACES := {
	"hard": {"name": "Pista dura", "e": 0.745, "mu": 0.60,
		"court": Color(0.10, 0.30, 0.64), "outer": Color(0.06, 0.18, 0.40), "marks": false},
	"clay": {"name": "Tierra batida", "e": 0.700, "mu": 0.80,
		"court": Color(0.62, 0.28, 0.15), "outer": Color(0.55, 0.25, 0.13), "marks": true},
}

static func net_height(x: float) -> float:
	var k := clampf(absf(x) / NET_HALF_W, 0.0, 1.0)
	return NET_CENTER_H + (NET_POST_H - NET_CENTER_H) * k * k

## ¿Cae dentro de las líneas de individuales? (la bola que toca línea es buena)
static func in_singles(p: Vector3) -> bool:
	return absf(p.x) <= HALF_W + BALL_R and absf(p.z) <= HALF_L + BALL_R

## Cuadro de saque al que debe ir el saque. server_side = +1 (z>0) o -1; server_x_sign = +1 si saca desde x>0.
static func in_service_box(p: Vector3, server_side: int, server_x_sign: int) -> bool:
	var tz: float = -float(server_side) * p.z   # distancia hacia el lado contrario, positiva si cruzó
	if tz < -BALL_R or tz > SERVICE_Z + BALL_R:
		return false
	var tx: float = -float(server_x_sign) * p.x # el cuadro es el diagonal opuesto
	return tx >= -BALL_R and tx <= HALF_W + BALL_R

## Objetivo central del cuadro de saque (para la IA y el valor por defecto de la cruz).
static func service_box_center(server_side: int, server_x_sign: int) -> Vector3:
	return Vector3(-float(server_x_sign) * HALF_W * 0.5, 0.0, -float(server_side) * SERVICE_Z * 0.86)
