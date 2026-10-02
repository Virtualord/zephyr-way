## The island scene: terrain mesh, shoreline and sea.
##
## Replaces the flat test environment as the world's height authority. It exposes
## the same [code]ground_height_at()[/code] the aircraft already samples, so the
## flight model needs no change at all to fly over real terrain — which was the
## reason for putting terrain behind that one function.
##
## Generation is chunked and seeded. Chunks are built on demand as the aircraft
## approaches, so starting the game does not pay for the whole island.
class_name Island
extends Node3D

## Seed for the terrain. The same seed always produces the same island.
@export var terrain_seed := 20261

## Distance in metres within which chunks are built at full detail.
@export_range(200.0, 4000.0, 50.0) var detail_distance := 1100.0

## How far the sea plane reaches, in multiples of the island radius.
##
## The sea has to reach the edge of the built terrain, not merely the shoreline.
## Everything outside the chunk grid is absent geometry, so a sea plane that stops
## short of it leaves a hard rectangular edge in the world with sky showing through
## behind -- invisible from the ground, where the sea fills the horizon anyway, and
## glaring from the air. Measured: the grid reached 3000 m and the sea plane also
## stopped at 3000 m, and the aerial view showed the island as a slab floating in
## sky.
##
## Beyond the terrain's own edge the seabed keeps going -- `height_at()` returns
## water indefinitely -- so the plane is what has to cover the gap, and it has to be
## generous because it is also the horizon when flying.
@export_range(2.0, 64.0, 0.5) var sea_extent_factor := 24.0
@export var sea_color := Color("#1CA7C6")
@export var sea_deep_color := Color("#0A4F8F")

## Distance at which terrain chunks fade out, in metres.
##
## Must exceed the grid's own half-extent, or chunks disappear while the camera can
## still see them.
@export_range(1000.0, 20000.0, 100.0) var visibility_range := 6000.0

## Chunks built per frame while filling in.
##
## Building the whole island at once takes about a second and freezes the game on
## entry. Spreading it over frames costs a second of partially-drawn terrain, which
## is invisible during a fade-in and far better than a stall.
@export_range(1, 32, 1) var chunks_per_frame := 4

var generator: TerrainGenerator
var builder: TerrainBuilder

var _chunks: Dictionary = {}
var _chunk_root: Node3D
var _sea: MeshInstance3D
var _focus := Vector2.ZERO
## Chunks still to build for the current focus, in build order.
var _pending: Array[Vector2] = []


func _ready() -> void:
	generator = TerrainGenerator.new()
	generator.terrain_seed = terrain_seed
	# The generator builds its noise sources in the constructor, so a seed assigned
	# afterwards must be followed by configure() or it is silently ignored.
	generator.configure()
	builder = TerrainBuilder.new(generator)

	_chunk_root = Node3D.new()
	_chunk_root.name = "Chunks"
	add_child(_chunk_root)

	_build_sea()
	_queue_chunks_around(_focus)


func _process(_delta: float) -> void:
	# Rebuild chunks as the aircraft moves. Cheap when nothing changed, because the
	# desired set is compared before anything is built.
	var aircraft := _find_aircraft()
	if aircraft != null:
		var position := aircraft.global_position
		var focus := Vector2(position.x, position.z)
		if focus.distance_to(_focus) > TerrainBuilder.CHUNK_SIZE * 0.5:
			_focus = focus
			_queue_chunks_around(_focus)

	# Nearest chunks first, so the ground under and around the aircraft appears
	# before the far side of the island.
	_pending.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.distance_squared_to(_focus) < b.distance_squared_to(_focus))

	for _index in mini(chunks_per_frame, _pending.size()):
		_build_chunk(_pending.pop_front(), _focus)


## Terrain height in metres at a world position. This is what [AircraftController]
## samples, so what you see is exactly what you land on.
func ground_height_at(position: Vector3) -> float:
	return generator.height_at(position.x, position.z)


func ground_height_at_2d(x: float, z: float) -> float:
	return generator.height_at(x, z)


## Work out which chunks need building around a focus point, without building them.
##
## Chunks outside the detail radius are kept at low detail rather than removed, so
## the island does not visibly appear as the player approaches.
func _queue_chunks_around(focus: Vector2) -> void:
	_pending.clear()
	for origin in builder.chunk_origins():
		var centre := origin + Vector2.ONE * TerrainBuilder.CHUNK_SIZE * 0.5
		var near := centre.distance_to(focus) < detail_distance

		# A chunk that already exists at this detail needs nothing done. One that
		# exists at the *other* detail is rebuilt at the new one, so approaching the
		# island refines it and leaving goes back to coarse.
		var existing: Node3D = _chunks.get(_key_for(origin, near), null)
		if existing != null:
			if bool(existing.get_meta(&"near", false)) == near:
				continue
			# Wrong detail: drop it and queue a replacement.
			_chunks.erase(_key_for(origin, near))
			existing.queue_free()

		_pending.append(origin)


