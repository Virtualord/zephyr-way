## Pilot input for one simulation step.
##
## A plain value object on purpose: FlightInput fills and reuses a single
## instance every frame so the hot path never allocates, and tests can build a
## command by hand with no scene tree or input device involved.
class_name FlightCommand
extends RefCounted

## Sentinel for "no absolute throttle requested this step".
const NO_ABSOLUTE := -1.0

## Stick positions, all normalised to [-1, 1] with +1 being the positive
## direction: pitch up, roll right, yaw nose-right.
var pitch: float = 0.0
var roll: float = 0.0
var yaw: float = 0.0

## Throttle rate request this step, [-1, 1]. Used for digital input, where a key
## nudges the throttle rather than placing it.
var throttle_delta: float = 0.0

## Absolute throttle target in [0, 1], or [constant NO_ABSOLUTE] for digital
## input. Used for gamepad triggers, which are already a position.
var throttle_target: float = NO_ABSOLUTE

## True while the airbrake / wheel brake is held. On the ground this is a wheel
## brake; airborne it becomes a drag brake.
var airbrake: bool = false


func clear() -> void:
	pitch = 0.0
	roll = 0.0
	yaw = 0.0
	throttle_delta = 0.0
	throttle_target = NO_ABSOLUTE
	airbrake = false


## True when the command carries an absolute throttle position.
func has_throttle_target() -> bool:
	return throttle_target >= 0.0


## Convenience for tests and scripted manoeuvres.
static func make(pitch_input := 0.0, roll_input := 0.0, yaw_input := 0.0) -> FlightCommand:
	var command := FlightCommand.new()
	command.pitch = pitch_input
	command.roll = roll_input
	command.yaw = yaw_input
	return command