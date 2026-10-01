## Flat test environment for the first playable slice.
##
## Milestone 1 asks for a simple flat test bed, not the island. What it does
## provide is everything needed to judge flight feel: an uncluttered ground
## plane, a grid for judging speed and closure, a horizon of distant ridges to
## give the eye something to read against, and lighting and sky tuned to the
## palette's dusk set.
##
## All geometry is generated in code. Meshes are built once and shared, so the
## grid and ridges cost a handful of draw calls.
##
## Also the terrain height authority for milestone 1: [method ground_height_at]
## is what AircraftController samples, and returning a constant here is what
## makes the flat slice flat. Replacing this with real terrain later is a change
## to one function.
class_name TestEnvironment
extends Node3D

## Half-extent of the ground plane, in metres. The design world is 5000 m across,
## so this is generous enough to never see the edge from the air.
@export var ground_extent := 4000.0

## Spacing and extent of the reference grid, in metres. The grid is the main cue
## for judging speed in a featureless world.
@export var grid_spacing := 100.0
@export var grid_extent := 1600.0
@export var grid_line_width := 1.2

## Height of the horizon ridges above the ground, in metres.
@export var ridge_height := 220.0
@export var ridge_distance := 2600.0
@export var ridge_count := 26
## Seed for ridge placement, so the horizon is identical every run.
@export var ridge_seed := 20261

## Sun direction as yaw and pitch in degrees. Low and warm, matching the
## reference art's dawn light.
@export var sun_yaw_degrees := 128.0
@export var sun_pitch_degrees := 14.0
@export var sun_energy := 1.15
@export var sun_color := Color(1.0, 0.87, 0.72)

## Sky and fog colours, from design/color_palette.json `cloud.dusk_*` and `ink`.
@export var sky_top_color := Color("#6A74B8")
@export var sky_horizon_color := Color("#FFB3A0")
@export var ground_horizon_color := Color("#6A4A8E")
@export var ground_bottom_color := Color("#2A2F66")
@export var fog_color := Color("#B89AC8")
@export_range(200.0, 8000.0, 10.0) var fog_distance := 2600.0

## Ground colour, from `grass.lawn_airport`.
@export var ground_color := Color("#8FD068")

var _sun: DirectionalLight3D
var _environment_node: WorldEnvironment


func _ready() -> void:
	_build_sun()
	_build_environment()
	_build_ground()
	_build_grid()
	_build_ridges()


## Terrain height under a world position. Constant for the flat test bed.
func ground_height_at(_position: Vector3) -> float:
	return 0.0


func sun() -> DirectionalLight3D:
	return _sun


## Yaw the sun so it can be shared with later atmosphere work.
func sun_direction() -> Vector3:
	var yaw := Units.deg_to_rad(sun_yaw_degrees)
	var pitch := Units.deg_to_rad(sun_pitch_degrees)
	return Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))


func _build_sun() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.light_color = sun_color
	_sun.light_energy = sun_energy
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = 600.0
	_sun.directional_shadow_split_1 = 0.12
	_sun.directional_shadow_blend_splits = true
	_sun.directional_shadow_fade_start = 0.85
	# Low sun means a long shadow that would smear across half the map, so bias
	# and normal-offset are kept modest rather than tuned to the reference shot.
	_sun.shadow_bias = 0.04
	_sun.shadow_normal_bias = 1.5

	# DirectionalLight3D shines along its local -Z, so aim that axis at the sun
	# vector. look_at_or_spread avoids gimbal problems when the sun is overhead.
	var direction := sun_direction()
	_sun.look_at_from_position(Vector3.ZERO, direction, Vector3.UP)
	add_child(_sun)


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_top_color
	sky_material.sky_horizon_color = sky_horizon_color
	sky_material.sky_curve = 0.15
	sky_material.ground_horizon_color = ground_horizon_color
	sky_material.ground_bottom_color = ground_bottom_color
	sky_material.ground_curve = 0.08
	sky_material.sun_angle_max = 8.0
	sky_material.sun_curve = 0.06

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Light depth fog: cheap, and it is what separates the ridge silhouettes
	# from the sky instead of leaving hard cutouts.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = fog_color
	environment.fog_density = 0.0
	environment.fog_depth_begin = fog_distance * 0.45
	environment.fog_depth_end = fog_distance
	environment.fog_depth_curve = 1.4
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 1.4

	_environment_node = WorldEnvironment.new()
	_environment_node.name = "WorldEnvironment"
	_environment_node.environment = environment
	add_child(_environment_node)


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(ground_extent, ground_extent)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	ground.mesh = plane
	ground.material_override = MeshBuilder.flat_material(ground_color, 0.95)
	# A flat plane casting a shadow onto itself costs a full shadow pass for no
	# visual gain, since there is nothing above it yet.
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)


