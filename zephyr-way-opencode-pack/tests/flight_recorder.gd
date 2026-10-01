## Flight recording and replay, for playtesting without re-flying every time.
##
## A playthrough takes real time and is hard to describe precisely. Recording the
## aircraft's state each physics tick makes flight feel reproducible: a bad
## moment can be replayed exactly, and a tuning change can be compared against
## identical input.
##
## This is a development tool, not a game feature. It lives in tests/ rather than
## scripts/ so it is obvious it is not part of the runtime, and it depends on no
## scene nodes: the caller feeds it commands and state.
##
## [codeblock]
## var recorder := FlightRecorder.new()
## recorder.begin()
## for tick in ticks:
##     recorder.capture(command, state, delta)
## recorder.summary()
## [/codeblock]
class_name FlightRecorder
extends RefCounted

## One simulation tick of recorded input and resulting aircraft state.
class Frame extends RefCounted:
	## Seconds since recording began.
	var time: float = 0.0
	## Pilot input for this tick.
	var pitch: float = 0.0
	var roll: float = 0.0
	var yaw: float = 0.0
	var throttle_delta: float = 0.0
	## Absolute throttle, or FlightCommand.NO_ABSOLUTE for rate-based input.
	var throttle_target: float = -1.0
	var airbrake: bool = false
	## Aircraft response, kept for comparison rather than replay.
	var airspeed: float = 0.0
	var altitude: float = 0.0
	var heading_degrees: float = 0.0
	var pitch_degrees: float = 0.0
	var roll_degrees: float = 0.0
	var grounded: bool = true

	## Command equivalent to this frame's recorded input.
	func to_command() -> FlightCommand:
		var command := FlightCommand.new()
		command.pitch = pitch
		command.roll = roll
		command.yaw = yaw
		command.throttle_delta = throttle_delta
		command.throttle_target = throttle_target
		command.airbrake = airbrake
		return command


## Emitted after every captured tick.
signal recorded(frame: Frame)
## Emitted after a replay completes.
signal replayed(state: FlightState)

## Longest recording to keep, so a forgotten recorder cannot grow without bound.
var max_ticks := 60 * 60 * 10

var _frames: Array[Frame] = []


## Discard any previous recording.
func begin() -> void:
	_frames.clear()


## Record one tick. Returns false once [member max_ticks] is spent, at which point
## recording silently stops rather than dropping frames in the middle of a replay.
func capture(command: FlightCommand, state: FlightState, delta: float) -> bool:
	if _frames.size() >= max_ticks:
		return false

	var frame := Frame.new()
	frame.time = _frames.size() * delta
	if command != null:
		frame.pitch = command.pitch
		frame.roll = command.roll
		frame.yaw = command.yaw
		frame.throttle_delta = command.throttle_delta
		frame.throttle_target = command.throttle_target
		frame.airbrake = command.airbrake
	if state != null:
		frame.airspeed = state.airspeed
		frame.altitude = state.altitude
		frame.heading_degrees = state.heading_degrees
		frame.pitch_degrees = state.pitch_degrees
		frame.roll_degrees = state.roll_degrees
		frame.grounded = state.grounded

	_frames.append(frame)
	recorded.emit(frame)
	return true


func frames() -> Array[Frame]:
	return _frames


func tick_count() -> int:
	return _frames.size()


## Length of the recording in seconds, from the number of frames and the tick
## rate they were captured at.
func duration(delta: float) -> float:
	return _frames.size() * delta


## One-line summary, for comparing two recordings at a glance.
func summary(delta: float = 1.0 / 60.0) -> String:
	if _frames.is_empty():
		return "no frames recorded"
	var last := _frames[_frames.size() - 1]
	return "%d ticks over %.1f s, ending at %.0f kt / %.0f m / %.0f deg" % [
		_frames.size(),
		duration(delta),
		Units.mps_to_knots(last.airspeed),
		last.altitude,
		last.heading_degrees,
	]


## Replay the recording through `model` into `state`, using the given terrain
## height as the ground.
##
## Input devices are not involved, so the same recording under different tuning
## isolates the effect of the tuning itself. The returned state is the one passed
## in, advanced to the end of the recording.
func replay(model: FlightModel, state: FlightState, delta: float, ground_height := 0.0) -> FlightState:
	for frame in _frames:
		model.step(state, frame.to_command(), delta, ground_height)
		replayed.emit(state)
	return state


## Peaks across the recording, for spotting where a manoeuvre was most extreme.
func peaks(delta: float) -> Dictionary:
	if _frames.is_empty():
		return {}
	var max_speed := 0.0
	var max_altitude := -INF
	var min_altitude := INF
	var max_bank := 0.0
	for frame in _frames:
		max_speed = maxf(max_speed, frame.airspeed)
		max_altitude = maxf(max_altitude, frame.altitude)
		min_altitude = minf(min_altitude, frame.altitude)
		max_bank = maxf(max_bank, absf(frame.roll_degrees))
	return {
		"ticks": _frames.size(),
		"duration_s": duration(delta),
		"max_speed_knots": Units.mps_to_knots(max_speed),
		"max_altitude_m": max_altitude,
		"min_altitude_m": min_altitude,
		"max_bank_degrees": max_bank,
	}