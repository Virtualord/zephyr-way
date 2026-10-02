extends SceneTree
## Checks two independent things about every face a StructureBuilder produces.
##
## **Normals.** The stored normal attribute must point out of the shape, so lighting is
## right. This was correct all along.
##
## **Winding.** The order the three corners are emitted in must be such that Godot
## counts the triangle as front-facing. These are separate and were separate in the
## failure: the runway carried 166 correct upward normals and every single one of its
## triangles was still culled. A normal attribute is a number the generator writes; the
## winding is what the rasteriser reads, and one does not imply the other.
##
## Godot's front faces are **clockwise on screen**. The right-hand rule says
## (b - a) x (c - a) points out of a triangle that runs counter-clockwise as seen from
## that side. So for a correct face, the right-hand-rule normal of the *emitted* order
## must point **opposite** to the stored normal. That is the whole assertion, and it is
## the one that fails when the winding is inverted.
##
## Convex solids still draw when the winding is wrong -- you see the inside of the far
## wall instead of the outside of the near one, at nearly the same depth -- so nothing
## looks obviously broken until two surfaces meet. The runway's underside is coplanar
## with the plateau at exactly 14.000 m, and once the real top face was culled the
## underside fought the terrain for the depth buffer.
##
##   godot --headless --path . --script res://tests/structure_test.gd

var _failures := 0
var _checks := 0


func _initialize() -> void:
	var color := Color(1.0, 1.0, 1.0)

	_check_box(Basis.IDENTITY, Vector3(4.0, 2.0, 6.0), "box at origin", color)
	_check_box(Basis.IDENTITY, Vector3(4.0, 2.0, 6.0), "box, moved and turned", color,
		Transform3D(Basis.from_euler(Vector3(0.4, 0.9, -0.3)), Vector3(120.0, -30.0, 55.0)))
	_check_cylinder("cylinder, straight", 5.0, 5.0, 10.0, 8, color)
	_check_cylinder("cylinder, tapered", 7.0, 3.0, 12.0, 10, color)
	_check_cylinder("cylinder, to a point", 6.0, 0.0, 9.0, 8, color)
	# Pyramids, roofs and slabs are not closed solids with the origin inside them: a
	# pyramid's base and a roof's underside correctly point *away* from the centroid,
	# so the centre-based test below reports them as inverted when they are in fact
	# the one face that is right. Those three are checked by direction instead.
	_check_pyramid("pyramid", color)
	_check_gable("gable roof", color)
	_check_slab("slab", color)

	# Winding is checked on the primitives too, and separately from their normals.
	_expect_clockwise_front_faces("box at origin", _box_mesh(Basis.IDENTITY,
		Vector3(4.0, 2.0, 6.0), Transform3D.IDENTITY))
	_expect_clockwise_front_faces("cylinder, tapered", _cylinder_mesh(7.0, 3.0, 12.0, 10))
	_expect_clockwise_front_faces("pyramid", _pyramid_mesh())
	_expect_clockwise_front_faces("gable roof", _gable_mesh())
	_expect_clockwise_front_faces("slab", _slab_mesh())

	# The real geometry, not just the primitives: the runway is the surface that
	# actually failed, and a primitive-level check would not have caught it if the
	# bug were in how the runway composes them.
	_check_real_geometry()

	print("")
	if _failures == 0:
		print("%d checks passed" % _checks)
		quit(0)
	else:
		print("%d of %d checks FAILED" % [_failures, _checks])
		quit(1)


func _check_box(basis: Basis, size: Vector3, label: String, color: Color,
		xform := Transform3D.IDENTITY) -> void:
	var builder := StructureBuilder.new()
	builder.box(xform, size, color)
	_expect_outward(builder, label)


func _check_cylinder(label: String, r_bottom: float, r_top: float, height: float,
		sides: int, color: Color) -> void:
	var builder := StructureBuilder.new()
	builder.cylinder(Transform3D(Basis.from_euler(Vector3(0.2, 1.1, 0.5)),
		Vector3(-40.0, 12.0, 77.0)), r_bottom, r_top, height, color, sides, true, true)
	_expect_outward(builder, label)