## Reference grid built as one mesh of thin quads rather than many nodes. This is
## the cheapest way to make speed legible in an otherwise empty world.
func _build_grid() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := grid_line_width * 0.5
	var step := maxf(grid_spacing, 1.0)
	var count := int(grid_extent / step)

	for index in range(-count, count + 1):
		var offset := float(index) * step
		# Lines parallel to X
		_add_flat_quad(tool, Vector3(-grid_extent, 0.0, offset - half), Vector3(grid_extent, 0.0, offset - half), Vector3(grid_extent, 0.0, offset + half), Vector3(-grid_extent, 0.0, offset + half))
		# Lines parallel to Z
		_add_flat_quad(tool, Vector3(offset - half, 0.0, -grid_extent), Vector3(offset + half, 0.0, -grid_extent), Vector3(offset + half, 0.0, grid_extent), Vector3(offset - half, 0.0, grid_extent))

	var grid := MeshInstance3D.new()
	grid.name = "ReferenceGrid"
	grid.mesh = MeshBuilder.commit(tool)
	var material := MeshBuilder.flat_material(Color("#7FBF5A"), 1.0)
	# Slightly transparent so the grid reads as an overlay on the grass rather
	# than as painted lines, which keeps it from competing with the aircraft.
	material.albedo_color = Color(0.55, 0.78, 0.42, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid.material_override = material
	grid.position.y = 0.05
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grid)


func _add_flat_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	MeshBuilder.add_quad(tool, a, b, c, d)


## Distant ridge silhouettes. Their only job is to give the horizon a readable
## scale reference; they are unlit, shadowless and placed beyond the fog so they
## read as flat atmospheric shapes.
func _build_ridges() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = ridge_seed

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var sides := 5
	for ridge in ridge_count:
		var angle := TAU * float(ridge) / float(ridge_count)
		# Jitter the radius so the ring is not a perfect circle.
		var distance := ridge_distance * rng.randf_range(0.85, 1.2)
		var centre := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		var height := ridge_height * rng.randf_range(0.55, 1.35)
		var width := distance * rng.randf_range(0.28, 0.5)

		for side_index in sides:
			var a := TAU * float(side_index) / float(sides) + rng.randf_range(-0.2, 0.2)
			var offset := Vector3(cos(a) * width, 0.0, sin(a) * width)
			var base := centre + offset
			var apex := centre + offset * rng.randf_range(0.1, 0.35)
			apex.y = height
			var next_base := centre + (base - centre).rotated(Vector3.UP, TAU / float(sides))
			var next_apex := centre + (apex - centre).rotated(Vector3.UP, TAU / float(sides))
			MeshBuilder.add_triangle(tool, base, apex, next_apex)
			MeshBuilder.add_triangle(tool, base, next_apex, next_base)

	var ridges := MeshInstance3D.new()
	ridges.name = "HorizonRidges"
	ridges.mesh = MeshBuilder.commit(tool)
	# `rock.cool_grey` pushed toward the fog colour so the ridges sit behind the
	# atmosphere rather than in front of it.
	var color := Color("#6C7288").lerp(fog_color, 0.35)
	var material := MeshBuilder.flat_material(color, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ridges.material_override = material
	ridges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ridges)