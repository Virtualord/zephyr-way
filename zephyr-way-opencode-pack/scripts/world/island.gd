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

## Extent of the sea plane, in metres. Must exceed the island radius so the
## horizon is water rather than an edge.
@export var sea_extent := 6000.0
@export var sea_color := Color("#1CA7C6")
@export var sea_deep_color := Color("#0A4F8F")

## Distance at which coarse chunks fade out, in metres.
@export_range(1000.0, 8000.0, 100.0) var visibility_range := 3600.0

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
## The detail is part of the key so both versions can coexist during a rebuild
## without one overwriting the other.
func _key_for(origin: Vector2, near: bool) -> int:
	var detail := 1 if near else 0
	return (int(origin.x) * 73856093) ^ (int(origin.y) * 19349663) ^ (detail * 83492791)


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


## Flat sea plane at sea level.
##
## A simple two-tone gradient by depth rather than a shader: milestone 04 owns the
## stylized ocean, and this only needs to read as water and provide a horizon.
func _build_sea() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(sea_extent, sea_extent)

	_sea = MeshInstance3D.new()
	_sea.name = "Sea"
	_sea.mesh = plane
	_sea.material_override = _sea_material()
	_sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sea.position.y = TerrainGenerator.SEA_LEVEL
	add_child(_sea)


func _sea_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = sea_color
	material.roughness = 0.12
	material.metallic = 0.25
	# Some transparency so shallow seabed colours show through near the shore,
	# which is the cheap part of what milestone 04 will do properly with a shader.
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