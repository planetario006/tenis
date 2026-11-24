extends SceneTree
## Alimenta WiiInput con /tmp/scenario.json (tools/gen_scenario.py) y muestra lo que reconoce.
## godot --headless --path . --script tools/test_gestures.gd
func _initialize() -> void:
	var w := WiiInput.new()
	root.add_child(w)
	var toss := [0]
	var swings := [0]
	w.toss_gesture.connect(func(): toss[0] += 1)
	w.swing_onset.connect(func(_c): swings[0] += 1)
	var segs = JSON.parse_string(FileAccess.get_file_as_string("/tmp/scenario.json"))
	for s in segs:
		toss[0] = 0
		swings[0] = 0
		w.last_gesture = {}
		for p in s.packets:
			w.ingest(Vector3(p.a[0], p.a[1], p.a[2]), Vector3(p.g[0], p.g[1], p.g[2]), int(p.b), 0.01)
		var g: Dictionary = w.last_gesture
		var line := "%-34s toss=%d golpes=%d" % [s.label, toss[0], swings[0]]
		if not g.is_empty():
			line += " | pico=%4.0f fuerza=%.2f lateral=%+.2f (%+5.1f°) sube=%+5.1f° A=%s B=%s shot=%s" % [float(g.peak_dps), float(g.power), float(g.lateral), float(g.az_rel_deg), float(g.lift_deg), g.a, g.b, Shots.from_buttons(g.a, g.b, float(g.upward))]
		print(line)
	quit()
