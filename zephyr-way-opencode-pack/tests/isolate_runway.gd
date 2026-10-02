extends SceneTree
## Minimal isolated reproduction of the runway, with nothing else in the scene.
##
## The runway is torn when the Island is on screen and complete when the terrain chunks
## are hidden. That contradiction is what this scene exists to break: here there is a
## camera, one light, a flat background and the runway mesh, and nothing else. If it
## renders complete here, then culling is not the cause and the fault lies in whatever
## the Island adds. If it is torn here, the runway mesh is at fault and the Island is
## innocent.
##
## Two reference quads sit beside the runway, wound in opposite directions, so the same
## render settles Godot's front-face convention for this geometry rather than it having
## to be assumed. MAGENTA is wound so its geometric normal points up; CYAN is the
## reverse.
##
##   godot --path . --script res://tests/isolate_runway.gd

const WIDTH := 1280
const HEIGHT := 720
const UP_WINDING := Color(1.0, 0.0, 1.0)
const DOWN_WINDING := Color(0.0, 1.0, 1.0)


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(WIDTH, HEIGHT))

	var world := Node3D.new()
	root.add_child(world)

	# Flat background, no sky and no fog, so nothing in the atmosphere can be
	# mistaken for the geometry under test.
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.06, 0.07, 0.09)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	environment.ambient_light_energy = 1.0
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)

	var light := DirectionalLight3D.new()
	light.light_energy = 1.0
	light.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	world.add_child(light)

	# The runway, exactly as the island builds it, in its own local space.
	var runway := Airport._runway(850.0)
	var runway_instance := StructureBuilder.to_mesh_instance("Runway", runway)
	world.add_child(runway_instance)

	# Reference quads: same winding helper, opposite directions.
	# Beside the runway rather than on it, and lifted clear of every surface in the
	# scene: the point is to be seen, not to be occluded by the thing under test.
	var up := StructureBuilder.new()
	up.quad(
		Vector3(80.0, 6.0, 0.0), Vector3(80.0, 6.0, 60.0),
		Vector3(150.0, 6.0, 60.0), Vector3(150.0, 6.0, 0.0), UP_WINDING)
	var down := StructureBuilder.new()
	down.quad(
		Vector3(-150.0, 6.0, 0.0), Vector3(-80.0, 6.0, 0.0),
		Vector3(-80.0, 6.0, 60.0), Vector3(-150.0, 6.0, 60.0), DOWN_WINDING)
	world.add_child(StructureBuilder.to_mesh_instance("RefUp", up))
	world.add_child(StructureBuilder.to_mesh_instance("RefDown", down))

	var camera := Camera3D.new()
	camera.fov = 50.0
	camera.near = 1.0
	camera.far = 20000.0
	camera.current = true
	world.add_child(camera)
	# Wait for the tree before posing the camera. SceneTree.root is not inside the tree
	# during _initialize, so look_at() there fails with "!is_inside_tree()" and the
	# camera silently stays at the origin -- which is why the first run of this script
	# found neither reference quad.
	await process_frame
	camera.look_at_from_position(Vector3(120.0, 1250.0, 120.0), Vector3(0.0, 0.0, 0.0), Vector3.UP)

	for _i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var cull_back_frame := root.get_texture().get_image()
	cull_back_frame.save_png("user://iso_runway_cull_back.png")
	var back := _reference_visible(UP_WINDING, DOWN_WINDING)
	print("CULL_BACK   reference quads visible: %s" % back)

	var material := runway_instance.material_override as StandardMaterial3D
	material = material.duplicate()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	runway_instance.material_override = material
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var no_cull_frame := root.get_texture().get_image()
	no_cull_frame.save_png("user://iso_runway_no_cull.png")

	# The acceptance test in one number: with nothing else in the scene, normal culling
	# must produce the same image as no culling at all. Anything that differs is a face
	# that culling is wrongly discarding.
	var differing := 0
	for y in cull_back_frame.get_height():
		for x in cull_back_frame.get_width():
			var a := cull_back_frame.get_pixel(x, y)
			var b := no_cull_frame.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.06:
				differing += 1
	print("pixels differing between CULL_BACK and CULL_DISABLED: %d of %d" % [
		differing, cull_back_frame.get_width() * cull_back_frame.get_height()])
	print("")
	print("wrote iso_runway_cull_back.png and iso_runway_no_cull.png")
	quit()


## Whether each reference quad's colour survived into the frame, which is how the
## front-face convention is read off the render rather than assumed.
func _reference_visible(up_color: Color, down_color: Color) -> String:
	var image := root.get_texture().get_image()
	var found_up := false
	var found_down := false
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if absf(c.r - up_color.r) < 0.15 and c.b > 0.7 and c.g < 0.3:
				found_up = true
			if c.g > 0.7 and c.b > 0.7 and c.r < 0.3:
				found_down = true
	return "magenta(up-wound)=%s  cyan(down-wound)=%s" % [found_up, found_down]
