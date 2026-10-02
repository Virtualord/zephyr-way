## The island's landmark: a coastal lighthouse, at the design file's position.
##
## Built from primitives in code, per the project's procedural-art rule. Position comes
## from `design/world_design.json`, read through the generator so the design file stays
## the single source rather than being duplicated here.
##
## The lighthouse is the island's one piece of pure verticality. Everything else is
## terrain, and terrain seen from the air is mostly area rather than shape, so the only
## thing that reads instantly at any distance is something tall and thin. That drives
## every choice below: the tower is 42 m on a 32 m headland, the bands are high
## contrast against the sky, and the lantern is emissive so it is visible at dusk when
## the tower itself has gone the same colour as the rock behind it.
##
## Sits on the terrain rather than on a flattened pad. The site is a headland the
## terrain generator already produced, and levelling it would be more work than reading
## the ground height under the footprint and dropping the base a little into it.
class_name Lighthouse
extends RefCounted

## Height of the tower shaft alone, in metres, from the base ring to the gallery.
const TOWER_HEIGHT := 32.0
## Radius at the base and at the gallery. Kept nearly straight: a lighthouse that
## tapers to a point reads as a spire, and this is a building.
const BASE_RADIUS := 6.5
const TOP_RADIUS := 4.6
## Bands painted around the shaft. Three, which is the fewest that still reads as
## banded from the air.
const BANDS := 3
## Radius of the gallery platform that rings the lantern.
const GALLERY_RADIUS := 6.2
## Height and radius of the glazed lantern room.
const LANTERN_HEIGHT := 4.2
const LANTERN_RADIUS := 3.4
## How far below the sampled ground the tower's base is sunk.
##
## Enough to guarantee no gap on a slope, small enough that the building does not
## appear to be pushed into the hill. A metre and a half reads as a plinth from any
## distance that matters.
const BASE_SINK := 1.5


## Where the design puts it, and how high the ground is there.
##
## [param generator] is the terrain, so the structure can sit on the real surface
## rather than on a guess written into a scene file.
static func site(generator: TerrainGenerator) -> Transform3D:
	var position := design_position(generator)
	var ground := generator.height_at(position.x, position.y)
	var heading := Units.deg_to_rad(_facing_degrees(generator, position))
	return Transform3D(
		Basis.looking_at(Vector3(sin(heading), 0.0, -cos(heading)), Vector3.UP),
		Vector3(position.x, ground - BASE_SINK, position.y)
	)


## The design's landmark position.
##
## Read through the generator, which carries it as an export alongside the airport
## fields, rather than hard-coded here -- so moving the landmark moves the building.
static func design_position(generator: TerrainGenerator) -> Vector2:
	return generator.lighthouse_position


## Which way the tower faces.
##
## Seaward, so the lantern and the gallery face the open water rather than the
## hillside. A lighthouse pointing inland is the sort of thing that is invisible from
## the approach it exists for.
static func _facing_degrees(generator: TerrainGenerator, at: Vector2) -> float:
	var outward := Vector2.ZERO
	for i in 12:
		var bearing := TAU * float(i) / 12.0
		var direction := Vector2(cos(bearing), sin(bearing))
		if _distance_to_sea(generator, at, direction) > outward.length():
			outward = direction
	# looking_at takes a direction whose -Z is the facing axis.
	return rad_to_deg(atan2(outward.x, -outward.y))


## How far the ground stays above sea level along a bearing, in metres.
static func _distance_to_sea(
	generator: TerrainGenerator, at: Vector2, direction: Vector2
) -> float:
	var step := 20.0
	while step < 2600.0:
		if generator.height_at(at.x + direction.x * step, at.y + direction.y * step) <= 0.0:
			break
		step += 20.0
	return step


