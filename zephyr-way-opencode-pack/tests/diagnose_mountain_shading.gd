extends SceneTree
## Isolates why the mountains render paler than their palette.
##
## The albedo is known to be correct (#585a6f for a steep face), and the tonemapper
## has been checked to be linear at 1.0. So the suspects are fog, sun energy, ambient
## fill, and the terrain material's own shading.
##
## Method: render the same viewpoint repeatedly, changing exactly one factor, and
## read back the actual pixel values from the framebuffer. A pixel measurement is
## evidence; squinting at a screenshot is not.
##
##   godot --path . --script res://tests/diagnose_mountain_shading.gd

const WIDTH := 640
const HEIGHT := 360
## Fraction of the frame height to discard from the top, as sky.
##
## The first version of this measured the whole frame and every configuration came
## back within a percent of the same number, because two thirds of it was sky. A sky
## pixel does not care what the fog or the sun are doing, so the measurement was
## reporting the sky and calling it the mountain.
const SKY_CROP := 0.34
## Fraction discarded from the bottom, as sea.
const SEA_CROP := 0.06
## How close to stand to the massif.
const DISTANCE := 900.0


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(WIDTH, HEIGHT))

	var scene: PackedScene = load("res://scenes/world/Island.tscn")
	var island := scene.instantiate() as Island
	root.add_child(island)
	await process_frame
	await process_frame

	var camera := Camera3D.new()
	# Narrow field of view so the massif fills the frame rather than sitting in it.
	camera.fov = 34.0
	# SceneTree is not a Node, so everything hangs off the window root.
	root.add_child(camera)

	# Aim at an actual massif rather than a guessed coordinate, so the measurement
	# survives retuning the terrain.
	var generator := island.generator
	var focus: Vector2 = generator._mountain_focus(0, generator.mountain_count)
	var summit := generator.height_at(focus.x, focus.y)
	var target := Vector3(focus.x, summit * 0.62, focus.y)
	var bearing := (focus - generator.island_center).angle()
	var offset := Vector2(cos(bearing), sin(bearing)) * DISTANCE
	camera.global_position = Vector3(focus.x + offset.x, summit * 0.72, focus.y + offset.y)
	camera.look_at(target, Vector3.UP)
	camera.make_current()
	print("aimed at massif 0 summit %.0f m, standing %.0f m away" % [summit, DISTANCE])

	# Let the world settle and every chunk build.
	for _i in 200:
		await process_frame
	# Build chunks synchronously so the terrain is definitely complete.
	await _build_all(island)
	for _i in 20:
		await process_frame

	print("=== mountain shading diagnosis ===")
	print("palette rock.cool_grey = %s" % Palette.color("rock.cool_grey").to_html(false))
	print("palette snow.shade    = %s" % Palette.color("snow.shade").to_html(false))
	print("")

	# Baseline: everything as shipped.
	await _measure(camera, "as shipped")

	var atmo := island.get_node(^"Atmosphere") as IslandAtmosphere
	var env := _environment_of(atmo)

	# Unshaded control. With lighting off, every terrain pixel renders as exactly the
	# vertex colour the mesh was given, which is the palette. If that matches
	# rock.cool_grey then the mesh is correct and any paleness is lighting. If it does
	# not, the palette is being lost before lighting is ever applied.
	var materials := _terrain_materials(island)
	for material in materials:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	await _measure(camera, "UNSHADED (palette as-is)")

	# Sun off, back to shaded: whatever light is doing.
	for material in materials:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var sun := atmo.sun()
	var energy := sun.light_energy
	sun.light_energy = 0.0
	await _measure(camera, "sun OFF (ambient only)")

	# Sun at a quarter: is the response linear in sun energy, as shading should be?
	sun.light_energy = energy * 0.25
	await _measure(camera, "sun at 25%%")
	sun.light_energy = energy * 0.5
	await _measure(camera, "sun at 50%%")
	sun.light_energy = energy
	await _measure(camera, "sun at 100%% (shipped %.2f)" % energy)

	# Fog, now that the sun is understood.
	env.fog_enabled = false
	await _measure(camera, "shipped sun, fog OFF")
	env.fog_enabled = true
	quit()


## Every distinct terrain material in the built chunks.
func _terrain_materials(island: Island) -> Array[BaseMaterial3D]:
	var found: Array[BaseMaterial3D] = []
	var seen := {}
	var chunks := island.get_node(^"Chunks")
	for child in chunks.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var m := mi.material_override as BaseMaterial3D
		if m != null and not seen.has(m.get_instance_id()):
			seen[m.get_instance_id()] = true
			found.append(m)
	return found


## Report the mean colour of the brightest and darkest large regions of the frame,
## plus a histogram, so a wash-out is visible as a number and not a judgement.
func _measure(camera: Camera3D, label: String) -> void:
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image = _sample(image)
	var stats := _stats(image)
	print("  %-42s mean %s  p10 %s  p90 %s  p99 %s" % [
		label, stats["mean"], stats["p10"], stats["p90"], stats["p99"]])


## Crops sky and sea out of the frame, then samples what is left.
func _sample(image: Image) -> Image:
	var top := int(float(image.get_height()) * SKY_CROP)
	var bottom := int(float(image.get_height()) * (1.0 - SEA_CROP))
	var span := maxi(bottom - top, 1)
	var out := Image.create_empty(16, 12, false, Image.FORMAT_RGB8)
	for y in 12:
		for x in 16:
			var src := Vector2i(
				int(float(x) / 15.0 * float(image.get_width() - 1)),
				top + int(float(y) / 11.0 * float(span - 1))
			)
			out.set_pixel(x, y, image.get_pixelv(src))
	return out


func _stats(image: Image) -> Dictionary:
	var values: Array[float] = []
	var r := 0.0
	var g := 0.0
	var b := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			# Luminance, so the three channels collapse to one ordering.
			values.append(c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722)
			r += c.r
			g += c.g
			b += c.b
	values.sort()
	var n := float(values.size())
	return {
		"mean": Color(r / n, g / n, b / n).to_html(false),
		"p10": _luma_to_hex(values[int(n * 0.1)]),
		"p90": _luma_to_hex(values[int(n * 0.9)]),
		"p99": _luma_to_hex(values[int(n * 0.99)]),
	}


func _luma_to_hex(luma: float) -> String:
	return Color(luma, luma, luma).to_html(false)


func _environment_of(atmo: IslandAtmosphere) -> Environment:
	for child in atmo.get_children():
		if child is WorldEnvironment:
			return (child as WorldEnvironment).environment
	return null


## Build every chunk now rather than waiting on the per-frame budget.
func _build_all(island: Island) -> void:
	var wanted := island.builder.chunk_origins().size()
	var guard := 0
	while island.built_chunk_count() < wanted and guard < 4000:
		await process_frame
		guard += 1
