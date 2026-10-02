## Node that binds the flight simulation to a scene tree.
##
## Owns the transform, owns the [FlightModel], and holds the [FlightState] other
## systems read. Deliberately thin: physics, input, visuals and camera each live
## in their own script, and this is only the wiring between them plus the public
## surface (signals, respawn, state access).
##
## Simulation runs in [method _physics_process] on the fixed tick so flight feel
## is identical regardless of render frame rate. Visual interpolation is not used
## yet; it belongs with the HUD milestone if the physics tick and render rate ever
## diverge enough to show.
class_name AircraftController
extends Node3D

## Emitted after every physics step. Carries the live state object, so listeners
## must read it rather than keep the reference.
signal flight_updated(state: FlightState)

## Emitted on transitions into and out of flight. Useful for audio and effects.
signal took_off(state: FlightState)
signal landed(state: FlightState)

## Emitted when the wing stalls and recovers. `true` on entering the stall.
signal stall_changed(is_stalled: bool)

## Emitted when the pilot resets the aircraft to its start pose.
signal respawned(state: FlightState)

## Initial pose. The aircraft starts on the ground at the origin facing north.
@export var start_position := Vector3.ZERO
@export var start_heading_degrees := 0.0

## Flight tuning. Shared Resource, so every aircraft uses the same feel.
@export var tuning: FlightTuning

## Where terrain height is sampled from. Set by the world scene; when unset the
## model treats the ground as flat at y = 0.
@export var ground_height_sampler_path: NodePath

## Slows the simulation for debugging without changing physics constants.
## 1.0 is real time.
@export_range(0.05, 2.0, 0.05) var time_scale := 1.0

## Current telemetry. The same object is passed to [signal flight_updated].
var state := FlightState.new()

var _model: FlightModel
var _input: FlightInput
var _was_grounded := true
var _was_stalled := false


func _ready() -> void:
	if tuning == null:
		tuning = FlightTuning.new()
	_model = FlightModel.new(tuning)
	_input = get_node_or_null(^"FlightInput") as FlightInput
	if _input == null:
		push_warning("AircraftController: no FlightInput child found; the aircraft will not respond to input.")
	else:
		# Input smoothing is a feel number, so it comes from the same tuning
		# Resource as the flight model rather than being set on the input node.
		_input.tuning = tuning
		_input.resolve_smoothing_time()

	_connect_ground_sampler()
	respawn()


func _physics_process(delta: float) -> void:
	var step := delta * time_scale
	if step <= 0.0:
		return

	var command := _input.poll(step) if _input != null else _idle_command()
	_model.step(state, command, step, NAN)

	# The transform is owned by the simulation, not by the scene graph.
	global_transform = Transform3D(state.basis, state.position)

	_emit_transitions(command)
	flight_updated.emit(state)


## Commands with no input at all, used when FlightInput is missing so the aircraft
## still settles on the ground instead of freezing mid-air.
func _idle_command() -> FlightCommand:
	var command := FlightCommand.new()
	command.throttle_target = state.throttle
	return command


## Return the aircraft to its start pose and clear velocity and control inputs.
func respawn() -> void:
	state.position = start_position
	state.basis = Basis.looking_at(
		Vector3(sin(Units.deg_to_rad(start_heading_degrees)), 0.0, -cos(Units.deg_to_rad(start_heading_degrees))),
		Vector3.UP
	)
	state.velocity = Vector3.ZERO
	state.throttle = 0.0
	state.grounded = true
	state.refresh(_ground_height_at(start_position))

	global_transform = Transform3D(state.basis, state.position)
	if _input != null:
		_input.reset()

	_was_grounded = true
	_was_stalled = false
	respawned.emit(state)
	flight_updated.emit(state)


func _emit_transitions(command: FlightCommand) -> void:
	if state.grounded != _was_grounded:
		_was_grounded = state.grounded
		if state.grounded:
			landed.emit(state)
		else:
			took_off.emit(state)

	var stalled := state.lift_efficiency < STALL_EFFICIENCY_THRESHOLD and not state.grounded
	if stalled != _was_stalled:
		_was_stalled = stalled
		stall_changed.emit(stalled)


func _connect_ground_sampler() -> void:
	if ground_height_sampler_path.is_empty():
		return
	var sampler := get_node_or_null(ground_height_sampler_path)
	if sampler == null:
		push_warning("AircraftController: ground_height_sampler_path points at a missing node.")
		return
	if sampler.has_method(&"ground_height_at"):
		_model.ground_height_sampler = Callable(sampler, &"ground_height_at")
	else:
		push_warning("AircraftController: ground sampler '%s' has no ground_height_at() method." % sampler.name)


## The callable that reports terrain height, if one is connected.
##
## Exposed so the scene wiring can be tested. Whether the aircraft is actually
## sampling the island rather than assuming flat ground is invisible from the flight
## model alone: both behave identically until the terrain has relief.
func ground_height_sampler() -> Callable:
	return _model.ground_height_sampler if _model != null else Callable()


func _ground_height_at(position: Vector3) -> float:
	if _model != null and _model.ground_height_sampler.is_valid():
		return float(_model.ground_height_sampler.call(position))
	return 0.0


## Below this lift efficiency the wing is considered stalled.
const STALL_EFFICIENCY_THRESHOLD := 0.99