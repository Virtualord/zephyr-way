extends SceneTree
## Investigated the shard of rock that appeared to float above the island in the
## aerial overview.
##
## The answer turned out to be that there was no floating geometry: every mesh whose
## bounding box these rays pass through is the sea, and every one of the 289 chunks has
## an identity transform and a bounding-box top of at most 685 m. Kept because the
## method is the part worth having -- screen-space proximity is not evidence, since a
## seabed chunk and a mountain chunk can project to the same pixel. This marches the
## real camera ray and intersects world-space boxes instead.
##
## What it actually exonerated was the camera. With `far` left at Godot's 4000 m
## default, the sea was clipped away well short of the horizon and the water beneath a
## distant massif was cut out with it, leaving the massif apparently hanging in the sky.
## The fix is in ChaseCamera; see docs/ARCHITECTURE.md.
##
##   godot --path . --script res://tests/diagnose_shard_raycast.gd

const WIDTH := 1280
const HEIGHT := 720
## The shard's centre, as a fraction of the frame, in the aerial_overview shot.
const SHARD_UV := Vector2(0.39, 0.25)


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(WIDTH, HEIGHT))

	var scene: PackedScene = load("res://scenes/main/Main.tscn")
	var main := scene.instantiate()
	root.add_child(main)
	var island := main.get_node(^"Island") as Island
	await process_frame
	await process_frame

	var wanted := island.builder.chunk_origins().size()
	var guard := 0
	while island.built_chunk_count() < wanted and guard < 4000:
		await process_frame
		guard += 1

	var camera := Camera3D.new()
	camera.fov = 60.0
	camera.current = true
	root.add_child(camera)
	var centre: Vector2 = island.generator.island_center
	var radius: float = island.generator.island_radius
	camera.global_position = Vector3(centre.x, radius * 1.35, centre.y + radius * 1.15)
	camera.look_at(Vector3(centre.x, 0.0, centre.y), Vector3.UP)
	for _i in 8:
		await process_frame

	var from := camera.project_ray_origin(SHARD_UV)
	var dir := camera.project_ray_normal(SHARD_UV)
	print("ray from " + str(from) + " toward " + str(dir))

	# Sweep the whole upper part of the frame. If nothing but the sea is hit anywhere
	# up there then whatever is drawn against the sky is not scene geometry, and the
	# question changes from "which node" to "what is drawing it".
	var names := {}
	for row in 16:
		for col in 24:
			var uv := Vector2(0.15 + float(col) / 23.0 * 0.7, 0.02 + float(row) / 15.0 * 0.34)
			var f := camera.project_ray_origin(uv)
			var d := camera.project_ray_normal(uv)
			var found: Array = []
			_collect(root, f, d, found, [])
			for hit in found:
				var n: String = hit["name"]
				if not n.ends_with("Sea"):
					names[n] = true
	print("")
	print("non-sea meshes hit by rays across the upper frame:")
	if names.is_empty():
		print("  NONE -- nothing but sea up there")
	for n: String in names:
		print("  %s" % n)

	# The sea, for reference: its own extent and where the ray leaves it.
	var sea := island.get_node(^"Sea") as MeshInstance3D
	var half: float = (sea.mesh as PlaneMesh).size.x * 0.5
	print("")
	print("sea plane half-extent %.0f m, so its edge is %.0f m from the origin" % [half, half])
	print("chunks built: %d" % island.built_chunk_count())
	quit()


func _collect(
	node: Node, from: Vector3, dir: Vector3, hits: Array, path: Array
) -> void:
	for child in node.get_children():
		var here := path.duplicate()
		here.append(child.name)
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh != null and mi.visible:
			var aabb := mi.mesh.get_aabb()
			var t: float = _ray_aabb(from, dir, aabb)
			if t >= 0.0:
				hits.append({
					"name": String("/".join(here)), "t": t,
					"lo": aabb.position.y, "hi": aabb.position.y + aabb.size.y,
				})
		_collect(child, from, dir, hits, here)


## Slab test. Returns the near distance if the ray meets the box, -1 otherwise.
func _ray_aabb(from: Vector3, dir: Vector3, box: AABB) -> float:
	var tmin := -INF
	var tmax := INF
	for axis in 3:
		var o: float = from[axis]
		var d: float = dir[axis]
		if absf(d) < 1e-8:
			# Ray is parallel to this slab: a miss unless the origin is already inside.
			if o < box.position[axis] or o > box.position[axis] + box.size[axis]:
				return -1.0
			continue
		var t1: float = (box.position[axis] - o) / d
		var t2: float = (box.position[axis] + box.size[axis] - o) / d
		if t1 > t2:
			var swap := t1
			t1 = t2
			t2 = swap
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return -1.0
	return maxf(tmin, 0.0)