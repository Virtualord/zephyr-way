extends SceneTree
## Reads the runway's index buffer and classifies every triangle's winding.
##
## This deliberately separates two things that are easy to confuse. A triangle's
## *normal attribute* is a number the generator wrote. Its *winding* is the order its
## three indices come in, and that is what decides whether the rasteriser keeps the
## triangle at all. A triangle can carry a perfectly correct normal and still be
## back-facing, which is precisely the failure this suite exists to catch: the runway's
## normals all measure upward and it still renders torn.
##
## Godot's front faces are wound clockwise. So a triangle whose geometric normal points
## at the viewer is wound counter-clockwise from that viewer's side, and is therefore
## BACK-facing. This counts how many of each the runway actually contains.
##
##   godot --headless --path . --script res://tests/diagnose_runway_winding.gd

## Below this a cross product is noise rather than a direction.
const DEGENERATE_EPS := 1e-6


func _initialize() -> void:
	var runway := Airport._runway(850.0)
	_report("runway", runway)
	_report("apron", Airport._apron(850.0))
	_report("terminal+hangar+tower", Airport._buildings(850.0))
	_report("approach lights", Airport._approach_lights(850.0))
	quit()


func _report(label: String, builder: StructureBuilder) -> void:
	var mesh := builder.build()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var stored: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	# ARRAY_INDEX comes back Nil: SurfaceTool.commit() does not index unless index()
	# is called explicitly, so this geometry is sequential and the vertex order *is*
	# the draw order. Read defensively so a future index() call does not silently turn
	# this into a loop over zero triangles.
	var raw_index: Variant = arrays[Mesh.ARRAY_INDEX]
	var indices: PackedInt32Array = [] if raw_index == null else raw_index
	var count: int = indices.size() / 3 if indices.size() > 0 else verts.size() / 3

	print("")
	print("=== %s: %d triangles, %d vertices, %s ===" % [
		label, count, verts.size(),
		"indexed" if indices.size() > 0 else "SEQUENTIAL (no index buffer)"])

	var upward := 0
	var downward := 0
	var degenerate := 0
	var normal_agrees := 0
	var normal_disagrees := 0
	# Grouped by the y the triangle sits at, which is what tells us which primitive
	# or band a reversed triangle came from.
	var bands := {}
	var examples := {}

	for i in count:
		var ia: int = indices[i * 3] if indices.size() > 0 else i * 3
		var ib: int = indices[i * 3 + 1] if indices.size() > 0 else i * 3 + 1
		var ic: int = indices[i * 3 + 2] if indices.size() > 0 else i * 3 + 2
		var pa := verts[ia]
		var pb := verts[ib]
		var pc := verts[ic]

		var geometric := (pb - pa).cross(pc - pa)
		if geometric.length() < DEGENERATE_EPS:
			degenerate += 1
			continue

		var up := geometric.y > 0.0
		if up:
			upward += 1
		else:
			downward += 1

		# Does the stored normal agree with the winding's own direction?
		var face_normal := (stored[ia] + stored[ib] + stored[ic]) / 3.0
		if face_normal.length() > DEGENERATE_EPS:
			if geometric.normalized().dot(face_normal.normalized()) > 0.0:
				normal_agrees += 1
			else:
				normal_disagrees += 1

		# Horizontal triangles are the ones a camera above can see, and their y says
		# which surface they belong to.
		var ys := [pa.y, pb.y, pc.y]
		var same_y := absf(ys[0] - ys[1]) < 0.001 and absf(ys[1] - ys[2]) < 0.001
		var band_key := "y=%.2f %s" % [ys[0], "UP" if up else "DOWN"] if same_y else "vertical"
		if not bands.has(band_key):
			bands[band_key] = 0
			examples[band_key] = ""
		bands[band_key] += 1
		if examples[band_key] == "":
			examples[band_key] = "%d,%d,%d" % [ia, ib, ic]

	print("  triangles wound so the geometric normal points UP   : %d" % upward)
	print("  triangles wound so the geometric normal points DOWN : %d" % downward)
	print("  degenerate (zero area)                              : %d" % degenerate)
	print("  stored normal AGREES with the winding direction      : %d" % normal_agrees)
	print("  stored normal DISAGREES with the winding direction   : %d" % normal_disagrees)
	print("")
	print("  Under Godot's clockwise-front convention, the UP group is BACK-facing from")
	print("  above and would be culled. Breakdown by surface:")
	var keys := bands.keys()
	keys.sort()
	for key: String in keys:
		print("    %-16s %4d triangles   e.g. indices %s" % [
			key, bands[key], examples[key]])
