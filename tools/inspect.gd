extends SceneTree
func _init():
	var lib: AnimationLibrary = load("res://animaciones/tenista_animaciones.res")
	for n in lib.get_animation_list():
		var a: Animation = lib.get_animation(n)
		print("ANIM '", n, "' len=", a.length, " loop=", a.loop_mode, " tracks=", a.get_track_count())
	var ps: PackedScene = load("res://assets/Barbarian.glb")
	var root = ps.instantiate()
	print("ROOT ", root.name, " ", root.get_class())
	_dump(root, 0)
	var sk: Skeleton3D = root.find_child("Skeleton3D", true, false)
	for i in sk.get_bone_count():
		print("BONE ", i, " ", sk.get_bone_name(i), " parent=", sk.get_bone_parent(i), " rest_origin=", sk.get_bone_rest(i).origin)
	var rs: PackedScene = load("res://assets/raqueta.glb")
	var r = rs.instantiate()
	_dump(r, 0)
	quit()
func _dump(n: Node, d: int):
	var s = "  ".repeat(d) + n.name + " [" + n.get_class() + "]"
	if n is MeshInstance3D:
		var ab: AABB = n.get_aabb()
		s += " aabb pos=" + str(ab.position) + " size=" + str(ab.size)
	if n is Skeleton3D:
		s += " bones=" + str(n.get_bone_count())
	print(s)
	for c in n.get_children(): _dump(c, d+1)