## Build one chunk and add it to the scene.
func _build_chunk(origin: Vector2, focus: Vector2) -> void:
	var centre := origin + Vector2.ONE * TerrainBuilder.CHUNK_SIZE * 0.5
	var near := centre.distance_to(focus) < detail_distance

	var mesh := builder.build_chunk(origin, near)
	if mesh == null:
		return
	var instance := MeshInstance3D.new()
	instance.name = "Chunk_%d_%d" % [int(origin.x), int(origin.y)]
	instance.mesh = mesh
	instance.set_meta(&"near", near)
	instance.material_override = _terrain_material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Far chunks fade out rather than being drawn, which is the only way to avoid
	# showing both detail levels of the same ground at once.
	instance.visibility_range_end = visibility_range
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_chunk_root.add_child(instance)
	_chunks[_key_for(origin, near)] = instance


## Key identifying a chunk at a given detail level.
##
## A String, not a hash of the coordinates.
##
## The previous key was `x * 73856093 ^ y * 19349663`, which collides on symmetric
## positions: `(3000, -1000)` and `(-3000, 1000)` both hash to the same value, so
## one chunk silently overwrote another and the build stopped at 246 of 289 with an
## empty queue and no error. Nothing reported it — `built_chunk_count()` was simply
## smaller than the grid, and the missing chunks were holes in the world.
##
## A string key cannot collide, and the cost is irrelevant at this scale: it is
## computed a few hundred times when the focus moves.
func _key_for(origin: Vector2, near: bool) -> String:
	return "%d_%d_%s" % [int(origin.x), int(origin.y), "n" if near else "f"]


## Shared terrain material.
##
## Vertex colours carry the biome, so this only needs to read them as albedo. Shaded
## rather than unshaded, so the sun still models the terrain's relief — that shading
## is most of what makes the mountains read as mountains rather than as coloured
## cardboard.
func _terrain_material() -> StandardMaterial3D:
	if _terrain_material_cache != null:
		return _terrain_material_cache
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.94
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_terrain_material_cache = material
	return material


var _terrain_material_cache: StandardMaterial3D


## Flat sea plane at sea level, carrying the stylized ocean shader.
##
## The shader reads the seabed from a height field the generator produces, so the
## shallows and the foam line follow the real terrain rather than a hand-tuned curve
## that drifts out of step with it.
func _build_sea() -> void:
	# Sized from the island rather than set, so growing the island cannot leave the
	# sea short of the terrain. Subdivided as well, because a 32 km plane built from
	## two triangles has no vertices to bend for a horizon, and its single huge quad
	# is where precision problems show up first.
	# Big enough that its edge is beyond the fog's full density, so the sea reaches the
	# horizon instead of ending in a visible straight line partway to it. At the old
	# extent of 16 km the edge sat about 8 km out, which from a low camera is only a
	# couple of degrees below eye level -- so the boundary was plainly visible as a
	# straight edge across the frame, with the sky showing past it.
	var extent := generator.island_radius * sea_extent_factor
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent, extent)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8

	_sea = MeshInstance3D.new()
	_sea.name = "Sea"
	_sea.mesh = plane
	_sea.material_override = _sea_material()
	_sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sea.position.y = TerrainGenerator.SEA_LEVEL
	add_child(_sea)


## The ocean material, or a flat fallback if the shader is missing.
##
## A missing shader would otherwise leave the sea as a black quad, which is worse than
## an unstyled one, so the failure is reported and a plain material used instead.
func _sea_material() -> Material:
	var shader: Shader = load(OCEAN_SHADER_PATH) as Shader
	if shader == null:
		push_warning("Island: ocean shader not found at %s; using a flat sea." % OCEAN_SHADER_PATH)
		return _flat_sea_material()

	var material := ShaderMaterial.new()
	material.shader = shader
	# Colours come from the palette's own ocean group, which was already in
	# design/color_palette.json and specifies five tones. Two hand-picked colours
	# were being used instead, which is why the sea never matched the art direction.
	material.set_shader_parameter(&"shallow_color", Palette.color("ocean.shallow"))
	material.set_shader_parameter(&"deep_color", Palette.color("ocean.deep"))
	material.set_shader_parameter(&"abyss_color", Palette.color("ocean.abyss"))
	material.set_shader_parameter(&"foam_color", Palette.color("ocean.foam"))
	material.set_shader_parameter(&"edge_color", Palette.color("ocean.wet_edge"))
	material.set_shader_parameter(&"height_field", _height_field())
	material.set_shader_parameter(&"world_extent", height_field_extent)
	material.set_shader_parameter(&"sea_level", TerrainGenerator.SEA_LEVEL)
	material.set_shader_parameter(&"height_range", height_field_range)
	# The ocean's sun sheen needs the sun's direction. Taken from the atmosphere
	# rather than duplicated, so the two cannot drift apart.
	var atmosphere := get_node_or_null(^"Atmosphere") as IslandAtmosphere
	if atmosphere != null:
		material.set_shader_parameter(&"light_direction", atmosphere.sun_direction())
		# The sea is deliberately given some light of its own. Dimming the sun to keep
		# the rock palette correct also dims the water by the same factor, and a sea
		# that darkens with the sun stops reading as sea. Emissive water is a standard
		# stylised-ocean trick: the surface colour stays legible and the sun sheen on top
		# still carries the lighting.
		material.set_shader_parameter(&"self_light", self_light)
	return material


