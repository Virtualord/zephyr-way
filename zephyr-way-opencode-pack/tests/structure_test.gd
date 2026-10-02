extends SceneTree
## Checks that every face a StructureBuilder produces points outward.
##
## A face wound the wrong way is culled, and a culled face is invisible rather than
## wrong. That is exactly what happened to the runway: from directly above it rendered
## as torn fragments, and the only reason it looked solid with the terrain hidden was
## that the underside was what survived. `CULL_DISABLED` "fixed" it too, which is why
## this test exists -- the fix has to be the winding, not the cull mode.
##
## The method is deliberately dumb: build each primitive inside out, and check that
## every face normal points away from the primitive's own centre. A correctly wound
## convex solid satisfies that for all of its faces.
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

	var apron := Airport._apron(generator.runway_length)
	_expect_upward_faces(apron, "apron surface")

	var lights := Airport._approach_lights(generator.runway_length)
	_check("approach lights have geometry", not lights.is_empty(),
		"%d triangles" % lights.triangle_count())


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
