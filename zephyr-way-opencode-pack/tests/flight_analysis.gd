## Flight-envelope measurement, for tuning rather than for pass/fail.
##
## Unlike the other suites this one asserts almost nothing. It flies a set of
## standard manoeuvres and prints the numbers, because flight feel is a design
## decision and the useful output is a measurement to compare against the last
## run, not a pass or fail.
##
## Run before and after changing [FlightTuning]:
## [codeblock]
## godot --headless --path . --script res://tests/flight_analysis.gd
## [/codeblock]
##
## The one check that does assert is the structural invariant: lift must still
## cancel gravity at cruise speed. Everything else is reporting.
extends SceneTree

const STEP := 1.0 / 60.0

## Thresholds are advisory targets, chosen to match how a light arcade aircraft
## should behave. They are printed rather than enforced so that tuning away from
## them is a deliberate act.
const TARGET := {
	"takeoff_roll_m": 250.0,
	"takeoff_seconds": 12.0,
	"climb_mps": 5.0,
	"bank_45": 8.0,
	"time_to_90_deg_s": 1.1,
}


func _initialize() -> void:
	var tuning := FlightTuning.new()
	print("=== Flight envelope (defaults) ===")
	print("thrust %.1f m/s^2, lift_gain %.6f, drag %.6f" % [
		tuning.acceleration, tuning.lift_gain(), tuning.drag_coefficient()
	])
	print("cruise %.0f kt, max %.0f kt, stall %.0f kt" % [
		tuning.cruise_speed_knots, tuning.max_speed_knots, tuning.stall_speed_knots
	])
	print("")

	_report("Takeoff", _measure_takeoff(tuning))
	_report("Climb", _measure_climb(tuning))
	_report("Cruise", _measure_cruise(tuning))
	_report("Stall", _measure_stall(tuning))
	_report("Roll", _measure_roll(tuning))
	_report("Turn", _measure_turn(tuning))
	_report("Response", _measure_response(tuning))
	_report("Descent and landing", _measure_landing(tuning))
	_report("Level flight stability", _measure_stability(tuning))

	_check_structural_invariants(tuning)
	quit()


## Flight test bed: a model plus a state parked on flat ground.
class Bench extends RefCounted:
	var model: FlightModel
	var state: FlightState

	func _init(tuning: FlightTuning) -> void:
		model = FlightModel.new(tuning)
		state = FlightState.new()
		state.position = Vector3(0.0, tuning.gear_height, 0.0)
		state.velocity = Vector3.ZERO
		state.grounded = true

	func run(seconds: float, command: FlightCommand, throttle: float) -> void:
		state.throttle = throttle
		var steps := int(round(seconds / STEP))
		for _step in steps:
			model.step(state, command, STEP, 0.0)

	func airborne(seconds: float, speed_mps: float, command: FlightCommand, throttle: float) -> void:
		state.position = Vector3(0.0, 500.0, 0.0)
		state.velocity = Vector3(0.0, 0.0, -speed_mps)
		state.grounded = false
		run(seconds, command, throttle)

	func set_speed(speed_mps: float) -> void:
		state.velocity = Vector3(0.0, 0.0, -speed_mps)


func _measure_takeoff(tuning: FlightTuning) -> Dictionary:
	var bench := Bench.new(tuning)
	# Rotate gently through the take-off roll. The aircraft also lifts off on its
	# own once it is fast enough, so this input is an aid, not the mechanism.
	var command := FlightCommand.make()
	command.pitch = 0.16
	command.throttle_target = 1.0

	var start_z := bench.state.position.z
	var seconds := 0.0
	var lift_off := false
	var lift_off_speed := 0.0

	# 40 s is far longer than any healthy take-off, so a failure shows up as a
	# timeout rather than as a silent no-op.
	for _step in 2400:
		bench.model.step(bench.state, command, STEP, 0.0)
		seconds += STEP
		if not bench.state.grounded:
			lift_off = true
			lift_off_speed = bench.state.airspeed
			break

	var roll_distance := absf(bench.state.position.z - start_z)
	if not lift_off:
		return {"took_off": false, "roll_m": roll_distance, "seconds": seconds}

	# Climb away with a little back stick. Hands off, the aircraft trims itself
	# level and will not climb at all, which is correct but measures nothing here.
	var start_altitude := bench.state.position.y
	var climb := FlightCommand.make(0.3)
	climb.throttle_target = 1.0
	bench.run(10.0, climb, 1.0)
	return {
		"took_off": true,
		"roll_m": roll_distance,
		"seconds": seconds,
		"lift_off_knots": Units.mps_to_knots(lift_off_speed),
		"climb_mps": (bench.state.position.y - start_altitude) / 10.0,
	}


