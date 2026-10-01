## Reproducibility checks for FlightRecorder.
##
## The recorder is only useful if a replay is exact, so these tests pin the
## property that matters: replaying a recording twice produces identical state,
## and replaying under different tuning produces the *same input* while allowing
## a different result.
##
## [codeblock]
## godot --headless --path . --script res://tests/recorder_test.gd
## [/codeblock]
extends SceneTree

const STEP := 1.0 / 60.0

var _failures := 0
var _checks := 0


func _initialize() -> void:
	print("Recorder checks")

	_check_capture_and_replay()
	_check_replay_is_deterministic()
	_check_tuning_changes_result_not_input()
	_check_peaks_and_summary()
	_check_budget_limit()

	if _failures == 0:
		print("  %d checks passed" % _checks)
	quit(0 if _failures == 0 else 1)


## Fly a manoeuvre into a recorder: full throttle, then a rolling turn.
func _fly_manoeuvre(recorder: FlightRecorder, model: FlightModel, state: FlightState) -> void:
	state.position = Vector3(0.0, 400.0, 0.0)
	state.velocity = Vector3(0.0, 0.0, -40.0)
	state.grounded = false

	recorder.begin()
	for tick in 180:
		var command := FlightCommand.make()
		command.throttle_delta = 1.0 if tick < 60 else 0.0
		command.pitch = 0.2
		command.roll = 0.8 if tick >= 60 else 0.0
		command.yaw = -0.2
		model.step(state, command, STEP, 0.0)
		recorder.capture(command, state, STEP)


func _check_capture_and_replay() -> void:
	var model := FlightModel.new()
	var state := FlightState.new()
	var recorder := FlightRecorder.new()
	_fly_manoeuvre(recorder, model, state)

	_check("recorder captured frames", recorder.tick_count() == 180, "got %d" % recorder.tick_count())
	_check("summary reports a length", recorder.summary(STEP).contains("180 ticks"))
	_check("frames advance in time", recorder.frames()[1].time > recorder.frames()[0].time)

	# Replay must land the aircraft somewhere plausible, not simply echo the input.
	var replay_model := FlightModel.new()
	var replay_state := FlightState.new()
	replay_state.position = Vector3(0.0, 400.0, 0.0)
	replay_state.velocity = Vector3(0.0, 0.0, -40.0)
	replay_state.grounded = false
	recorder.replay(replay_model, replay_state, STEP, 0.0)
	_check("replay produced motion", replay_state.position.length() > 1.0)
	_check("replay stays finite", is_finite(replay_state.position.length()))


## The property that makes a recording worth having.
func _check_replay_is_deterministic() -> void:
	var model := FlightModel.new()
	var state := FlightState.new()
	var recorder := FlightRecorder.new()
	_fly_manoeuvre(recorder, model, state)

	var first := FlightState.new()
	first.position = Vector3(0.0, 400.0, 0.0)
	first.velocity = Vector3(0.0, 0.0, -40.0)
	first.grounded = false
	recorder.replay(FlightModel.new(), first, STEP, 0.0)

	var second := FlightState.new()
	second.position = Vector3(0.0, 400.0, 0.0)
	second.velocity = Vector3(0.0, 0.0, -40.0)
	second.grounded = false
	recorder.replay(FlightModel.new(), second, STEP, 0.0)

	_check(
		"replaying twice gives identical position",
		first.position.is_equal_approx(second.position),
		"%v vs %v" % [first.position, second.position]
	)
	_check("replaying twice gives identical velocity", first.velocity.is_equal_approx(second.velocity))


## Input is held constant while tuning varies, which is the whole point of
## comparing recordings.
func _check_tuning_changes_result_not_input() -> void:
	var model := FlightModel.new()
	var state := FlightState.new()
	var recorder := FlightRecorder.new()
	_fly_manoeuvre(recorder, model, state)

	var original_commands := recorder.frames()[100].to_command()
	_check("recorded input survives capture", is_equal_approx(original_commands.roll, 0.8))
	_check("recorded throttle rate is preserved", is_zero_approx(original_commands.throttle_delta))

	# A slower aircraft under the same input should end up lower or slower.
	var slow_model := FlightModel.new()
	slow_model.tuning.acceleration = model.tuning.acceleration * 0.5
	var slow_state := FlightState.new()
	slow_state.position = Vector3(0.0, 400.0, 0.0)
	slow_state.velocity = Vector3(0.0, 0.0, -40.0)
	slow_state.grounded = false
	recorder.replay(slow_model, slow_state, STEP, 0.0)
	_check(
		"weaker thrust under identical input flies differently",
		not slow_state.position.is_equal_approx(state.position)
	)


func _check_peaks_and_summary() -> void:
	var empty := FlightRecorder.new()
	_check("empty summary says so", empty.summary(STEP) == "no frames recorded")
	_check("empty peaks is empty", empty.peaks(STEP).is_empty())

	var model := FlightModel.new()
	var state := FlightState.new()
	var recorder := FlightRecorder.new()
	_fly_manoeuvre(recorder, model, state)

	var peaks := recorder.peaks(STEP)
	_check("peaks report a tick count", peaks["ticks"] == 180)
	_check("peaks report a positive max speed", peaks["max_speed_knots"] > 0.0)
	_check("peaks report a real altitude range", peaks["max_altitude_m"] >= peaks["min_altitude_m"])
	_check("peaks report a bank angle", peaks["max_bank_degrees"] > 1.0)


## A forgotten recorder must stop rather than grow without bound.
func _check_budget_limit() -> void:
	var recorder := FlightRecorder.new()
	recorder.max_ticks = 3
	recorder.begin()

	var state := FlightState.new()
	state.position = Vector3(0.0, 100.0, 0.0)
	var accepted := 0
	for tick in 10:
		if recorder.capture(FlightCommand.make(), state, STEP):
			accepted += 1
	_check("capture stops at the budget", accepted == 3, "accepted %d" % accepted)
	_check("frames are kept up to the budget", recorder.tick_count() == 3)

	recorder.begin()
	_check("begin clears the recording", recorder.tick_count() == 0)


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s%s" % [label, (" (%s)" % detail) if detail != "" else ""])