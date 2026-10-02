extends SceneTree
## The ocean shader's sea is one flat colour, which means the depth term is not
## varying. Checks what the height field the shader reads actually contains.
##
##   godot --headless --path . --script res://tests/diagnose_ocean_field.gd

func _initialize() -> void:
	var island_scene: PackedScene = load("res://scenes/world/Island.tscn")
	var island := island_scene.instantiate() as Island
	root.add_child(island)
	await process_frame
	await process_frame

	var sea := island.get_node(^"Sea") as MeshInstance3D
	var material := sea.material_override as ShaderMaterial
	if material == null:
		print("sea has no ShaderMaterial: %s" % sea.material_override)
		quit(1)
		return
	print("sea material: %s" % material.get_class())
	print("shader: %s" % material.shader.resource_path)
	print("")
	for param: String in ["shallow_color", "deep_color", "foam_color", "world_extent", "sea_level"]:
		print("  %-14s = %s" % [param, material.get_shader_parameter(param)])

	var field: Texture2D = material.get_shader_parameter("height_field")
	print("")
	print("height_field: %s" % field)
	if field == null:
		print("  NO FIELD — the shader samples a null texture and depth comes out wrong")
		quit(1)
		return

	var image := field.get_image()
	print("  size %d x %d, format %d" % [
		image.get_width(), image.get_height(), image.get_format()])

	# Read a transect across the island and report the value the shader would see.
	var extent: float = material.get_shader_parameter("world_extent")
	var size := image.get_width()
	var sea_level: float = material.get_shader_parameter("sea_level")
	print("")
	print("transect along +x at z=0 (shader uv = x/extent + 0.5):")
	print("     x        texel value   height_at()   uv")
	for i in 11:
		var fx := float(i) / 10.0
		var x := (fx - 0.5) * extent * 0.5
		var u := (x / extent) + 0.5
		var tx := int(clampf(u, 0.0, 1.0) * float(size - 1))
		var texel: float = image.get_pixel(tx, size / 2).r
		print("  %7.0f   %12.2f   %10.1f   %.3f" % [
			x, texel, island.generator.height_at(x, 0.0), u])
	print("")
	print("sea_level = %.1f, so depth = sea_level - height" % sea_level)
	quit()