func _measure_climb(tuning: FlightTuning) -> Dictionary:
	var cruise := tuning.cruise_speed_mps()
	var results := {}

	# Best rate of climb: slow, just above the stall.
	var slow := Bench.new(tuning)
	slow.airborne(0.0, tuning.stall_speed_mps() * 1.15, FlightCommand.make(), 1.0)
	var start := slow.state.position.y
	slow.run(15.0, FlightCommand.make(0.35, 0.0, 0.0), 1.0)
	results["at_stall_knots"] = (slow.state.position.y - start) / 15.0
	results["at_stall_speed_knots"] = Units.mps_to_knots(slow.state.airspeed)

	# Climb at cruise speed with full throttle.
	var fast := Bench.new(tuning)
	fast.airborne(0.0, cruise, FlightCommand.make(), 1.0)
	start = fast.state.position.y
	fast.run(15.0, FlightCommand.make(0.35, 0.0, 0.0), 1.0)
	results["at_cruise"] = (fast.state.position.y - start) / 15.0

	return results


func _measure_cruise(tuning: FlightTuning) -> Dictionary:
	var bench := Bench.new(tuning)
	# Hands off at cruise with a pitch-and-throttle hold, which is what a trimmed
	# aircraft does. Same controller shape as the flight model test.
	var integral := 0.0
	var target := bench.state.position.y
	var cruise := tuning.cruise_speed_mps()
	bench.airborne(0.0, cruise, FlightCommand.make(), 1.0)

	for _step in 1800:
		var command := FlightCommand.make()
		integral = clampf(integral + (target - bench.state.position.y) * STEP, -10.0, 10.0)
		command.pitch = clampf((target - bench.state.position.y) * 0.03 + integral * 0.01, -0.5, 0.5)
		command.throttle_target = clampf(0.6 + (cruise - bench.state.airspeed) * 0.05, 0.0, 1.0)
		bench.model.step(bench.state, command, STEP, 0.0)

	# Now ask for full throttle and let it settle at the level ceiling.
	bench.state.throttle = 1.0
	var command := FlightCommand.make(0.1, 0.0, 0.0)
	for _step in 1800:
		bench.model.step(bench.state, command, STEP, 0.0)
	return {
		"level_knots": Units.mps_to_knots(bench.state.airspeed),
		"throttle_used": bench.state.throttle,
		"vertical_mps": bench.state.vertical_speed,
	}


