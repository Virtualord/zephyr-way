## The island's airport: runway, apron, and the buildings beside it.
##
## Built entirely in code from primitives, per the project's procedural-art rule. The
## position, heading and length come from `design/world_design.json` and are read off
## the generator rather than duplicated, so the design file stays the single source.
##
## Everything is merged into a handful of meshes by [StructureBuilder] and placed on
## the flattened plateau the terrain already reserves, at its elevation. Nothing here
## samples the terrain for its own height: the plateau is flat to within a rounding
## error by construction, and sampling per-building would put a hangar on a slope the
## runway is not on.
##
## Read from the air, the shapes are chosen to be legible at a glance rather than
## detailed: a long dark strip with bright threshold bars, one apron's worth of pale
## concrete, and two roofs in warm colours that are the only saturated things on a
## green plateau.
class_name Airport
extends RefCounted

## Width of the runway surface. Not in the design file; chosen to read as a runway at
## the altitude this island is flown at. A real 850 m runway is 30-45 m wide, so this
## is in range rather than a stylisation.
const WIDTH := 46.0

## Widths of the painted markings.
##
## Deliberately several times life size. At true scale a centreline is under a metre
## wide, which from a few hundred metres up is a couple of pixels and reads as bare
## asphalt; these are sized to be legible at the altitude this island is actually
## flown at, which is the milestone's stated priority. A runway that is invisible from
## the air is not a runway as far as this game is concerned.
const CENTRELINE_WIDTH := 3.4
const EDGE_LINE_WIDTH := 2.4
const THRESHOLD_BAR_WIDTH := 5.0
const AIM_POINT_WIDTH := 4.4

## How far the paved surface stands above the plateau.
##
## Enough to have a visible edge from a low approach, small enough that the aircraft
## does not have to climb a step off it.
const PAVEMENT_LIFT := 0.35

## How far the painted markings stand above the paved surface.
##
## They have to be off it. At the same height they are coplanar with the slab, and
## coplanar faces z-fight: from the air the runway came out as bare asphalt with a
## few stray hairlines where the stripes happened to win the depth test. Six
## centimetres is far more than the depth buffer's resolution at any range this
## island is seen from, and far too little to notice as a step from the ground.
const MARKING_LIFT := 0.06

## Side of the runway the apron and buildings sit on, in runway-local +X.
const APRON_SIDE := 1.0

## Local transform of the whole airport: origin at the design position on the
## plateau, with -Z pointing down the runway the way the aircraft starts.
static func transform(generator: TerrainGenerator) -> Transform3D:
	var heading := Units.deg_to_rad(generator.airport_heading_degrees)
	var forward := Vector3(sin(heading), 0.0, -cos(heading))
	return Transform3D(
		Basis.looking_at(forward, Vector3.UP),
		Vector3(generator.airport_position.x, generator.airport_elevation, generator.airport_position.y)
	)


