extends SceneTree
## Finds terrain that floats above the surface it belongs to.
##
## The aerial overview shows a detached shard of rock hanging in the sky above the
## island's far coast. The scene test already confirms every chunk key appears exactly
## once, so this is not a duplicate: it is geometry sitting well above the terrain.
##
## Two mistakes are guarded against here, both of which produced a confident wrong
## answer before this file was corrected.
##
## Chunk meshes carry their offset in the node NAME, not in their transform: every
## chunk's global_position is (0, 0, 0) and the vertices are pre-offset. Reading
## global_position compared every chunk against the terrain at the world origin and
## reported the whole island as floating.
##
## And the footprint must be sampled across the whole chunk. The first version stepped
## from the chunk origin by a sample spacing barely larger than the chunk's cell, so
## it measured a single 25 m corner of each 500 m chunk and reported 30-odd chunks as
## floating by up to 750 m -- including chunk meshes that match the generator exactly.
## Both of those reports were wrong, and the real cause of the apparent floating rock
## was the camera's far plane clipping the sea out from under a distant massif.
##
##   godot --path . --script res://tests/diagnose_floating_terrain.gd

## A chunk's mesh may legitimately stand above the sampled terrain by this much, for
## the sampling step and for the mesh's own vertical exaggeration.
const SLACK_M := 40.0
## Spacing of the terrain samples taken over each chunk's footprint, in metres.
const SAMPLE_M := 25.0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/world/Island.tscn")
	var island := scene.instantiate() as Island
	root.add_child(island)
	await process_frame
	await process_frame

	var wanted := island.builder.chunk_origins().size()
	var guard := 0
	while island.built_chunk_count() < wanted and guard < 4000:
		await process_frame
		guard += 1

	var generator := island.generator
	var chunks := island.get_node(^"Chunks")
	var floating: Array[Dictionary] = []
	var parsed := 0

	print("chunks built: %d" % island.built_chunk_count())
	print("")
	for child in chunks.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var origin := _origin_from_name(String(mi.name))
		parsed += 1

		# The mesh's own vertices already include the offset, so read them directly
		# rather than adding a transform.
		var arrays := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var mesh_top := -INF
		for v in verts:
			mesh_top = maxf(mesh_top, v.y)

		# The tallest terrain the generator produces over this chunk's own cells.
		# Sample the mesh's own footprint, not the chunk's nominal one, and cover the
		# full cell -- the previous loop covered only the first sample interval.
		var bounds := mi.mesh.get_aabb()
		var terrain_max := -INF
		var x := bounds.position.x
		while x <= bounds.position.x + bounds.size.x:
			var z := bounds.position.z
			while z <= bounds.position.z + bounds.size.z:
				terrain_max = maxf(terrain_max, generator.height_at(x, z))
				z += SAMPLE_M
			x += SAMPLE_M

		var overhang := mesh_top - terrain_max
		if overhang > SLACK_M:
			floating.append({
				"name": String(mi.name), "mesh": mesh_top,
				"terrain": terrain_max, "over": overhang,
			})

	print("chunks parsed: %d" % parsed)
	print("chunks whose mesh rises more than %.0f m above the terrain beneath them: %d" % [
		SLACK_M, floating.size()])
	for f: Dictionary in floating:
		print("  %-22s mesh top %.0f m   terrain max %.0f m   floating %+.0f m" % [
			f["name"], f["mesh"], f["terrain"], f["over"]])
	quit()


## Chunk nodes are named \"Chunk_<x>_<y>\" in grid coordinates, which carry the
## chunk's world-space origin.
func _origin_from_name(chunk_name: String) -> Vector2:
	var parts := chunk_name.split("_")
	if parts.size() < 3:
		return Vector2.ZERO
	var gx := float(parts[parts.size() - 2])
	var gy := float(parts[parts.size() - 1])
	return Vector2(gx, gy)