## Stall is measured by flying nose-high until the wing gives up, and reported in
## terms of angle of attack. Measuring it as an airspeed would be measuring the
## wrong quantity: the wing stalls at an angle, and the airspeed at which that
## happens depends on how the aircraft is being flown.
func _measure_stall(tuning: FlightTuning) -> Dictionary:
	var bench := Bench.new(tuning)
	# Full back stick and closed throttle: raise the nose until the wing quits.
	# A gentle pull will not do it, because the pitch restoring term holds the
	# aircraft near its trim angle.
	var command := FlightCommand.make(1.0, 0.0, 0.0)
	command.throttle_target = 0.0
	bench.airborne(0.0, tuning.cruise_speed_mps(), command, 0.0)

	var onset_speed := 0.0
	var onset_angle := 0.0
	var altitude_at_stall := 0.0
	for _step in 3600:
		bench.model.step(bench.state, command, STEP, 0.0)
		if onset_speed == 0.0 and bench.state.lift_efficiency < 0.999:
			onset_speed = bench.state.airspeed_knots()
			onset_angle = bench.model._angle_of_attack_degrees(bench.state)
			altitude_at_stall = bench.state.position.y

	if onset_speed == 0.0:
		return {"stalled": false, "configured_angle_deg": tuning.stall_angle_degrees}

	# Recovery: release the stick and let the nose drop. A recoverable stall
	# rebuilds airspeed and lift with no further input.
	var start_altitude := bench.state.position.y
	# Recovery: ease the stick back and add a little power, which is what a pilot
	# actually does. Releasing alone is not enough while the nose is still high,
	# because the aircraft stays slow and keeps descending.
	var command_recovery := FlightCommand.make(-0.05)
	command_recovery.throttle_target = 0.5
	for _step in 1800:
		bench.model.step(bench.state, command_recovery, STEP, 0.0)

	# Report the lowest point of the recovery rather than the state at the end of
	# the window: the aircraft keeps descending for several seconds after the
	# stall breaks before it settles, so sampling only at the end understates how
	# much altitude the manoeuvre cost.
	var lowest := bench.state.position.y
	var recovered := false
	for _step in 1800:
		bench.model.step(bench.state, command_recovery, STEP, 0.0)
		lowest = minf(lowest, bench.state.position.y)
		if bench.state.lift_efficiency > 0.99 and bench.state.vertical_speed > -3.0:
			recovered = true
			break

	return {
		"stalled": true,
		"onset_angle_deg": onset_angle,
		"configured_angle_deg": tuning.stall_angle_degrees,
		"onset_knots": onset_speed,
		"recovered": recovered,
		"recovered_knots": bench.state.airspeed_knots(),
		"altitude_lost_m": start_altitude - lowest,
		"altitude_at_stall_m": altitude_at_stall,
		"recovery_seconds": (1800.0 if not recovered else 0.0),
	}


func _measure_roll(tuning: FlightTuning) -> Dictionary:
	var bench := Bench.new(tuning)
	bench.airborne(0.0, tuning.cruise_speed_mps(), FlightCommand.make(), 0.8)

	# Time to roll through 90 degrees at full stick.
	var command := FlightCommand.make(0.0, 1.0, 0.0)
	var start_bank := bench.state.roll_degrees
	var seconds := 0.0
	for _step in 600:
		bench.model.step(bench.state, command, STEP, 0.0)
		seconds += STEP
		if absf(bench.state.roll_degrees - start_bank) >= 90.0:
			break

	return {
		"time_to_90_deg_s": seconds,
		"achieved_rate_deg_s": 90.0 / maxf(seconds, 0.0001),
		"configured_rate_deg_s": Units.rad_to_deg(tuning.roll_rate),
		"final_bank_deg": bench.state.roll_degrees,
	}


## Steady turn rate at a commanded bank angle.
##
## The aircraft is pre-banked rather than rolled in with a control loop, and given
## time to settle before the heading change is measured. Rolling in with a
## proportional loop and measuring straight away reports the entry transient
## rather than the steady turn.
##
## `theoretical_*` is g * tan(bank) / V, which is what a rigid body doing a
## coordinated level turn must produce. Agreement with it is the single best
## check that lift, drag and the turn geometry are all consistent.
func _measure_turn(tuning: FlightTuning) -> Dictionary:
	var results := {}
	var measure_seconds := 8.0
	var settle_seconds := 8.0

	for bank_degrees in [30.0, 45.0, 60.0]:
		var bench := Bench.new(tuning)
		bench.state.position = Vector3(0.0, 3000.0, 0.0)
		bench.state.velocity = Vector3(0.0, 0.0, -tuning.cruise_speed_mps())
		bench.state.grounded = false
		# Positive roll is right wing down. Rotating about the forward axis is the
		# only rotation that produces pure bank; rotating about world up would yaw.
		bench.state.basis = Basis(Vector3.FORWARD, deg_to_rad(bank_degrees))

		var command := FlightCommand.make(0.0)
		command.throttle_target = 0.7
		bench.run(settle_seconds, command, 0.7)

		var start_heading := bench.state.heading_degrees
		bench.run(measure_seconds, command, 0.7)
		var turned := wrapf(bench.state.heading_degrees - start_heading, -360.0, 360.0)

		var label := "bank_%d" % int(bank_degrees)
		results[label] = absf(turned) / measure_seconds
		results[label + "_held"] = bench.state.roll_degrees
		results[label + "_sideslip"] = rad_to_deg(
			bench.state.velocity.normalized().angle_to(Units.forward_of(bench.state.basis))
		)
		results[label + "_theory"] = Units.rad_to_deg(
			tuning.gravity * tan(deg_to_rad(bank_degrees)) / maxf(bench.state.airspeed, 1.0)
		)

	return results


