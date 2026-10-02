extends SceneTree
## Renders the island from a set of viewpoints and saves PNGs, so the terrain can be
## looked at rather than only measured.
##
## Everything else in this project is verified headless and numerical, which catches
## real defects -- four of them, in milestone 03 -- but it cannot see that a mountain
## is nearly black or that the whole foreground is one flat wash of green. This is the
## check that can.
##
## Needs a real display server: the headless dummy renderer produces no image.
##   godot --path . --script res://tests/render_shot.gd
func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))

	var scene: PackedScene = load("res://scenes/main/Main.tscn")
	var main := scene.instantiate()
	root.add_child(main)

	# Let the island generate every chunk before shooting, so the views are of the
	# finished island rather than of a fade-in.
	#
	# Waiting on `_pending` alone is not enough: it is empty before the first
	# `_process` runs, so a single early check passes with nothing built. That is what
	# produced a shot of a half-built world with a stray slab of terrain hanging in
	# the sky. Waits for the count to match the grid instead.
	var island := main.get_node(^"Island") as Island
	await process_frame
	await process_frame
	var wanted := island.builder.chunk_origins().size()
	var frames := 0
	while frames < 3000 and island.built_chunk_count() < wanted:
		await process_frame
		frames += 1
	# A few more frames for materials, shadows and fog to settle.
	for _i in 40:
		await process_frame
	print("built %d of %d chunks in %d frames" % [
		island.built_chunk_count(), wanted, frames])

	print("chunks: %d, triangles: %d" % [island.built_chunk_count(), island.triangle_count()])
	if island.built_chunk_count() < island.builder.chunk_origins().size():
		print("WARNING: only %d of %d chunks built; the shots below are of a partial world" % [
			island.built_chunk_count(), island.builder.chunk_origins().size()])

	var camera := _find_camera(main)
	var centre: Vector2 = island.generator.island_center
	var radius := island.generator.island_radius

	# Ground level, on the runway, as the player first sees it. The chase camera is
	# still attached for this one, since that pose is the one it produces.
	await _shoot(camera, "ground_runway")

	# Everything after this is a review viewpoint rather than a gameplay one, so the
	# camera is detached and keeps the transform it is given.
	(camera as ChaseCamera).detached = true

	# High above the island looking down, to read its shape and the coastline.
	camera.global_position = Vector3(centre.x, radius * 1.35, centre.y + radius * 1.15)
	camera.look_at(Vector3(centre.x, 0.0, centre.y), Vector3.UP)
	await _settle()
	await _shoot(camera, "aerial_overview")

	# Straight down, which is the clearest read of the coastline and the airport.
	# Tilted rather than vertical: looking straight down with an up vector of +Y is
	# degenerate, and a slight lean keeps north at the top of the frame.
	camera.global_position = Vector3(centre.x, radius * 1.9, centre.y + radius * 0.02)
	camera.look_at(Vector3(centre.x, 0.0, centre.y), Vector3.FORWARD)
	await _settle()
	await _shoot(camera, "plan_view")

	# Low pass in from the sea toward the coast, which shows whether the shoreline
	# reads as a shoreline.
	camera.global_position = Vector3(centre.x + radius * 1.15, 320.0, centre.y + radius * 0.7)
	camera.look_at(Vector3(centre.x, 150.0, centre.y), Vector3.UP)
	await _settle()
	await _shoot(camera, "approach_from_sea")

	# A mountain massif from the air, for silhouette.
	var focus: Vector2 = island.generator._mountain_focus(0, island.generator.mountain_count)
	var summit := Vector3(focus.x, island.generator.height_at(focus.x, focus.y), focus.y)
	camera.global_position = summit + Vector3(radius * 0.5, radius * 0.28, radius * 0.5)
	camera.look_at(summit, Vector3.UP)
	await _settle()
	await _shoot(camera, "massif")

	print("")
	print("shots written to: %s" % ProjectSettings.globalize_path("user://"))
	quit()


func _settle() -> void:
	for _i in 8:
		await process_frame
	await RenderingServer.frame_post_draw


func _shoot(camera: Camera3D, name: String) -> void:
	# Two frames: one to apply the new transform, one to draw it.
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "user://shot_%s.png" % name
	image.save_png(path)
	print("  %s" % path)


func _find_camera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node
	for child in node.get_children():
		var found := _find_camera(child)
		if found != null:
			return found
	return null
