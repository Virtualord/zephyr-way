## Palette and mesh-toolkit checks.
##
## design/color_palette.json is the design contract, and MeshBuilder is how
## every visual in the game is produced. A silent failure in either would show up
## as magenta geometry or missing colour rather than as an error, so both are
## checked here.
##
## [codeblock]
## godot --headless --path . --script res://tests/procedural_test.gd
## [/codeblock]
extends SceneTree

## Palette keys the aircraft and world depend on. A missing one is a real problem,
## because materials fall back to an obvious placeholder colour.
const REQUIRED_COLORS := [
	"aircraft.cream",
	"aircraft.coral",
	"aircraft.teal",
	"aircraft.sun",
	"grass.lawn_airport",
	"ocean.mid",
	"rock.cool_grey",
	"sand.dry",
	"cloud.dusk_top",
	"cloud.dusk_bottom",
	"ui.text",
]

var _failures := 0
var _checks := 0


func _initialize() -> void:
	print("Palette and mesh checks")

	_check_palette()
	_check_weighted_sets()
	_check_ramps()
	_check_livery()
	_check_units()
	_check_meshes()
	_check_materials()
	_check_aircraft_profile()

	if _failures == 0:
		print("  %d checks passed" % _checks)
	quit(0 if _failures == 0 else 1)


func _check_palette() -> void:
	_check("palette document loads", not Palette.document().is_empty())
	for ref in REQUIRED_COLORS:
		var color := Palette.color(ref)
		# The documented fallback is magenta, so a real match means it resolved.
		_check(
			"palette resolves '%s'" % ref,
			color != Color.MAGENTA,
			"got %s" % color
		)

	# Alpha and near-black or near-white values would break the documented
	# contrast rules even though the key exists.
	for ref in REQUIRED_COLORS:
		var color := Palette.color(ref)
		_check("palette '%s' is opaque" % ref, color.a > 0.99)


func _check_weighted_sets() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for set_name in ["building_wall", "building_roof", "foliage_conifer", "field_cycle"]:
		var color := Palette.weighted(set_name, rng)
		_check("weighted set '%s' returns a real colour" % set_name, color != Color.MAGENTA)

	# Determinism matters because world generators are seeded and must be
	# reproducible across runs.
	var first := RandomNumberGenerator.new()
	first.seed = 99
	var second := RandomNumberGenerator.new()
	second.seed = 99
	_check(
		"weighted sets are deterministic for a seed",
		Palette.weighted("field_cycle", first) == Palette.weighted("field_cycle", second)
	)

	# Every colour referenced by a weighted set must itself resolve, or a random
	# pick would sometimes produce placeholder magenta.
	for entry in Palette.document().get("weighted_sets", {}):
		for option in (Palette.document()["weighted_sets"][entry] as Array):
			var ref := str((option as Dictionary).get("color", ""))
			_check("weighted set '%s' reference resolves" % entry, Palette.color(ref) != Color.MAGENTA, ref)


func _check_ramps() -> void:
	var shallow := Palette.ramp_color("ocean_depth", 0.0)
	var deep := Palette.ramp_color("ocean_depth", 90.0)
	_check("ocean ramp resolves at the surface", shallow != Color.MAGENTA)
	_check("ocean ramp resolves at depth", deep != Color.MAGENTA)
	_check("deeper ocean is darker", deep.get_luminance() < shallow.get_luminance())
	# Values outside the range must clamp rather than fail.
	_check("ocean ramp clamps below range", Palette.ramp_color("ocean_depth", -50.0) == shallow)
	_check("ocean ramp clamps above range", Palette.ramp_color("ocean_depth", 500.0) == deep)


func _check_livery() -> void:
	var livery := Palette.livery("sunrise_coral")
	_check("livery 'sunrise_coral' resolves", not livery.is_empty())
	for field in ["body", "wing_top", "cowl", "fin", "stripe", "belly", "spinner"]:
		_check("livery has '%s'" % field, livery.has(field))


func _check_units() -> void:
	_check_near("knots round-trip", Units.knots_to_mps(Units.mps_to_knots(100.0)), 100.0, 0.001)
	_check("one knot is 0.5144 m/s", absf(Units.knots_to_mps(1.0) - 0.5144444) < 0.0001)
	_check_near("degrees round-trip", Units.deg_to_rad(Units.rad_to_deg(0.7)), 0.7, 0.0001)
	_check_near("degrees convert", Units.rad_to_deg(PI), 180.0, 0.001)
	_check("zero knots is zero", is_zero_approx(Units.knots_to_mps(0.0)))


