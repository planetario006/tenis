class_name HUD
extends CanvasLayer

var score_lbl: Label
var msg_lbl: Label
var help_lbl: Label
var status_lbl: Label
var shot_lbl: Label
var timing: TimingBar
var _msg_t := 0.0
var _freeze_t := 0.0

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.12, 0.82)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	score_lbl = Label.new()
	score_lbl.add_theme_font_size_override("font_size", 22)
	panel.add_child(score_lbl)
	msg_lbl = Label.new()
	msg_lbl.add_theme_font_size_override("font_size", 54)
	msg_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	msg_lbl.add_theme_constant_override("outline_size", 10)
	msg_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	msg_lbl.position = Vector2(-300, 90)
	msg_lbl.size = Vector2(600, 80)
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(msg_lbl)
	shot_lbl = Label.new()
	shot_lbl.add_theme_font_size_override("font_size", 24)
	shot_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	shot_lbl.add_theme_constant_override("outline_size", 6)
	shot_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	shot_lbl.position = Vector2(-200, 168)
	shot_lbl.size = Vector2(400, 40)
	shot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(shot_lbl)
	help_lbl = Label.new()
	help_lbl.add_theme_font_size_override("font_size", 11)
	help_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	help_lbl.add_theme_constant_override("outline_size", 4)
	help_lbl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help_lbl.position = Vector2(18, -92)
	help_lbl.text = "WII: gesto = golpe (recto = paralelo · cruzado = cruzado) · sin botón topspin · A plano · B cortado · A+B globo/dejada\nWII SAQUE: levanta el mando para lanzar y golpea a tiempo · botón + = movimiento auto/manual\nTECLADO: ESPACIO golpear/lanzar · Q paralelo · E cruzado · J plano · K cortado · J+K+I globo · Shift fuerte · M auto/manual · flechas mover (manual)\nX amarilla = dónde botará la bola del rival en tu campo · V invierte recto/cruzado · C superficie · F1-F3 dificultad · R reiniciar"
	root.add_child(help_lbl)
	status_lbl = Label.new()
	status_lbl.add_theme_font_size_override("font_size", 14)
	status_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	status_lbl.position = Vector2(-360, 16)
	status_lbl.size = Vector2(340, 40)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(status_lbl)
	timing = TimingBar.new()
	timing.visible = false
	root.add_child(timing)

func update_score(sc: TennisScore, names: Array, server: int) -> void:
	var s := ""
	for i in 2:
		var row := "%s%-6s" % ["● " if server == i else "   ", names[i]]
		for st in sc.set_log:
			row += "  %d" % st[i]
		row += "  %d" % sc.games[i]
		row += "   | %s" % sc.point_text(i)
		s += row + ("\n" if i == 0 else "")
	if sc.tiebreak:
		s += "\n   (tie-break)"
	score_lbl.text = s

func flash(text: String, color: Color = Color.WHITE, dur: float = 1.4) -> void:
	msg_lbl.text = text
	msg_lbl.add_theme_color_override("font_color", color)
	_msg_t = dur

func set_shot_info(text: String) -> void:
	shot_lbl.text = text

func set_timing(is_visible: bool, e: float, screen_pos: Vector2 = Vector2.ZERO) -> void:
	if _freeze_t > 0.0:
		return
	timing.visible = is_visible
	timing.e = e
	timing.frozen = false
	timing.position = screen_pos
	timing.queue_redraw()

func freeze_timing(e: float, dur: float = 0.7) -> void:
	timing.e = e
	timing.frozen = true
	timing.visible = true
	_freeze_t = dur
	timing.queue_redraw()

func _process(delta: float) -> void:
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			msg_lbl.text = ""
	if _freeze_t > 0.0:
		_freeze_t -= delta
		if _freeze_t <= 0.0:
			timing.frozen = false
			timing.visible = false