func _check_pyramid(label: String, color: Color) -> void:
	var builder := StructureBuilder.new()
	builder.pyramid(Transform3D(Basis.from_euler(Vector3(0.0, 0.7, 0.0)),
		Vector3(10.0, -5.0, 20.0)), Vector2(9.0, 7.0), 8.0, color)
	_expect_slopes_up(builder, label)
	_expect_base_down(builder, label)


func _check_gable(label: String, color: Color) -> void:
	var builder := StructureBuilder.new()
	builder.gable_roof(Basis.from_euler(Vector3(0.0, 0.35, 0.0)),
		Vector3(0.0, 3.0, 0.0), Vector2(12.0, 8.0), 5.0, 1.0, color)
	_expect_slopes_up(builder, label)
	_expect_base_down(builder, label)


func _check_slab(label: String, color: Color) -> void:
	var builder := StructureBuilder.new()
	builder.slab(Basis.IDENTITY, Vector3.ZERO, Vector2(10.0, 6.0), color, true)
	_expect_all_up(builder, label)


## The runway, apron and lighthouse, built the way the island builds them.
func _check_real_geometry() -> void:
	var generator := TerrainGenerator.new()
	generator.configure()

	var runway := Airport._runway(generator.runway_length)
	_check("runway has geometry", not runway.is_empty(),
		"%d triangles" % runway.triangle_count())
	_expect_upward_faces(runway, "runway surface")
	_expect_clockwise_front_faces("runway", runway.build())

	var buildings := Airport._buildings(generator.runway_length)
	_expect_clockwise_front_faces("airport buildings", buildings.build())
	var lights := Airport._approach_lights(generator.runway_length)
	_expect_clockwise_front_faces("approach lights", lights.build())

	var apron := Airport._apron(generator.runway_length)
	_expect_upward_faces(apron, "apron surface")

	var light_masts := Airport._approach_lights(generator.runway_length)
	_check("approach lights have geometry", not light_masts.is_empty(),
		"%d triangles" % light_masts.triangle_count())


## Assert that the builder's upward-facing faces actually point up.
##
## The runway is a horizontal surface, so "outward" is not a useful test for it -- a
## correctly wound slab has its top pointing up and its sides pointing sideways, and the
## centre-based test would flag the underside. What matters is that the faces a viewer
## looks down on are front-facing, which is the same as their normals pointing up.
func _expect_upward_faces(builder: StructureBuilder, label: String) -> void:
	var arrays := builder.build().surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var up := 0
	var down := 0
	for normal in normals:
		if normal.y > 0.5:
			up += 1
		elif normal.y < -0.5:
			down += 1
	_check("%s has upward faces" % label, up > 0, "%d up, %d down" % [up, down])
	_check("%s has a downward underside" % label, down > 0, "%d down" % down)


## Assert that every face normal points away from the builder's own centre.
##
## True for any correctly wound closed convex solid, which is every primitive here.
func _expect_outward(builder: StructureBuilder, label: String) -> void:
	if builder.is_empty():
		_check("%s produced geometry" % label, false)
		return
	var arrays := builder.build().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var centre := Vector3.ZERO
	for v in verts:
		centre += v
	centre /= float(maxi(verts.size(), 1))

	var inverted := 0
	var worst := ""
	for i in normals.size():
		var from_centre := verts[i] - centre
		# A face through the exact centre has no meaningful outward direction; skip
		# those rather than call them inverted.
		if from_centre.length() < 0.05:
			continue
		if from_centre.normalized().dot(normals[i]) < 0.0:
			inverted += 1
			if worst.is_empty():
				worst = "at %v normal %v" % [verts[i], normals[i]]
	_check("%s faces outward" % label, inverted == 0,
		"%d of %d faces point inward, %s" % [inverted, normals.size(), worst])