## Roll response: how long the aircraft takes to roll through 90 degrees at full
## stick. This is the number that decides whether the aircraft feels responsive or
## ponderous, and it is measured from the attitude rather than from the commanded
## rate so it includes every term that resists the roll.
func _measure_response(tuning: FlightTuning) -> Dictionary:
	var bench := Bench.new(tuning)
	bench.airborne(0.0, tuning.cruise_speed_mps(), FlightCommand.make(), 0.8)

	var command := FlightCommand.make(0.0, 1.0, 0.0)
	var start_bank := bench.state.roll_degrees
	var seconds := 0.0
	for _step in 600:
		bench.model.step(bench.state, command, STEP, 0.0)
		seconds += STEP
		if absf(bench.state.roll_degrees - start_bank) >= 90.0:
			break

	# Settle time: release the stick and see how long a shallow bank takes to level.
	var settled := Bench.new(tuning)
	settled.airborne(0.0, tuning.cruise_speed_mps(), FlightCommand.make(), 0.8)
	settled.state.basis = Basis(Vector3.FORWARD, deg_to_rad(20.0))
	var hands_off := FlightCommand.make()
	var level_seconds := 0.0
	for _step in 1200:
		settled.model.step(settled.state, hands_off, STEP, 0.0)
		level_seconds += STEP
		if absf(settled.state.roll_degrees) <= 1.0:
			break

	return {
		"time_to_90_deg_s": seconds,
		"achieved_roll_rate_deg_s": 90.0 / maxf(seconds, 0.0001),
		"configured_roll_rate_deg_s": Units.rad_to_deg(tuning.roll_rate),
		"time_to_level_from_20_s": level_seconds,
		"axis_smoothing_ms": tuning.axis_smoothing_time * 1000.0,
	}


## Approach and land: fly a stabilised descent, flare, then roll out.
func _measure_landing(tuning: FlightTuning) -> Dictionary:
	var bench := Bench.new(tuning)
	bench.state.position = Vector3(0.0, 250.0, 0.0)
	bench.state.velocity = Vector3(0.0, 0.0, -tuning.stall_speed_mps() * 1.4)
	bench.state.grounded = false

	# Descent at a controlled sink rate, holding speed with the throttle.
	var target_sink := -2.0
	var touched_down := false
	for _step in 3600:
		var command := FlightCommand.make()
		var sink_error := bench.state.vertical_speed - target_sink
		command.pitch = clampf(-sink_error * 0.15, -0.6, 0.6)
		var speed_error := tuning.stall_speed_mps() * 1.4 - bench.state.airspeed
		command.throttle_target = clampf(0.3 + speed_error * 0.05, 0.0, 1.0)
		bench.model.step(bench.state, command, STEP, 0.0)
		if bench.state.grounded:
			touched_down = true
			break

	if not touched_down:
		return {"landed": false, "altitude_m": bench.state.position.y}

	var touchdown_speed := bench.state.airspeed_knots()
	var start_z := bench.state.position.z

	# Roll out with brakes applied. Position is sampled before the run because the
	# bench advances position by integration and comparing against a stale
	# coordinate would report the whole approach distance rather than the roll-out.
	var brake := FlightCommand.make()
	brake.airbrake = true
	bench.run(30.0, brake, 0.0)

	return {
		"landed": true,
		"touchdown_knots": touchdown_speed,
		"roll_out_m": absf(bench.state.position.z - start_z),
		"came_to_rest": bench.state.velocity.length() < REST_SPEED,
		"still_grounded": bench.state.grounded,
	}