## Build the lighthouse. Returns a node holding the merged meshes, positioned on the
## ground.
static func build(generator: TerrainGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Lighthouse"
	root.transform = site(generator)

	var body := StructureBuilder.new()
	_tower(body)
	_keeper_house(body)
	var body_mesh := StructureBuilder.to_mesh_instance("Tower", body)
	if body_mesh != null:
		root.add_child(body_mesh)

	var lamp := StructureBuilder.new()
	_lamp(lamp)
	var lamp_mesh := StructureBuilder.to_mesh_instance("Lantern", lamp)
	if lamp_mesh != null:
		lamp_mesh.material_override = _lantern_material()
		root.add_child(lamp_mesh)

	return root


## The lantern's glass and lamp, kept out of the body mesh.
##
## It needs a different material -- emissive, and unaffected by fog in the way the
## tower's is -- so it cannot be merged with everything else. That is the one place in
## the project where a second draw call is spent on purpose.
static func _lantern_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Palette.color("accent.lamp_warm")
	mat.emission_energy_multiplier = 2.4
	mat.roughness = 0.4
	mat.metallic = 0.0
	return mat


## The tower: banded shaft, gallery, lantern housing and its roof.
static func _tower(builder: StructureBuilder) -> void:
	var coral := Palette.color("building.wall_coral")
	var cream := Palette.color("building.wall_white")
	var metal := Palette.color("building.metal_dark")
	var trim := Palette.color("building.trim")

	# Banded shaft. Each band is its own short tapered cylinder rather than one long
	# one with a texture, which is why the whole tower is a few hundred triangles and
	# needs no material beyond the shared one.
	var band_height := TOWER_HEIGHT / float(BANDS)
	for band in BANDS:
		var y := float(band) * band_height
		var t0 := float(band) / float(BANDS)
		var t1 := float(band + 1) / float(BANDS)
		builder.cylinder(
			Transform3D(Basis.IDENTITY, Vector3(0.0, y, 0.0)),
			lerpf(BASE_RADIUS, TOP_RADIUS, t0),
			lerpf(BASE_RADIUS, TOP_RADIUS, t1),
			band_height,
			coral if band % 2 == 0 else cream,
			8, false, band == 0
		)

	# Gallery: a wider ring the lantern sits on. Its overhang is what casts the
	# lighthouse's one hard horizontal line in a silhouette.
	builder.cylinder(
		Transform3D(Basis.IDENTITY, Vector3(0.0, TOWER_HEIGHT, 0.0)),
		GALLERY_RADIUS, GALLERY_RADIUS, 0.9, metal, 8, true, false
	)
	# Railing, as a short band above the gallery floor.
	builder.cylinder(
		Transform3D(Basis.IDENTITY, Vector3(0.0, TOWER_HEIGHT + 0.9, 0.0)),
		GALLERY_RADIUS - 0.2, GALLERY_RADIUS - 0.2, 1.3, trim, 8, true, false
	)

	# Lantern housing. In the body mesh rather than the lamp mesh because it is opaque
	# structure; only the glass and the bulb need to emit.
	builder.cylinder(
		Transform3D(Basis.IDENTITY, Vector3(0.0, TOWER_HEIGHT + 2.2, 0.0)),
		LANTERN_RADIUS, LANTERN_RADIUS, LANTERN_HEIGHT, trim, 8, false, false
	)
	# Roof cone, and a finial so the top is a point rather than a flat disc.
	builder.cone(
		Transform3D(Basis.IDENTITY, Vector3(0.0, TOWER_HEIGHT + 2.2 + LANTERN_HEIGHT, 0.0)),
		LANTERN_RADIUS + 0.7, 3.6, metal, 8
	)
	builder.box(
		Transform3D(Basis.IDENTITY,
			Vector3(0.0, TOWER_HEIGHT + 2.2 + LANTERN_HEIGHT + 3.6, 0.0)),
		Vector3(0.5, 2.4, 0.5), trim
	)


## The lantern glass and the lamp inside it.
static func _lamp(builder: StructureBuilder) -> void:
	var glass := Palette.color("accent.lamp_cool")
	var flame := Palette.color("accent.lamp_warm")
	var y := TOWER_HEIGHT + 2.2
	# Glass band, inset slightly so the housing frames it.
	builder.cylinder(
		Transform3D(Basis.IDENTITY, Vector3(0.0, y + 0.5, 0.0)),
		LANTERN_RADIUS - 0.35, LANTERN_RADIUS - 0.35, LANTERN_HEIGHT - 1.0, glass, 8, false, false
	)
	# The lamp itself.
	builder.cone(
		Transform3D(Basis.IDENTITY, Vector3(0.0, y + 1.1, 0.0)),
		1.9, 2.2, flame, 8
	)


## The keeper's cottage, set back and to one side.
##
## Small, low, and a different colour from the tower. Without it the lighthouse is a
## lone stick on a rock; with it there is something at the base that gives the eye a
## scale reference, which is what makes the tower read as tall.
static func _keeper_house(builder: StructureBuilder) -> void:
	var stone := Palette.color("building.wall_stone")
	var slate := Palette.color("building.roof_slate")
	var wood := Palette.color("building.wood_dark")

	# Offset in runway-independent local space: to the left of the tower and slightly
	# behind, so it is not hidden behind the shaft from the seaward approach.
	var at := Vector3(-17.0, 0.0, -9.0)
	builder.box(Transform3D(Basis.IDENTITY, at + Vector3(0.0, 3.4, 0.0)),
		Vector3(15.0, 6.8, 11.0), stone)
	builder.gable_roof(Basis.IDENTITY, at + Vector3(0.0, 6.8, 0.0),
		Vector2(15.0, 11.0), 4.2, 1.0, slate)
	builder.box(Transform3D(Basis.IDENTITY, at + Vector3(0.0, 1.4, 5.6)),
		Vector3(1.6, 2.8, 0.5), wood)

	# A low boundary wall, which is what makes the site read as a place rather than as
	# two objects that happen to be near each other.
	for offset in [Vector3(0.0, 0.0, 13.0), Vector3(13.0, 0.0, 6.0), Vector3(-13.0, 0.0, 6.0)]:
		builder.box(
			Transform3D(Basis.IDENTITY, at + offset + Vector3(0.0, 0.7, 0.0)),
			Vector3(20.0, 1.4, 1.0), stone
		)
