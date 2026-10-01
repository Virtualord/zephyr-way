## Translates the Godot InputMap into a per-step [FlightCommand].
##
## Kept separate from FlightModel so flight dynamics never touch input devices,
## and so a replay, autopilot or test can substitute commands later without
## changing the model.
##
## Actions are read through [method Input.get_action_strength], which already
## applies deadzone and returns analogue values from gamepad sticks and triggers.
## Keyboard axes are smoothed here so a digital keypress ramps rather than snaps.
class_name FlightInput
extends Node

## Negative and positive input actions for each axis. Actions may be a key, an
## axis or a button; they are summed and clamped.
@export var pitch_down_actions: Array[StringName] = [&"pitch_down", &"pitch_down_arrow"]
@export var pitch_up_actions: Array[StringName] = [&"pitch_up", &"pitch_up_arrow"]
@export var roll_left_actions: Array[StringName] = [&"roll_left", &"roll_left_arrow"]
@export var roll_right_actions: Array[StringName] = [&"roll_right", &"roll_right_arrow"]
@export var yaw_left_actions: Array[StringName] = [&"yaw_left"]
@export var yaw_right_actions: Array[StringName] = [&"yaw_right"]

@export var throttle_up_actions: Array[StringName] = [&"throttle_up"]
@export var throttle_down_actions: Array[StringName] = [&"throttle_down"]

## Gamepad trigger axis mapped to absolute throttle position. Optional.
@export var throttle_axis_action: StringName = &"throttle_axis"

@export var airbrake_actions: Array[StringName] = [&"airbrake"]

## Seconds for a held digital key to travel from centre to full deflection.
## Gamepad input bypasses smoothing because it is already analogue.
##
## Left unset here by default so [member FlightTuning.axis_smoothing_time] is the
## single source of truth. Assign it directly only to override tuning, e.g. in a
## test that needs a fixed lag.
@export_range(0.0, 1.0, 0.01) var axis_smoothing_time_override: float = 0.0

var _axis_smoothing_time := 0.14

## Reused every frame so the hot path does not allocate.
var command := FlightCommand.new()

var _pitch := 0.0
var _roll := 0.0
var _yaw := 0.0
## True while a gamepad trigger is driving the throttle. Latched so releasing the
## trigger returns control to the keyboard instead of sticking at the last value.
var _throttle_is_analogue := false


func _ready() -> void:
	resolve_smoothing_time()


## Sample the InputMap and update [member command].
func poll(delta: float) -> FlightCommand:
	var step := delta / _axis_smoothing_time
	_pitch = move_toward(_pitch, _axis(pitch_up_actions, pitch_down_actions), step)
	_roll = move_toward(_roll, _axis(roll_right_actions, roll_left_actions), step)
	_yaw = move_toward(_yaw, _axis(yaw_right_actions, yaw_left_actions), step)

	command.pitch = _pitch
	command.roll = _roll
	command.yaw = _yaw
	command.throttle_delta = _throttle_rate()
	command.throttle_target = _throttle_position()
	command.airbrake = _is_pressed(airbrake_actions)
	return command


## Zero the smoothed axes, e.g. when the aircraft is respawned mid-turn.
func reset() -> void:
	_pitch = 0.0
	_roll = 0.0
	_yaw = 0.0
	_throttle_is_analogue = false
	command.clear()


## Positive minus negative action strength, clamped to [-1, 1].
func _axis(positive: Array[StringName], negative: Array[StringName]) -> float:
	return clampf(_strength(positive) - _strength(negative), -1.0, 1.0)


func _strength(actions: Array[StringName]) -> float:
	var total := 0.0
	for action in actions:
		if InputMap.has_action(action):
			total += Input.get_action_strength(action)
	return minf(total, 1.0)


func _is_pressed(actions: Array[StringName]) -> bool:
	for action in actions:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			return true
	return false


## Digital throttle request: +1 while raising, -1 while lowering.
func _throttle_rate() -> float:
	var raise := _is_pressed(throttle_up_actions)
	var lower := _is_pressed(throttle_down_actions)
	return (1.0 if raise else 0.0) - (1.0 if lower else 0.0)


## Point the smoothing time at the tuning Resource, which owns the value.
## Called by [method _ready] and safe to call again after assigning `tuning`.
func resolve_smoothing_time() -> void:
	if axis_smoothing_time_override > 0.0:
		_axis_smoothing_time = axis_smoothing_time_override
	elif tuning != null:
		_axis_smoothing_time = tuning.axis_smoothing_time
	_axis_smoothing_time = maxf(_axis_smoothing_time, 0.01)


## Active smoothing time in seconds.
func axis_smoothing_time() -> float:
	return _axis_smoothing_time


## Flight tuning, consulted for [member axis_smoothing_time]. Optional so the
## input layer can be tested on its own.
var tuning: FlightTuning


## Absolute throttle position from a gamepad trigger, or [constant
## FlightCommand.NO_ABSOLUTE] when no trigger is active.
func _throttle_position() -> float:
	if InputMap.has_action(throttle_axis_action):
		var value := Input.get_action_strength(throttle_axis_action)
		if value > ANALOGUE_THRESHOLD:
			_throttle_is_analogue = true
			return clampf(value, 0.0, 1.0)

	if _throttle_is_analogue:
		_throttle_is_analogue = false
	return FlightCommand.NO_ABSOLUTE


const ANALOGUE_THRESHOLD := 0.02