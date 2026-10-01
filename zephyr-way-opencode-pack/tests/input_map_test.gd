## Flight checks that must hold with the real project input map loaded.
##
## The flight model tests drive commands directly, so they cannot catch a missing
## or misnamed InputMap action. This loads project.godot's actual [input] section
## and checks that every action FlightInput reads exists, is wired to at least
## one event, and that FlightInput produces the axes it advertises.
##
## [codeblock]
## godot --headless --path . --script res://tests/input_map_test.gd
## [/codeblock]
extends SceneTree

## Actions FlightInput reads by default. Keep in sync with its exported defaults.
const EXPECTED_ACTIONS := [
	&"pitch_up",
	&"pitch_down",
	&"roll_left",
	&"roll_right",
	&"yaw_left",
	&"yaw_right",
	&"throttle_up",
	&"throttle_down",
	&"throttle_axis",
	&"airbrake",
]

var _failures := 0
var _checks := 0


func _initialize() -> void:
	print("Input map checks")

	for action in EXPECTED_ACTIONS:
		_check("action '%s' exists" % action, InputMap.has_action(action))
		if not InputMap.has_action(action):
			continue
		_check(
			"action '%s' has an event" % action,
			not InputMap.action_get_events(action).is_empty()
		)

	_check("reset action exists", InputMap.has_action(&"reset_aircraft"))

	# FlightInput skips unknown actions silently so a stripped export still runs.
	# That is a robustness feature, but it also means a typo would be silent, so
	# assert against it here.
	var flight_input := FlightInput.new()
	_check("FlightInput instantiates", flight_input != null)
	_check("FlightInput default axes are known actions", _all_actions_known(flight_input))

	# With nothing pressed, every axis must be neutral and the command must carry
	# no absolute throttle.
	var command := flight_input.poll(STEP)
	_check("neutral pitch", is_zero_approx(command.pitch), "%.3f" % command.pitch)
	_check("neutral roll", is_zero_approx(command.roll), "%.3f" % command.roll)
	_check("neutral yaw", is_zero_approx(command.yaw), "%.3f" % command.yaw)
	_check("neutral throttle delta", is_zero_approx(command.throttle_delta))
	_check("no absolute throttle target", not command.has_throttle_target())
	_check("airbrake released", not command.airbrake)

	# Reused instance: the hot path must not allocate a command per frame.
	_check("command instance is reused", flight_input.poll(STEP) == command)

	flight_input.free()

	if _failures == 0:
		print("  %d checks passed" % _checks)
	quit(0 if _failures == 0 else 1)


func _all_actions_known(flight_input: FlightInput) -> bool:
	var lists: Array = [
		flight_input.pitch_up_actions,
		flight_input.pitch_down_actions,
		flight_input.roll_left_actions,
		flight_input.roll_right_actions,
		flight_input.yaw_left_actions,
		flight_input.yaw_right_actions,
		flight_input.throttle_up_actions,
		flight_input.throttle_down_actions,
		flight_input.airbrake_actions,
	]
	for list: Array in lists:
		for action: StringName in list:
			if not InputMap.has_action(action):
				return false
	return InputMap.has_action(flight_input.throttle_axis_action)


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s%s" % [label, (" (%s)" % detail) if detail != "" else ""])


const STEP := 1.0 / 60.0