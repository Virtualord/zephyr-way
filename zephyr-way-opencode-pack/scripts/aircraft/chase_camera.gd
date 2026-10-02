## Third-person chase camera.
##
## A deliberately simple follow rig: the camera sits at a fixed offset behind and
## above the aircraft, the offset is smoothed with frame-rate independent decay,
## and the rig inherits part of the aircraft's own roll. That inheritance is what
## makes a banked turn feel banked from the chase view.
##
## All smoothing uses [code]1 - exp(-delta / time)[/code], so the feel is
## identical at 30, 60 or 144 FPS. Look-ahead pushes the aim point along the
## velocity vector, which keeps the nose on the horizon in fast flight.
##
## Kept separate from the aircraft: this node has no children of its own and
## reads the aircraft through [member AircraftController.state], so gameplay and
## presentation never depend on each other.
class_name ChaseCamera
extends Camera3D

## Aircraft to follow.
@export var target: Node3D

## Offset from the target in the target's local space. Local -Z is behind the nose.
@export var local_offset := Vector3(0.0, 2.6, 11.0)

## Seconds for the camera to close most of the gap to its ideal position.
## Lower is tighter and more responsive; higher is smoother and more cinematic.
@export_range(0.01, 2.0, 0.01) var follow_time: float = 0.16

## Seconds for the aim point to catch up. Slightly longer than follow_time so the
## camera settles rather than jitters.
@export_range(0.01, 2.0, 0.01) var aim_time: float = 0.22

## How much of the aircraft's roll the camera adopts, 0 to 1. The reference look
## sits near 0.55: enough to feel the bank, not enough to disorient.
@export_range(0.0, 1.0, 0.01) var roll_influence: float = 0.55

## Metres of aim lead per m/s of airspeed. 0 disables look-ahead.
@export_range(0.0, 2.0, 0.01) var look_ahead: float = 0.22

## Extra height at maximum airspeed, so fast flight sits lower and reads faster.
@export_range(0.0, 6.0, 0.05) var speed_height_bias: float = 1.1
## Vertical field of view at zero airspeed and at full speed. Widening with speed
## is the cheapest convincing speed cue available. Names are suffixed to avoid
## colliding with Camera3D's own `fov` property.
@export_range(30.0, 110.0, 0.5) var idle_fov: float = 62.0
@export_range(30.0, 110.0, 0.5) var speed_fov: float = 74.0
## Airspeed in m/s at which the speed biases reach full effect.
@export_range(10.0, 200.0, 1.0) var speed_bias_reference: float = 75.0

## Minimum height of the camera above its aim point, so a low pass never puts the
## camera inside the terrain.
@export_range(0.0, 20.0, 0.1) var minimum_height: float = 1.6

## When true the camera stops following the aircraft and holds its own transform.
##
## For looking at the world rather than the aircraft: a terrain review needs a
## viewpoint 3 km up, and a chase camera will drag it back behind the plane every
## frame. Set from code rather than bound to a key, since it is a review tool and not
## something to ship in the cockpit.
var detached := false

var _aim_point := Vector3.ZERO
var _initialised := false


func _ready() -> void:
	fov = idle_fov


## Snap the camera to its ideal pose with no smoothing. Call after a teleport or
## respawn, where easing from the old position would fly the camera across the map.
func snap_to_target() -> void:
	var state := _state()
	if state == null:
		return
	global_position = state.position + _ideal_offset(state.airspeed)
	_aim_point = state.position
	_apply_orientation()
	_initialised = true


func _process(delta: float) -> void:
	var state := _state()
	if state == null:
		return
	# Detached: the camera holds whatever pose it was given and ignores the aircraft.
	# Used for art review, where the subject is the world rather than the plane.
	if detached:
		return
	if not _initialised:
		snap_to_target()
		return

	var speed := state.airspeed
	global_position = global_position.lerp(
		state.position + _ideal_offset(speed),
		_blend(delta, follow_time)
	)

	var aim := _desired_aim(state, speed)
	_aim_point = _aim_point.lerp(aim, _blend(delta, aim_time))

	# Keep the camera above its aim point on a low pass.
	var floor_y := _aim_point.y + minimum_height
	if global_position.y < floor_y:
		global_position.y = floor_y

	_apply_orientation()
	fov = lerpf(idle_fov, speed_fov, _speed_ratio(speed))


## Camera offset in world space.
##
## The aircraft's basis is used for the lateral and fore/aft components so the
## camera sits behind the tail, and the roll is applied separately so
## [member roll_influence] can hold it partly level.
func _ideal_offset(speed: float) -> Vector3:
	var state := _state()
	if state == null:
		return local_offset

	var level := Basis.looking_at(Vector3(0.0, 0.0, -1.0), Vector3.UP)
	var rolled := _basis_with_partial_roll(state.basis, roll_influence)
	var oriented := rolled.orthonormalized().slerp(level, 0.0)

	var offset := local_offset
	offset.y += speed_height_bias * _speed_ratio(speed)
	return oriented * offset


## Basis rolled by `influence` of the aircraft's own roll.
func _basis_with_partial_roll(source: Basis, influence: float) -> Basis:
	var roll := Units.roll_of(source) * Units.DEG_TO_RAD * clampf(influence, 0.0, 1.0)
	return Basis(Vector3(0.0, 0.0, -1.0), roll) * source


func _desired_aim(state: FlightState, speed: float) -> Vector3:
	if speed < MIN_LEAD_SPEED:
		return state.position
	return state.position + (state.velocity / speed) * speed * look_ahead


func _apply_orientation() -> void:
	if global_position.distance_squared_to(_aim_point) > MIN_AIM_DISTANCE_SQUARED:
		look_at(_aim_point, Vector3.UP)


func _speed_ratio(speed: float) -> float:
	return clampf(speed / maxf(speed_bias_reference, 1.0), 0.0, 1.0)


## Aircraft state, or null when no valid target is assigned.
##
## The target may be the controller itself or a parent of it, so both are
## accepted. This keeps the camera usable whether it is pointed at the aircraft
## root or at the flight node.
func _state() -> FlightState:
	if target == null or not is_instance_valid(target):
		return null
	if target is AircraftController:
		return target.state
	var controller := target.get_node_or_null(^"FlightController") as AircraftController
	return controller.state if controller != null else null


## Weight that closes `1 - exp(-delta / time)` of the remaining gap.
func _blend(delta: float, time: float) -> float:
	return 1.0 - exp(-delta / maxf(time, 0.001))


const MIN_LEAD_SPEED := 0.5
const MIN_AIM_DISTANCE_SQUARED := 0.01