## Entry point for the playable slice.
##
## Assembles the three things milestone 1 needs and nothing more: the test
## environment, the aircraft, and the chase camera. Aircraft respawn, input
## actions and the main loop wiring live here so [TestEnvironment] and
## [AircraftController] stay free of scene-graph knowledge.
##
## Deliberately absent for now, per PROMPT_FIRST.md: terrain, ocean, missions,
## HUD, menus, audio and save state. A later milestone adds its own scene beside
## this one rather than growing this script.
class_name Main
extends Node3D

## Aircraft scene to spawn.
@export var aircraft_scene: PackedScene
## Camera scene to spawn.
@export var chase_camera_scene: PackedScene

@onready var environment: TestEnvironment = $TestEnvironment
@onready var aircraft: AircraftController = $Aircraft/FlightController

var _chase_camera: ChaseCamera


func _ready() -> void:
	_spawn_camera()
	_connect_respawn()
	print("[Zephyr Way] Ready. Pitch: W/S, Roll: A/D, Yaw: Q/E, Throttle: Shift/Ctrl, Airbrake: Space, Reset: R")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"reset_aircraft"):
		reset_aircraft()


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