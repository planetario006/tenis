class_name TennisScore
extends RefCounted
## Puntuación de tenis: 15-30-40, ventaja, juegos, sets y tie-break a 7 (diferencia de 2).
## Índice 0 = jugador humano, 1 = CPU.

var points := [0, 0]
var games := [0, 0]
var sets := [0, 0]
var set_log: Array = []
var server := 0
var tiebreak := false
var tb_played := 0
var tb_first_server := 0
var sets_to_win := 2
var games_per_set := 6
var match_over := false
var winner := -1

func reset(first_server: int = 0) -> void:
	points = [0, 0]
	games = [0, 0]
	sets = [0, 0]
	set_log = []
	server = first_server
	tiebreak = false
	tb_played = 0
	match_over = false
	winner = -1

## Devuelve {"game":bool, "set":bool, "match":bool}
func point_won(i: int) -> Dictionary:
	var o := 1 - i
	var ev := {"game": false, "set": false, "match": false}
	points[i] += 1
	if tiebreak:
		tb_played += 1
		server = (tb_first_server + (tb_played + 1) / 2) % 2
		if points[i] >= 7 and points[i] - points[o] >= 2:
			games[i] += 1
			ev.game = true
			_finish_set(i, ev)
		return ev
	if points[i] >= 4 and points[i] - points[o] >= 2:
		games[i] += 1
		points = [0, 0]
		server = 1 - server
		ev.game = true
		if (games[i] >= games_per_set and games[i] - games[o] >= 2):
			_finish_set(i, ev)
		elif games[0] == games_per_set and games[1] == games_per_set:
			tiebreak = true
			tb_played = 0
			tb_first_server = server
	return ev

func _finish_set(i: int, ev: Dictionary) -> void:
	sets[i] += 1
	set_log.append([games[0], games[1]])
	games = [0, 0]
	points = [0, 0]
	tiebreak = false
	ev.set = true
	if sets[i] >= sets_to_win:
		match_over = true
		winner = i
		ev.match = true

func point_text(i: int) -> String:
	var o := 1 - i
	if tiebreak:
		return str(points[i])
	if points[i] >= 3 and points[o] >= 3:
		if points[i] == points[o]:
			return "40"
		return "AD" if points[i] > points[o] else "40"
	return ["0", "15", "30", "40"][mini(points[i], 3)]

## +1 si se saca desde la mitad derecha del sacador (puntos pares).
func serve_right() -> bool:
	if tiebreak:
		return tb_played % 2 == 0
	return (points[0] + points[1]) % 2 == 0
