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
## Directional light strength.
##
## Set by measurement, not by eye, against the terrain's own vertex colours.
##
## The terrain mesh carries the palette exactly — a massif body reads 575a6e, which is
## rock.dark lerped toward rock.cool_grey — and that was confirmed by reading the mesh
## buffers directly. The paleness was entirely this light: at 1.25 a lit rock face
## rendered roughly 4.7x its linear albedo, so the mountains were being lit as though
## they were snow, and every face read near-white.
##
## An A/B render of the same viewpoint with each lighting factor isolated
## (tests/ab_lighting.gd) put the cause beyond doubt: with fog off the image is
## unchanged, with ambient off the image is unchanged, and with the sun off the
## mountains drop to their correct dark purple. The sun was the whole of it.
##
## So the level is set by what the sun alone does to the terrain, which is why cutting
## it from 1.25 to 0.55 was not enough — the mountains were still several times their
## albedo. Deliberately not 1.0: the palette is the colour of a *lit* face, and a
## face turned away from the sun should still be darker than its swatch.
@export var sun_energy := 0.32
@export var sun_color := Color(1.0, 0.88, 0.74)

## Sky gradient. The palette's dusk set, warmed slightly near the horizon.
@export var sky_top := Color("#5A63A8")
@export var sky_horizon := Color("#FFB9A6")
## Colour where the sky's lower half meets its upper half.
##
## Kept close to [member sky_horizon] on purpose. A large jump between the two puts a
## hard horizontal line across the sky at the horizon, which is very visible in a
## wide shot and reads as a rendering fault rather than as weather. The rendered
## images showed exactly that: a straight band well above the sea.
@export var ground_horizon := Color("#E8A9AE")
@export var ground_bottom := Color("#6B5A7E")

## Fog. Distance fog rather than density, because a density fog fills in the whole
## view and washes out the near terrain; depth fog only affects distance, which is
## what gives aerial perspective.
##
## The distances are set against the island, not chosen for looks. The island is
## 4000 m across and the world is 5000 m, so a player routinely has 2-3 km of
## terrain in frame at once. Fogging from 900 m to 4200 m — the first values tried —
## meant most of the island was permanently behind haze, and the rendered shots came
## back with a flat purple wash over the mountains and no horizon.
##
## Fog now starts beyond the island and completes well past it, so it does
## atmospheric depth on the far side of the world without touching anything the
## player is actually flying over.
@export var fog_color := Color("#B9A6CE")
@export_range(1000.0, 12000.0, 100.0) var fog_begin := 2600.0
@export_range(2000.0, 30000.0, 100.0) var fog_end := 11000.0
@export_range(0.5, 3.0, 0.05) var fog_curve := 1.0

## Distance at which shadows are calculated, in metres.
@export_range(100.0, 8000.0, 50.0) var shadow_distance := 3000.0

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
	# A broad gradient rather than a tight one.
	#
	# At 0.18 the horizon colour met the zenith colour within a few degrees, which
	# put a hard band across the sky. Visible in the rendered shots as a straight
	# horizontal line well above the horizon.
	sky_material.sky_curve = 0.45
	sky_material.ground_horizon_color = ground_horizon
	sky_material.ground_bottom_color = ground_bottom
	sky_material.ground_curve = 0.2
	sky_material.sun_angle_max = 6.0
	sky_material.sun_curve = 0.08

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky

	# Ambient light from the sky rather than a flat colour, so shaded slopes pick
	# up the sky's blue and do not go uniformly grey.
	#
	# Scaled down rather than left at full strength. The sky is bright, and full sky
	# ambient fills every shadow until the faceting that makes low-poly terrain read
	# disappears into a flat wash. Enough fill to keep shadowed faces coloured, not
	# enough to erase the difference between them. Set together with sun_energy for
	# the same reason: see the note there.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 1.0
	environment.ambient_light_energy = 0.25
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

	# Linear tonemapping at a white point of 1.0, not a filmic curve at 1.6.
	#
	# The filmic curve lifts midtones hard, which is right for HDR content where 1.0
	# is mid-grey and the highlights need somewhere to go. This project is neither:
	# the palette is chosen as final display colours, and the whole point of a
	# stylized low-poly look is that a face's colour is the colour that was picked for
	# it. At filmic/1.6 the mountains' rock, which is a mid grey-blue at #585a6f,
	# rendered as near-white — the terrain generator was correct and the tonemapper was
	# throwing the art direction away.
	#
	# Linear also keeps saturation, which filmic desaturates as it rolls off.
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_white = 1.0

	_world_environment = WorldEnvironment.new()
	_world_environment.name = "WorldEnvironment"
	_world_environment.environment = environment
	add_child(_world_environment)