## Seabed heights for the ocean shader to read.
##
## Sampled once at startup from the same generator the terrain uses, so the water's
## idea of the seabed is the terrain's idea of the seabed rather than a second,
## slightly different source that drifts out of step with it.
func _height_field() -> Texture2D:
	if _built_height_field != null:
		return _built_height_field
	var size := HEIGHT_FIELD_SIZE
	# RGBA8 with the height normalised into the green channel, not FORMAT_RF.
	#
	# The single-float-channel version read back as zero on this backend, so every
	# fragment computed maximum depth and the sea came out one flat colour. RGBA8 is
	# portable, costs 65k more texels once at startup, and normalises cleanly: the
	# island's relief is about 800 m from trough to summit, which fits an 8-bit
	# channel at roughly 3 m per step, far finer than the foam band needs.
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var half := height_field_extent * 0.5
	for y in size:
		for x in size:
			# Texel (0,0) is the low corner, matching the uv the shader builds.
			var world_x := (float(x) / float(size - 1) - 0.5) * height_field_extent
			var world_z := (float(y) / float(size - 1) - 0.5) * height_field_extent
			var height := generator.height_at(world_x, world_z)
			# Encoded symmetrically about zero, because the sea is mostly *negative*
			# terrain: the whole seabed sat below the old 0-based encoding and clamped
			# to 0.0, so every fragment computed zero depth, no gradient appeared and no
			# foam was ever in range. The shader divides back out the same way.
			var encoded := clampf(
				height / (2.0 * height_field_range) + 0.5, 0.0, 1.0
			)
			image.set_pixel(x, y, Color(encoded, encoded, encoded, 1.0))
	_built_height_field = ImageTexture.create_from_image(image)
	return _built_height_field


## Resolution of the seabed field handed to the ocean shader, per axis.
##
## 256 is ample: the shader only needs the shape of the shallows, and the foam line is
## tens of metres wide, so one texel every 94 m cannot make it look wrong. It is
## generated once, so the cost is 65k height evaluations at startup.
const HEIGHT_FIELD_SIZE := 256

## World extent the height field covers, in metres, centred on the island.
##
## Sized to the island rather than to the sea plane. At 24000 m -- the width that
## covers the whole sea -- a 256-texel field is 94 m per texel, which is coarser than
## the shoreline the foam is drawn along, so the shallows and the foam arrived as
## blocky rectangles rather than a coastline. At 6000 m the island's full 4 km width
## gets about 170 texels, and the water beyond 3 km out is open sea where the shader
## treats the ground as deep anyway.
@export var height_field_extent := 6000.0

## Range the height field encodes over, in metres. Must comfortably exceed the
## island's relief, since anything above the top of the range is clamped and would
## read as the deepest water rather than as land.
@export var height_field_range := 800.0

## How much of its own colour the water keeps regardless of the sun, 0 to 1.
## See the note where it is passed to the shader.
@export_range(0.0, 1.0, 0.05) var self_light := 0.55

const OCEAN_SHADER_PATH := "res://shaders/ocean.gdshader"

var _built_height_field: Texture2D


## Unstyled water, used only if the shader cannot be loaded.
func _flat_sea_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = sea_color
	material.roughness = 0.12
	material.metallic = 0.25
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.82
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _find_aircraft() -> Node3D:
	# The island is a sibling of the aircraft rather than its parent, so look it up
	# from the scene root once and cache nothing: this runs per frame.
	var root := get_tree().current_scene if is_inside_tree() else null
	if root == null:
		return null
	return root.get_node_or_null(^"Aircraft") as Node3D


## Chunk count, for the profiler.
func built_chunk_count() -> int:
	return _chunks.size()


## Total triangles across built chunks, for the profiler.
func triangle_count() -> int:
	var total := 0
	for chunk in _chunks.values():
		var mesh := (chunk as MeshInstance3D).mesh
		if mesh != null:
			total += _surface_triangles(mesh)
	return total


func _surface_triangles(mesh: ArrayMesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		count += vertices.size() / 3
	return count