## Build the airport. Returns a node holding the merged meshes, already positioned.
static func build(generator: TerrainGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Airport"

	var xform := transform(generator)
	var length: float = generator.runway_length

	_add(root, "Runway", _runway(length))
	_add(root, "Apron", _apron(length))
	_add(root, "Buildings", _buildings(length))
	_add(root, "ApproachLights", _approach_lights(length))

	root.transform = xform
	return root


static func _add(parent: Node, node_name: String, builder: StructureBuilder) -> void:
	var instance := StructureBuilder.to_mesh_instance(node_name, builder)
	if instance != null:
		parent.add_child(instance)


## Runway surface and its markings, all in one mesh.
##
## The markings are separate quads lying a few centimetres above the surface rather
## than being part of it. That is a z-fighting risk in principle; it is not one in
## practice because the lift is far larger than the depth buffer's resolution at this
## range, and because the alternative -- building the markings as holes in the slab --
## would need several times the triangles for no visible gain.
static func _runway(length: float) -> StructureBuilder:
	var builder := StructureBuilder.new()
	var surface := Palette.color("road.runway")
	var stripe := Palette.color("road.runway_stripe")

	_paint_slab(builder, length, surface)

	# Centreline: dashes rather than a continuous line, which is both what real
	# runways have and what stops the strip reading as a plain grey rectangle.
	var dash := 26.0
	var gap := 22.0
	var travelled := -length * 0.5 + 120.0
	while travelled < length * 0.5 - 120.0:
		_strip(builder, Vector2(CENTRELINE_WIDTH, dash),
			Vector3(0.0, PAVEMENT_LIFT + MARKING_LIFT, travelled), stripe)
		travelled += dash + gap

	# Edge lines, continuous and inset from the slab edge.
	for side: float in [-1.0, 1.0]:
		_strip(
			builder, Vector2(EDGE_LINE_WIDTH, length),
			Vector3(side * (WIDTH * 0.5 - 3.4), PAVEMENT_LIFT + MARKING_LIFT, 0.0), stripe
		)

	# Threshold bars: six per end, the classic piano keyboard. Mirrored at both ends
	# so the runway reads the same whichever way it is approached.
	for end_sign: float in [-1.0, 1.0]:
		for bar in 6:
			var offset := (float(bar) - 2.5) * 7.2
			_strip(
				builder, Vector2(THRESHOLD_BAR_WIDTH, 30.0),
				Vector3(offset, PAVEMENT_LIFT + MARKING_LIFT, end_sign * (length * 0.5 - 34.0)), stripe
			)
		# Aim point markers, a pair of bars a third of the way in from the threshold.
		for side: float in [-1.0, 1.0]:
			_strip(
				builder, Vector2(AIM_POINT_WIDTH, 42.0),
				Vector3(side * 11.0, PAVEMENT_LIFT + MARKING_LIFT, end_sign * (length * 0.5 - 130.0)), stripe
			)

	return builder


## The runway slab.
##
## Divided into segments along its length rather than drawn as one pair of triangles.
## A 46 x 850 m quad is two enormous slivers, and that is a bad surface to hand a
## rasteriser: the runway came out torn along terrain triangle edges over most of its
## length while the apron beside it, at exactly the same height and built the same way,
## rendered solid. Subdividing costs a few hundred triangles and removes the shape from
## the question entirely.
const SLAB_SEGMENTS := 24


static func _paint_slab(builder: StructureBuilder, length: float, color: Color) -> void:
	var half_w := WIDTH * 0.5
	var segment := length / float(SLAB_SEGMENTS)
	for i in SLAB_SEGMENTS:
		var z0 := -length * 0.5 + float(i) * segment
		var z1 := z0 + segment
		# Top, wound so the normal points up.
		builder.quad(
			Vector3(-half_w, PAVEMENT_LIFT, z0), Vector3(-half_w, PAVEMENT_LIFT, z1),
			Vector3(half_w, PAVEMENT_LIFT, z1), Vector3(half_w, PAVEMENT_LIFT, z0), color
		)
		# Bottom, the other way round.
		builder.quad(
			Vector3(-half_w, 0.0, z0), Vector3(half_w, 0.0, z0),
			Vector3(half_w, 0.0, z1), Vector3(-half_w, 0.0, z1), color
		)
	# Only the two long sides and the two ends need their own faces; every interior
	# segment boundary is shared and would be interior geometry.
	builder.quad(
		Vector3(-half_w, 0.0, -length * 0.5), Vector3(-half_w, PAVEMENT_LIFT, -length * 0.5),
		Vector3(half_w, PAVEMENT_LIFT, -length * 0.5), Vector3(half_w, 0.0, -length * 0.5), color
	)
	builder.quad(
		Vector3(-half_w, 0.0, length * 0.5), Vector3(half_w, 0.0, length * 0.5),
		Vector3(half_w, PAVEMENT_LIFT, length * 0.5), Vector3(-half_w, PAVEMENT_LIFT, length * 0.5),
		color
	)
	for side: float in [-1.0, 1.0]:
		var x := side * half_w
		builder.quad(
			Vector3(x, 0.0, -length * 0.5), Vector3(x, 0.0, length * 0.5),
			Vector3(x, PAVEMENT_LIFT, length * 0.5), Vector3(x, PAVEMENT_LIFT, -length * 0.5),
			color
		)


## One painted rectangle on the runway, given its size and centre in runway-local
## coordinates. X is across the runway, Z is along it.
static func _strip(
	builder: StructureBuilder, size_xz: Vector2, at: Vector3, color: Color
) -> void:
	var h := Vector3(size_xz.x, 0.0, size_xz.y) * 0.5
	var y := at.y
	var x := at.x
	var z := at.z
	# Wound so the normal points up.
	builder.quad(
		Vector3(x - h.x, y, z - h.z), Vector3(x - h.x, y, z + h.z),
		Vector3(x + h.x, y, z + h.z), Vector3(x + h.x, y, z - h.z), color
	)


## Apron and the taxiway linking it to the runway.
##
## Placed beside the runway rather than at its end: an apron at the threshold would
## sit in the approach path, and the point of this milestone is a readable silhouette,
## not a working airport layout.
## How far along the runway the apron sits, measured back from the near threshold.
##
## Named because the buildings need it too and hard-coding it in two places is how a
## hangar ends up standing on grass.
static func _apron_offset(length: float) -> float:
	return length * 0.5 - 200.0


static func _apron(length: float) -> StructureBuilder:
	var builder := StructureBuilder.new()
	var apron_color := Palette.color("road.apron")
	var side := APRON_SIDE
	var centre_x := side * (WIDTH * 0.5 + 78.0)
	var centre_z := -length * 0.5 + 200.0

	_apron_slab(builder, Vector2(150.0, 210.0), Vector3(centre_x, 0.0, centre_z), apron_color)

	# Taxiway: a strip from the apron edge to the runway edge, level with the apron.
	var taxi_width := 26.0
	var from_x := centre_x - side * 75.0
	var to_x := side * (WIDTH * 0.5 + 1.0)
	_apron_slab(
		builder, Vector2(absf(from_x - to_x), taxi_width),
		Vector3((from_x + to_x) * 0.5, 0.0, centre_z), apron_color
	)
	return builder


## A flat paved rectangle at the ground lift, with a thin edge so it is not a decal.
static func _apron_slab(
	builder: StructureBuilder, size_xz: Vector2, at: Vector3, color: Color
) -> void:
	var half := Vector3(size_xz.x, PAVEMENT_LIFT, size_xz.y) * 0.5
	var x := at.x
	var z := at.z
	var top := at.y + PAVEMENT_LIFT
	var bottom := at.y
	builder.quad(
		Vector3(x - half.x, top, z - half.z), Vector3(x - half.x, top, z + half.z),
		Vector3(x + half.x, top, z + half.z), Vector3(x + half.x, top, z - half.z), color
	)
	builder.quad(
		Vector3(x - half.x, bottom, z - half.z), Vector3(x + half.x, bottom, z - half.z),
		Vector3(x + half.x, bottom, z + half.z), Vector3(x - half.x, bottom, z + half.z), color
	)
	for side_x: float in [-1.0, 1.0]:
		var sx := side_x * half.x
		builder.quad(
			Vector3(x + sx, bottom, z - half.z), Vector3(x + sx, bottom, z + half.z),
			Vector3(x + sx, top, z + half.z), Vector3(x + sx, top, z - half.z), color
		)
	for side_z: float in [-1.0, 1.0]:
		var sz := side_z * half.z
		builder.quad(
			Vector3(x - half.x, bottom, z + sz), Vector3(x + half.x, bottom, z + sz),
			Vector3(x + half.x, top, z + sz), Vector3(x - half.x, top, z + sz), color
		)


## Terminal and hangar.
##
## The roofs are the point. From the air these are the only saturated colours on the
## plateau, so they are what tells a player where the airport is before the runway
## itself resolves.
static func _buildings(length: float) -> StructureBuilder:
	var builder := StructureBuilder.new()
	var side := APRON_SIDE
	# The apron the buildings stand on. Read rather than recomputed, so moving the
	# apron cannot quietly leave a hangar hanging off its edge.
	var centre_z := -_apron_offset(length)

	var cream := Palette.color("building.wall_cream")
	var terracotta := Palette.color("building.roof_terracotta")
	var slate := Palette.color("building.roof_slate")
	var trim := Palette.color("building.trim")
	var glass := Palette.color("building.window_day")

	# Terminal: a long low block with a glazed face toward the apron and a pitched roof.
	var terminal_at := Vector3(side * 118.0, PAVEMENT_LIFT, centre_z)
	var terminal_size := Vector3(34.0, 13.0, 86.0)
	builder.box(Transform3D(Basis.IDENTITY, terminal_at + Vector3(0.0, terminal_size.y * 0.5, 0.0)),
		terminal_size, cream)
	# Glazed face, inset on the apron side, which is the side the player sees first.
	builder.box(
		Transform3D(Basis.IDENTITY,
			terminal_at + Vector3(-side * (terminal_size.x * 0.5 + 0.2), 6.0, 0.0)),
		Vector3(1.0, 7.5, 74.0), glass
	)
	builder.gable_roof(
		Basis.IDENTITY, terminal_at + Vector3(0.0, terminal_size.y, 0.0),
		Vector2(terminal_size.x, terminal_size.z), 7.0, 2.5, terracotta
	)

	# Hangar: wider, taller, and a darker roof so the two do not read as one blob.
	var hangar_at := Vector3(side * 140.0, PAVEMENT_LIFT, centre_z + 74.0)
	var hangar_size := Vector3(56.0, 17.0, 62.0)
	builder.box(Transform3D(Basis.IDENTITY, hangar_at + Vector3(0.0, hangar_size.y * 0.5, 0.0)),
		hangar_size, cream)
	# Door band: the hangar's opening, the one dark rectangle that says "hangar".
	builder.box(
		Transform3D(Basis.IDENTITY, hangar_at + Vector3(-side * (hangar_size.x * 0.5 + 0.3), 7.0, 0.0)),
		Vector3(1.0, 13.0, 40.0), Palette.color("road.asphalt")
	)
	builder.gable_roof(
		Basis.IDENTITY, hangar_at + Vector3(0.0, hangar_size.y, 0.0),
		Vector2(hangar_size.x, hangar_size.z), 9.0, 3.0, slate
	)

	# A control tower, tall and thin. Its job is vertical: on a flat plateau it is the
	# only thing that marks the airport from a distance or a low pass.
	var tower_at := Vector3(side * 96.0, PAVEMENT_LIFT, centre_z - 84.0)
	builder.box(
		Transform3D(Basis.IDENTITY, tower_at + Vector3(0.0, 13.0, 0.0)),
		Vector3(9.0, 26.0, 9.0), cream
	)
	builder.box(
		Transform3D(Basis.IDENTITY, tower_at + Vector3(0.0, 29.5, 0.0)),
		Vector3(14.0, 8.0, 14.0), glass
	)
	builder.box(
		Transform3D(Basis.IDENTITY, tower_at + Vector3(0.0, 34.5, 0.0)),
		Vector3(16.0, 2.5, 16.0), trim
	)
	builder.cone(
		Transform3D(Basis.IDENTITY, tower_at + Vector3(0.0, 35.8, 0.0)),
		7.0, 6.0, terracotta, 8
	)
	return builder


## Approach light masts along both extended centrelines.
##
## Small, but they are what gives the runway a direction at dusk and they read as a
## dotted line converging on the threshold from the air.
static func _approach_lights(length: float) -> StructureBuilder:
	var builder := StructureBuilder.new()
	var mast := Palette.color("building.metal")
	var lamp := Palette.color("accent.lamp_warm")

	# Kept inside the plateau. The runway's half-length is 425 m and the plateau's
	# radius is 500 m, so there are only 75 m of flat ground beyond each threshold;
	# running the lights out to 605 m put them on the blend, hanging in the air.
	for end_sign: float in [-1.0, 1.0]:
		var travelled := length * 0.5 + 20.0
		while travelled < length * 0.5 + 68.0:
			for side: float in [-1.0, 1.0]:
				var at := Vector3(side * (WIDTH * 0.5 + 4.0), 0.0, end_sign * travelled)
				# Mast.
				builder.box(
					Transform3D(Basis.IDENTITY, at + Vector3(0.0, 1.6, 0.0)),
					Vector3(0.7, 3.2, 0.7), mast
				)
				# Lamp head.
				builder.box(
					Transform3D(Basis.IDENTITY, at + Vector3(0.0, 3.6, 0.0)),
					Vector3(1.3, 1.0, 1.3), lamp
				)
			travelled += 18.0
	return builder