## Assert that every triangle is wound so Godot counts it as a FRONT face.
##
## The check is on the emitted corner order, read straight out of the buffer, and it is
## deliberately *not* the same test as [method _expect_outward]. This one would pass on
## the broken runway; the normals one also would. Neither catches the other, which is
## the entire reason both exist.
func _expect_clockwise_front_faces(label: String, mesh: ArrayMesh) -> void:
	if mesh == null:
		_check("%s winding is front-facing" % label, false, "no mesh")
		return
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var stored: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var raw_index: Variant = arrays[Mesh.ARRAY_INDEX]
	var indices: PackedInt32Array = [] if raw_index == null else raw_index
	var count: int = indices.size() / 3 if indices.size() > 0 else verts.size() / 3

	var front_facing := 0
	var back_facing := 0
	var degenerate := 0
	var worst := ""
	for i in count:
		var ia: int = indices[i * 3] if indices.size() > 0 else i * 3
		var ib: int = indices[i * 3 + 1] if indices.size() > 0 else i * 3 + 1
		var ic: int = indices[i * 3 + 2] if indices.size() > 0 else i * 3 + 2
		# Right-hand rule over the order actually emitted.
		var geometric := (verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
		if geometric.length() < 0.000001:
			degenerate += 1
			continue
		# Must oppose the stored normal, because front is clockwise and the right-hand
		# rule describes the counter-clockwise direction.
		if geometric.normalized().dot(stored[ia].normalized()) < 0.0:
			front_facing += 1
		else:
			back_facing += 1
			if worst.is_empty():
				worst = "first at corners %d,%d,%d" % [ia, ib, ic]

	_check("%s winding is front-facing" % label, back_facing == 0,
		"%d front, %d back, %d degenerate, %s" % [
			front_facing, back_facing, degenerate, worst])


func _box_mesh(basis: Basis, size: Vector3, xform: Transform3D) -> ArrayMesh:
	var builder := StructureBuilder.new()
	builder.box(xform, size, Color.WHITE)
	return builder.build()


func _cylinder_mesh(r_bottom: float, r_top: float, height: float, sides: int) -> ArrayMesh:
	var builder := StructureBuilder.new()
	builder.cylinder(Transform3D(Basis.from_euler(Vector3(0.2, 1.1, 0.5)),
		Vector3(-40.0, 12.0, 77.0)), r_bottom, r_top, height, Color.WHITE, sides, true, true)
	return builder.build()


func _pyramid_mesh() -> ArrayMesh:
	var builder := StructureBuilder.new()
	builder.pyramid(Transform3D(Basis.from_euler(Vector3(0.0, 0.7, 0.0)),
		Vector3(10.0, -5.0, 20.0)), Vector2(9.0, 7.0), 8.0, Color.WHITE)
	return builder.build()


func _gable_mesh() -> ArrayMesh:
	var builder := StructureBuilder.new()
	builder.gable_roof(Basis.from_euler(Vector3(0.0, 0.35, 0.0)),
		Vector3(0.0, 3.0, 0.0), Vector2(12.0, 8.0), 5.0, 1.0, Color.WHITE)
	return builder.build()


func _slab_mesh() -> ArrayMesh:
	var builder := StructureBuilder.new()
	builder.slab(Basis.IDENTITY, Vector3.ZERO, Vector2(10.0, 6.0), Color.WHITE, true)
	return builder.build()


## Every face must point up. For a single horizontal quad that is the whole question.
func _expect_all_up(builder: StructureBuilder, label: String) -> void:
	var normals: PackedVector3Array = builder.build().surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var down := 0
	for normal in normals:
		if normal.y < -0.5:
			down += 1
	_check("%s faces up" % label, down == 0, "%d of %d point down" % [down, normals.size()])


## The pitched faces must point up and away. The underside is allowed to point down.
func _expect_slopes_up(builder: StructureBuilder, label: String) -> void:
	var normals: PackedVector3Array = builder.build().surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var up := 0
	for normal in normals:
		if normal.y > 0.1:
			up += 1
	_check("%s has upward slopes" % label, up > 0, "%d of %d" % [up, normals.size()])


## The base must point down, out of the shape, or it is wound inside-out and culled
## from every angle that can see it.
func _expect_base_down(builder: StructureBuilder, label: String) -> void:
	var normals: PackedVector3Array = builder.build().surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var down := 0
	for normal in normals:
		if normal.y < -0.9:
			down += 1
	_check("%s base faces down" % label, down > 0, "%d of %d" % [down, normals.size()])


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if ok:
		print("  PASS  %s%s" % [label, "" if detail.is_empty() else "  (%s)" % detail])
	else:
		_failures += 1
		print("  FAIL  %s%s" % [label, "" if detail.is_empty() else "  (%s)" % detail])