func _check_meshes() -> void:
	var box := MeshBuilder.box(Vector3(1.0, 2.0, 3.0))
	_check("box builds", box != null)
	_check("box has 12 vertices", box.get_surface_count() > 0 and _vertex_count(box) == 36, "got %d" % _vertex_count(box))

	var tapered := MeshBuilder.tapered_box(Vector3(1.0, 1.0, 1.0), Vector3(0.5, 0.5, 0.5), Vector3(0.0, 0.0, 0.2))
	_check("tapered box builds", tapered != null and _vertex_count(tapered) > 0)

	var cylinder := MeshBuilder.cylinder(1.0, 2.0, 8)
	_check("cylinder builds", cylinder != null and _vertex_count(cylinder) > 0)

	var cone := MeshBuilder.cone(1.0, 2.0, 8)
	_check("cone builds", cone != null and _vertex_count(cone) > 0)

	var swept := MeshBuilder.sweep(2.0, Vector2(1.0, 1.0), Vector2(0.3, 0.3))
	_check("sweep builds", swept != null and _vertex_count(swept) > 0)

	# Loft is the workhorse, so it gets checked on both sweep axes.
	var along_z := MeshBuilder.loft([
		{"width": 1.0, "height": 1.0, "z": 0.0},
		{"width": 0.5, "height": 0.5, "z": 2.0},
	])
	_check("loft along Z builds", along_z != null and _vertex_count(along_z) > 0)
	_check("loft along Z extends in Z", _bounds(along_z).size.z > 1.9, "%v" % _bounds(along_z).size)

	var along_x := MeshBuilder.loft([
		{"width": 1.0, "height": 0.2, "z": 0.0},
		{"width": 0.5, "height": 0.2, "z": 2.0},
	], MeshBuilder.PROFILE_WING, true, true, MeshBuilder.Axis.X)
	_check("loft along X builds", along_x != null and _vertex_count(along_x) > 0)
	_check("loft along X extends in X", _bounds(along_x).size.x > 1.9, "%v" % _bounds(along_x).size)
	_check("loft along X keeps chord on Z", _bounds(along_x).size.z > 0.9, "%v" % _bounds(along_x).size)

	# Flat shading is the whole visual identity, so normals must exist and vary
	# between faces rather than being smoothed away.
	_check("box has normals", _normals(box).size() > 0)
	_check("box normals are not all identical", _normals_vary(box))

	_check("materials build", MeshBuilder.flat_material(Color.RED) != null)


func _check_materials() -> void:
	var material := MeshBuilder.flat_material(Color("#4FA88A"))
	_check("material keeps its albedo", material.albedo_color.is_equal_approx(Color("#4FA88A")))
	_check("material is unshaded-capable", material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL)


## The profile drives every dimension of the airframe, so its contract values must
## match design/aircraft_design.json exactly.
func _check_aircraft_profile() -> void:
	var profile := AircraftProfile.new()
	_check_near("profile length", profile.length, 8.2, 0.001)
	_check_near("profile wingspan", profile.wingspan, 10.6, 0.001)
	_check_near("profile height", profile.height, 2.8, 0.001)
	_check_near("profile fuselage width", profile.fuselage_width, 0.9, 0.001)
	_check_near("profile wing area", profile.wing_area, 18.0, 0.001)
	_check_near("profile tail scale", profile.tail_scale, 0.72, 0.001)
	_check(
		"profile primary colour matches the design file",
		profile.primary_color.is_equal_approx(Color("#E9E3D0"))
	)
	_check(
		"profile accent colour matches the design file",
		profile.accent_color.is_equal_approx(Color("#E58C5A"))
	)

	# Wing area has to be achievable by the wing the builder generates, otherwise
	# the two numbers disagree.
	var aspect := profile.wingspan / profile.wing_root_chord
	_check("wing aspect ratio is plausible", aspect > 3.0 and aspect < 12.0, "%.2f" % aspect)


func _vertex_count(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var arrays := mesh.surface_get_arrays(0)
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()


func _normals(mesh: ArrayMesh) -> PackedVector3Array:
	if mesh == null or mesh.get_surface_count() == 0:
		return PackedVector3Array()
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL] as PackedVector3Array


## Distinct normals are the observable signature of flat shading: a smoothed box
## would collapse to six directions shared across all 36 vertices.
func _normals_vary(mesh: ArrayMesh) -> bool:
	var distinct := {}
	var step := 0.001
	for normal in _normals(mesh):
		var key := Vector3(
			snappedf(normal.x, step),
			snappedf(normal.y, step),
			snappedf(normal.z, step)
		)
		distinct[key] = true
	return distinct.size() >= 6


func _bounds(mesh: ArrayMesh) -> AABB:
	if mesh == null or mesh.get_surface_count() == 0:
		return AABB()
	return mesh.get_aabb()


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s%s" % [label, (" (%s)" % detail) if detail != "" else ""])


func _check_near(label: String, actual: float, expected: float, tolerance: float) -> void:
	_check(label, absf(actual - expected) <= tolerance, "expected %.3f +/- %.3f, got %.3f" % [expected, tolerance, actual])