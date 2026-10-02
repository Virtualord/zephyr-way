extends SceneTree
## Reads the vertex colours the terrain mesh actually carries, and where they sit.
##
## The rendered images say the mountains are pale. This says what colour the mesh
## was given, which is upstream of every lighting effect. If the mesh is right then
## the paleness is lighting; if the mesh is wrong then no amount of tonemapping or fog
## tuning will fix it.
##
##   godot --headless --path . --script res://tests/diagnose_terrain_colours.gd

func _initialize() -> void:
	var g := TerrainGenerator.new()
	var b := TerrainBuilder.new(g)
	var focus: Vector2 = g._mountain_focus(0, g.mountain_count)
	var origin := Vector2(floor(focus.x / 500.0) * 500.0, floor(focus.y / 500.0) * 500.0)
	var mesh := b.build_chunk(origin, true)
	if mesh == null:
		print("no mesh")
		quit(1)
		return

	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	print("chunk at %v: %d vertices, %d colours" % [origin, verts.size(), cols.size()])

	# Height bands, with the palette colour the generator intends for that height.
	print("")
	print("height band | faces | mean vertex colour | brightest | intended")
	var bands := [
		["0-100 m", 0.0, 100.0], ["100-300 m", 100.0, 300.0],
		["300-500 m", 300.0, 500.0], ["500-600 m", 500.0, 600.0],
		["600-700 m", 600.0, 700.0],
	]
	for band in bands:
		var low: float = band[1]
		var high: float = band[2]
		var sum := Color(0, 0, 0)
		var brightest := Color(0, 0, 0)
		var count := 0
		for i in verts.size():
			var h := verts[i].y
			if h < low or h >= high:
				continue
			sum += cols[i]
			count += 1
			if cols[i].get_luminance() > brightest.get_luminance():
				brightest = cols[i]
		if count == 0:
			print("  %-11s %6d  (none)" % [band[0], 0])
			continue
		var mean := sum / float(count)
		print("  %-11s %6d  mean %s  brightest %s" % [
			band[0], count, mean.to_html(false), brightest.to_html(false)])

	print("")
	print("palette references:")
	for name in ["rock.cool_grey", "rock.dark", "snow.shade", "snow.top", "grass.meadow"]:
		print("  %-16s %s" % [name, Palette.color(name).to_html(false)])

	# What does the face_color function itself return, at the steep-face slope a
	# mountain flank actually has?
	print("")
	print("face_color() on a steep face (slope 1.0), by height:")
	for h: float in [200.0, 400.0, 550.0, 650.0]:
		print("  %4.0f m -> %s" % [
			h, b.face_color(g, Vector3(0, h, 0), 1.0, b.snow_line).to_html(false)])
	quit()
