## Sun, sky and fog for the island.
##
## Split out from [TestEnvironment] because the two have different jobs: that one is
## a flat test bed with a reference grid, this one is lighting for real terrain with
## a long view distance.
##
## The values come from the palette's dusk cloud colours, chosen because the
## reference art is a dawn scene over water: a cool sky above, warm haze at the
## horizon, and enough fog depth that distant mountains sit behind the air rather
## than cutting against it.
class_name IslandAtmosphere
extends Node3D

## Direction the sun comes from, as yaw in degrees. 0 is north.
@export_range(0.0, 360.0, 1.0) var sun_yaw_degrees := 118.0
## Sun elevation. Low, so shadows are long and the terrain reads as relief.
@export_range(-10.0, 80.0, 0.5) var sun_elevation_degrees := 22.0
@export var sun_energy := 1.25
@export var sun_color := Color(1.0, 0.88, 0.74)

## Sky gradient. The palette's dusk set, warmed slightly near the horizon.
@export var sky_top := Color("#5A63A8")
@export var sky_horizon := Color("#FFB9A6")
@export var ground_horizon := Color("#7A5C8E")
@export var ground_bottom := Color("#242848")

## Fog. Distance fog rather than density, because a density fog fills in the whole
## view and washes out the near terrain; depth fog only affects distance, which is
## what gives aerial perspective.
@export var fog_color := Color("#C9A8C4")
@export_range(300.0, 8000.0, 50.0) var fog_begin := 900.0
@export_range(600.0, 12000.0, 50.0) var fog_end := 4200.0
@export_range(0.5, 3.0, 0.05) var fog_curve := 1.5

## Distance at which shadows are calculated, in metres.
@export_range(100.0, 4000.0, 50.0) var shadow_distance := 1400.0

var _sun: DirectionalLight3D
var _world_environment: WorldEnvironment


func _ready() -> void:
	_build_sun()
	_build_environment()


func sun() -> DirectionalLight3D:
	return _sun


## Unit vector pointing from the world toward the sun.
func sun_direction() -> Vector3:
	var yaw := Units.deg_to_rad(sun_yaw_degrees)
	var elevation := Units.deg_to_rad(sun_elevation_degrees)
	return Vector3(
		cos(elevation) * sin(yaw),
		sin(elevation),
		cos(elevation) * cos(yaw)
	)


func _build_sun() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.light_color = sun_color
	_sun.light_energy = sun_energy
	_sun.light_specular = 0.4
	_sun.shadow_enabled = true
	# Parallel splits rather than a single cascade: with a long view distance a
	# single cascade cannot hold useful resolution, and terrain shadows at long
	# range need it.
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = shadow_distance
	_sun.directional_shadow_split_1 = 0.06
	_sun.directional_shadow_split_2 = 0.18
	_sun.directional_shadow_split_3 = 0.45
	_sun.directional_shadow_blend_splits = true
	_sun.directional_shadow_fade_start = 0.9
	_sun.shadow_bias = 0.05
	_sun.shadow_normal_bias = 1.8

	_sun.look_at_from_position(Vector3.ZERO, sun_direction(), Vector3.UP)
	add_child(_sun)


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_top
	sky_material.sky_horizon_color = sky_horizon
	sky_material.sky_curve = 0.18
	sky_material.ground_horizon_color = ground_horizon
	sky_material.ground_bottom_color = ground_bottom
	sky_material.ground_curve = 0.05
	sky_material.sun_angle_max = 6.0
	sky_material.sun_curve = 0.08

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky

	# Ambient light from the sky rather than a flat colour, so shaded slopes pick
	# up the sky's blue and do not go uniformly grey.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = fog_color
	environment.fog_light_energy = 1.0
	environment.fog_sun_scatter = 0.25
	environment.fog_density = 0.0
	environment.fog_depth_begin = fog_begin
	environment.fog_depth_end = fog_end
	environment.fog_depth_curve = fog_curve
	environment.fog_sky_affect = 0.4

	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 1.6

	_world_environment = WorldEnvironment.new()
	_world_environment.name = "WorldEnvironment"
	_world_environment.environment = environment
	add_child(_world_environment)