extends SceneTree
## Finds the sun and ambient levels at which a lit rock face renders at its palette
## value.
##
## Established already, by measurement rather than by eye:
##
## - The terrain mesh carries the correct palette. Vertex colours on a massif read
##   575a6e for the body and d0d9f0 for snow, which is rock.dark lerped toward
##   rock.cool_grey and snow.shade respectively.
## - Disabling fog changes nothing at 900 m. Disabling ambient changes nothing
##   either. Only the sun moves the value.
##
## So the paleness is direct light, and the question is simply how much. A lit rock
## face currently renders about 4.7x its linear albedo, which is why the mountains
## read near-white: they are being lit as if they were snow.
##
## This sweeps the two light levels and reports the rendered value of a face known
## to be rock, so the answer is measured rather than guessed.
##
##   godot --path . --script res://tests/diagnose_mountain_exposure.gd

const WIDTH := 320
const HEIGHT := 200
## The rock colour the mountain body should render as when lit.
const TARGET := Color("575a6e")


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(WIDTH, HEIGHT))

	var scene: PackedScene = load("res://scenes/world/Island.tscn")
	var island := scene.instantiate() as Island
	root.add_child(island)
	await process_frame
	await process_frame

	var camera := Camera3D.new()
	camera.fov = 30.0
	root.add_child(camera)

	var g := island.generator
	var focus: Vector2 = g._mountain_focus(0, g.mountain_count)
	var summit := g.height_at(focus.x, focus.y)
	# Stand close and low, looking at the mid-flank where the ground is rock and
	# steep, so the face filling the frame is known to be rock rather than snow.
	camera.global_position = Vector3(focus.x + 420.0, 300.0, focus.y + 420.0)
	camera.look_at(Vector3(focus.x, summit * 0.55, focus.y), Vector3.UP)
	camera.make_current()

	for _i in 120:
		await process_frame
	var wanted := island.builder.chunk_origins().size()
	var guard := 0
	while island.built_chunk_count() < wanted and guard < 4000:
		await process_frame
		guard += 1
	for _i in 15:
		await process_frame

	var atmo := island.get_node(^"Atmosphere") as IslandAtmosphere
	var env := _environment_of(atmo)
	var sun := atmo.sun()
	env.fog_enabled = false

	print("target rock colour: %s   luminance %.3f" % [
		TARGET.to_html(false), TARGET.get_luminance()])
	print("")
	print("sun     ambient | rendered p50  | vs target")
	for pair: Array in [
		[1.25, 0.45], [0.80, 0.45], [0.55, 0.30], [0.40, 0.20], [0.30, 0.15]
	]:
		sun.light_energy = pair[0]
		env.ambient_light_energy = pair[1]
		var sample := await _read()
		var delta := sample.get_luminance() - TARGET.get_luminance()
		print("  %.2f    %.2f    | %s      | %+.3f" % [
			pair[0], pair[1], sample.to_html(false), delta])
	quit()


## Median rendered colour of the frame, which is a robust stand-in for "the colour
## of the thing being looked at" without needing to identify individual faces.
func _read() -> Color:
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var values: Array[Color] = []
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			values.append(image.get_pixel(x, y))
	values.sort_custom(func(a: Color, b: Color) -> bool:
		return a.get_luminance() < b.get_luminance())
	return values[values.size() / 2]


func _environment_of(atmo: IslandAtmosphere) -> Environment:
	for child in atmo.get_children():
		if child is WorldEnvironment:
			return (child as WorldEnvironment).environment
	return null
