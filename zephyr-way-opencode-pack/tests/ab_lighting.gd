extends SceneTree
## A/B the wide view against each lighting factor, as images.
##
## The earlier numeric sweep concluded "fog is not the cause", but it measured from
## 900 m where fog_begin is 2600 m and there is no fog to find. The wide shots are
## from 2-3 km, where fog is active. So the question is being re-asked at the distance
## where the problem is actually visible, and answered by looking at pictures rather
## than at a mean over a frame that is mostly sky.
##
##   godot --path . --script res://tests/ab_lighting.gd

const WIDTH := 960
const HEIGHT := 540


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
	for _i in 20:
		await process_frame

	var camera := _find_camera(main) as ChaseCamera
	camera.detached = true
	var g := island.generator
	# The same framing as the aerial shot, which is where the problem shows.
	var centre: Vector2 = g.island_center
	var radius := g.island_radius
	camera.global_position = Vector3(
		centre.x + radius * 1.15, 320.0, centre.y + radius * 0.7
	)
	camera.look_at(Vector3(centre.x, 150.0, centre.y), Vector3.UP)
	for _i in 10:
		await process_frame

	var atmo := island.get_node(^"Atmosphere") as IslandAtmosphere
	var env := _environment_of(atmo)
	var sun := atmo.sun()

	print("distance from camera to the far massif: ~%.0f m" % radius)
	print("fog: %s  %.0f to %.0f m" % [env.fog_enabled, env.fog_depth_begin, env.fog_depth_end])
	print("")

	await _shoot("ab_1_shipped")

	env.fog_enabled = false
	await _shoot("ab_2_no_fog")
	env.fog_enabled = true

	env.ambient_light_energy = 0.0
	await _shoot("ab_3_no_ambient")
	env.ambient_light_energy = 0.25

	sun.light_energy = 0.0
	await _shoot("ab_4_no_sun")
	sun.light_energy = 0.55

	env.ambient_light_energy = 0.0
	sun.light_energy = 0.0
	await _shoot("ab_5_neither")
	env.ambient_light_energy = 0.25
	sun.light_energy = 0.55

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.40, 0.52)
	await _shoot("ab_6_neutral_ambient")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY

	print("")
	print("written to %s" % ProjectSettings.globalize_path("user://"))
	quit()


func _shoot(name: String) -> void:
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "user://%s.png" % name
	image.save_png(path)
	print("  %s" % path)


func _find_camera(node: Node) -> Node:
	if node is ChaseCamera:
		return node
	for child in node.get_children():
		var found := _find_camera(child)
		if found != null:
			return found
	return null


func _environment_of(atmo: Node) -> Environment:
	for child in atmo.get_children():
		if child is WorldEnvironment:
			return (child as WorldEnvironment).environment
	return null