const REST_SPEED := 0.5


## Hands-off stability. The aircraft is trimmed and released; a stable model holds
## an attitude and a speed indefinitely rather than diverging, which is the single
## most important property for a game the player is meant to relax into.
func _measure_stability(tuning: FlightTuning) -> Dictionary:
	var results := {}

	for throttle: float in [0.4, 0.7, 1.0]:
		var bench := Bench.new(tuning)
		bench.airborne(0.0, tuning.cruise_speed_mps(), FlightCommand.make(), throttle)

		var command := FlightCommand.make()
		command.throttle_target = throttle
		var start_altitude := bench.state.position.y
		for _step in 3600:
			bench.model.step(bench.state, command, STEP, 0.0)

		results["alt_change_thr_%.1f" % throttle] = bench.state.position.y - start_altitude
		results["speed_thr_%.1f" % throttle] = bench.state.airspeed_knots()
		results["sink_thr_%.1f" % throttle] = -bench.state.vertical_speed
		results["pitch_thr_%.1f" % throttle] = bench.state.pitch_degrees
		results["sideslip_thr_%.1f" % throttle] = rad_to_deg(
			bench.state.velocity.normalized().angle_to(Units.forward_of(bench.state.basis))
		)

	return results


## The invariant the whole model rests on: lift must cancel gravity at cruise.
## Everything else about feel can be retuned, but if this breaks the aircraft can
## neither hold altitude nor behave sanely.
func _check_structural_invariants(tuning: FlightTuning) -> void:
	print("=== Invariants ===")
	var cruise := tuning.cruise_speed_mps()
	var lift := tuning.lift_gain() * cruise * cruise
	var ok := absf(lift - tuning.gravity) / tuning.gravity < 0.01
	print("  %s lift cancels gravity at cruise (%.2f vs %.2f m/s^2)" % [
		"PASS" if ok else "FAIL", lift, tuning.gravity
	])

	var authority := tuning.authority_for(tuning.stall_speed_mps() * 0.5)
	var monotonic := tuning.authority_for(tuning.stall_speed_mps() * 0.9) > authority
	print("  %s control authority rises with airspeed" % ("PASS" if monotonic else "FAIL"))

	# A drag curve larger than lift at cruise makes the aircraft unable to turn,
	# which is the failure mode that motivated deriving drag from lift-to-drag.
	var drag_at_cruise := tuning.drag_coefficient() * cruise * cruise
	var ratio := tuning.gravity / maxf(drag_at_cruise, 0.001)
	var drag_ok := ratio > 3.0
	print("  %s lift-to-drag at cruise is %.1f (must exceed 3 to turn)" % [
		"PASS" if drag_ok else "FAIL", ratio])

	# Static friction below full thrust, or the aircraft can never take off.
	var takeoff_ok := tuning.ground_static_friction < tuning.acceleration
	print("  %s static friction (%.2f) is below thrust (%.2f)" % [
		"PASS" if takeoff_ok else "FAIL", tuning.ground_static_friction, tuning.acceleration])
	print("")


func _report(title: String, data: Dictionary) -> void:
	print("--- %s" % title)
	for key in data:
		var value: Variant = data[key]
		var advisory := "(target %.1f)" % TARGET[key] if _is_advisory(key) else ""
		# Bools print as words and floats as numbers; anything else is shown as-is
		# rather than forced through a numeric format string.
		if value is bool:
			print("  %-24s %-10s %s" % [key, str(value), advisory])
		elif value is float or value is int:
			print("  %-24s %10.2f %s" % [key, value, advisory])
		else:
			print("  %-24s %-10s %s" % [key, str(value), advisory])
	print("")


func _is_advisory(key: String) -> bool:
	return TARGET.has(key)