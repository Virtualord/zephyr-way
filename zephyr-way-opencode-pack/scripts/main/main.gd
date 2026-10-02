## Entry point for the playable slice.
##
## Assembles the island, the aircraft and the chase camera, and owns the handful of
## things that need to know about all three: where the aircraft starts, and
## resetting it.
##
## The world is a scene reference rather than a hard-coded type wherever possible,
## so `TestEnvironment` can be swapped back in for the flat test bed without
## touching this script. Both expose `ground_height_at`, which is the entire
## contract between the world and the flight model.
class_name Main
extends Node3D

## World scene to instantiate. Must expose `ground_height_at(Vector3) -> float`.
@export var world_scene: PackedScene
## Aircraft scene to spawn.
@export var aircraft_scene: PackedScene
## Camera scene to spawn.
@export var chase_camera_scene: PackedScene

@onready var aircraft: AircraftController = $Aircraft/FlightController

var world: Node3D
var _chase_camera: ChaseCamera


func _ready() -> void:
	_resolve_world()
	_place_aircraft()
	_spawn_camera()
	_connect_respawn()
	print("[Zephyr Way] Ready. Pitch: W/S, Roll: A/D, Yaw: Q/E, Throttle: Shift/Ctrl, Airbrake: Space, Reset: R")


## Find the world this scene is running over.
##
## The world node is already in the scene tree rather than instantiated here, because
## the island builds terrain in `_ready` and the aircraft samples its height in its
## own `_ready`; spawning it later would mean a frame of the aircraft falling through
## ground that does not exist yet.
##
## [member world_scene] is therefore only a declaration of which world is expected,
## and is used to find the node by name. That keeps the contract explicit — if the
## scene and the declaration disagree, this says so — without duplicating the node.
func _resolve_world() -> void:
	if world != null:
		return
	if world_scene == null:
		push_warning("Main: no world_scene set; the aircraft will fly over flat ground at y=0.")
		return

	var expected := world_scene.resource_path.get_file().get_basename()
	world = get_node_or_null(NodePath(expected)) as Node3D
	if world == null:
		push_warning("Main: world_scene is set but no '%s' node is in the scene." % expected)
		return
	if not world.has_method(&"ground_height_at"):
		push_warning("Main: '%s' has no ground_height_at(); the aircraft cannot land." % expected)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"reset_aircraft"):
		reset_aircraft()


## Spawn position for the aircraft.
##
## On the island this is the airport plateau, at the position the design specifies.
## The world origin would be a poor choice on generated terrain, since it may well be
## underwater and means nothing to a player.
##
## The aircraft is placed exactly on the surface, not above it. A scene-authored
## transform is not good enough: the terrain is generated at runtime, so any height
## written into the scene file is a guess that will be wrong as soon as the seed
## changes. Spawning high enough to be safe would mean dropping onto the runway on
## the first frame.
func _place_aircraft() -> void:
	if world == null:
		aircraft.respawn()
		return

	var start := _find_start_point()
	aircraft.start_position = Vector3(
		start.x,
		_call_ground_height(Vector3(start.x, 0.0, start.y)),
		start.y
	)
	aircraft.start_heading_degrees = _start_heading()
	aircraft.respawn()


## Heading the aircraft starts facing, in degrees.
##
## Aligned with the runway so the player begins pointed down it rather than across
## it. Milestone 05 builds the runway itself; this only needs the design's number.
func _start_heading() -> float:
	var island := world as Island
	if island == null or island.generator == null:
		return 0.0
	return island.generator.airport_heading_degrees


## Where to start: the airport plateau, since the design fixes its position and the
## terrain generator flattens it deliberately.
func _find_start_point() -> Vector2:
	var island := world as Island
	if island != null and island.generator != null:
		return island.generator.airport_position
	return Vector2.ZERO


## Spiral search for somewhere flat and above the waterline.
func _flat_dry_point_near(centre: Vector2, max_radius: float) -> Vector2:
	for ring in 8:
		var radius := max_radius * float(ring) / 8.0
		var samples := 8 * maxi(ring, 1)
		for index in samples:
			var angle := TAU * float(index) / float(samples)
			var point := centre + Vector2(cos(angle), sin(angle)) * radius
			var height := _call_ground_height(Vector3(point.x, 0.0, point.y))
			if height > 20.0:
				# Flatness matters more than exact flatness: a plateau edge is fine.
				var slope := _call_slope(point)
				if slope < 0.12:
					return point
	return Vector2.ZERO


## Calls `ground_height_at` when the world provides it.
func _call_ground_height(position: Vector3) -> float:
	if world != null and world.has_method(&"ground_height_at"):
		return float(world.call(&"ground_height_at", position))
	return 0.0


func _call_slope(point: Vector2) -> float:
	var island := world as Island
	if island != null and island.generator != null:
		return island.generator.slope_at(point.x, point.y)
	return 0.0


## Return the aircraft to its start pose and snap the camera with it, so the view
## does not sweep across the map from wherever the aircraft was.
func reset_aircraft() -> void:
	aircraft.respawn()
	if _chase_camera != null:
		_chase_camera.snap_to_target()


func _spawn_camera() -> void:
	if chase_camera_scene == null:
		push_warning("Main: chase_camera_scene is not set; the camera will not follow the aircraft.")
		return
	_chase_camera = chase_camera_scene.instantiate() as ChaseCamera
	if _chase_camera == null:
		push_warning("Main: chase_camera_scene did not instantiate a ChaseCamera.")
		return
	_chase_camera.target = aircraft
	add_child(_chase_camera)
	_chase_camera.snap_to_target()


func _connect_respawn() -> void:
	aircraft.respawned.connect(_on_aircraft_respawned)


func _on_aircraft_respawned(_state: FlightState) -> void:
	if _chase_camera != null:
		_chase_camera.snap_to_target()