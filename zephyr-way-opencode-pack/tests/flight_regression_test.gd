## Regression tests for flight-feel bugs found during milestone 02.
##
## Every test here corresponds to a specific defect that made the aircraft fly
## wrong, and each is written so the failure would be unmistakable. They are
## separate from `flight_model_test.gd` because that file checks what the model
## should do in principle, while this one pins down the specific ways it used to
## be broken.
##
## Several of these cost real time to diagnose because the symptoms were
## indirect: a runaway climb, a turn rate 400x too high, an aircraft that could
## not be stopped. All of them were physically checkable, so all of them are
## checked here against physics rather than against remembered numbers.
##
## [codeblock]
## godot --headless --path . --script res://tests/flight_regression_test.gd
## [/codeblock]
extends SceneTree

const STEP := 1.0 / 60.0

var _failures := 0
var _checks := 0


func _initialize() -> void:
	print("Flight feel regression checks")

	_test_ground_actually_moves()
	_test_brakes_stop_the_aircraft()
	_test_idle_does_not_creep()
	_test_takeoff_happens()
	_test_lift_off_needs_lift_not_just_speed()
	_test_hands_off_flight_is_stable()
	_test_drag_is_below_lift()
	_test_banked_turn_matches_theory()
	_test_turn_rate_does_not_run_away()
	_test_sideslip_stays_small()
	_test_bank_is_held_not_levelled()
	_test_pitch_does_not_dive_on_its_own()
	_test_stall_is_an_angle_not_a_speed()
	_test_stall_recovers()
	_test_turn_rate_is_measured_from_the_track()
	_test_alignment_units_are_consistent()
	_test_angle_of_attack_tracks_the_flight_path()
	_test_stall_angle_beats_low_speed_softening()

	if _failures == 0:
		print("  %d checks passed" % _checks)
	quit(0 if _failures == 0 else 1)


## Helpers

func _model(tuning: FlightTuning = null) -> FlightModel:
	return FlightModel.new(tuning if tuning != null else FlightTuning.new())


func _parked(state: FlightState, tuning: FlightTuning) -> void:
	state.position = Vector3(0.0, tuning.gear_height, 0.0)
	state.velocity = Vector3.ZERO
	state.grounded = true


func _flying(state: FlightState, speed_mps: float, altitude := 1000.0) -> void:
	state.position = Vector3(0.0, altitude, 0.0)
	state.velocity = Vector3(0.0, 0.0, -speed_mps)
	state.grounded = false


## The aircraft used to build speed on the runway without ever travelling, because
## the ground branch updated velocity but never integrated position.
func _test_ground_actually_moves() -> void:
	var tuning := FlightTuning.new()
	var model := _model(tuning)
	var state := FlightState.new()
	_parked(state, tuning)

	var command := FlightCommand.make()
	command.throttle_target = 1.0
	for _step in int(2.0 / STEP):
		model.step(state, command, STEP, 0.0)

	_check("full throttle on the ground produces motion", state.position.length() > 20.0,
		"moved %.2f m in 2 s" % state.position.length())
	_check("ground roll builds airspeed", state.airspeed > 10.0, "%.2f m/s" % state.airspeed)


## The wheel brakes were 0.385 m/s^2 when a landing needs about 6, so the aircraft
## held its speed indefinitely with the brakes held.
func _test_brakes_stop_the_aircraft() -> void:
	var tuning := FlightTuning.new()
	var model := _model(tuning)
	var state := FlightState.new()
	_parked(state, tuning)
	state.velocity = Vector3(0.0, 0.0, -30.0)

	var brake := FlightCommand.make()
	brake.airbrake = true
	var seconds := 0.0
	for _step in 1800:
		model.step(state, brake, STEP, 0.0)
		seconds += STEP
		if state.velocity.length() < 0.5:
			break

	_check("brakes bring the aircraft to rest", state.velocity.length() < 0.5,
		"%.3f m/s after %.1f s" % [state.velocity.length(), seconds])
	_check("braking stops within a reasonable distance", seconds < 15.0, "%.1f s" % seconds)
	_check("aircraft stays on the ground while braking", state.grounded)


## Resistance must stop the aircraft creeping on idle power.
##
## Measured as horizontal travel only: the aircraft settles vertically onto its
## wheels on the first tick, and counting that as motion would report a false
## failure of roughly one gear height.
func _test_idle_does_not_creep() -> void:
	var tuning := FlightTuning.new()
	var model := _model(tuning)
	var state := FlightState.new()
	_parked(state, tuning)

	var idle := FlightCommand.make()
	var start := state.position
	for _step in int(10.0 / STEP):
		model.step(state, idle, STEP, 0.0)

	var horizontal := Vector2(state.position.x - start.x, state.position.z - start.z).length()
	_check("idle power does not move the aircraft", horizontal < 0.5,
		"travelled %.3f m" % horizontal)


## The original model had no path to leaving the ground at all.
func _test_takeoff_happens() -> void:
	var tuning := FlightTuning.new()
	var model := _model(tuning)
	var state := FlightState.new()
	_parked(state, tuning)

	var command := FlightCommand.make(0.16)
	command.throttle_target = 1.0
	var lifted := false
	var seconds := 0.0
	for _step in 1800:
		model.step(state, command, STEP, 0.0)
		seconds += STEP
		if not state.grounded:
			lifted = true
			break

	_check("full power and back stick lifts off", lifted, "after %.1f s" % seconds)
	_check("take-off happens at a sane speed", state.airspeed > 25.0 and state.airspeed < 80.0,
		"%.1f m/s" % state.airspeed)

	# And it should keep climbing rather than settling back down.
	var start := state.position.y
	var climb := FlightCommand.make(0.3)
	climb.throttle_target = 1.0
	for _step in int(10.0 / STEP):
		model.step(state, climb, STEP, 0.0)
	_check("aircraft climbs away after take-off", state.position.y > start + 30.0,
		"gained %.1f m" % (state.position.y - start))


## Lift-off must depend on the wing's lift, not merely on speed: a nose-down
## attitude at high speed generates no vertical lift and must stay down.
func _test_lift_off_needs_lift_not_just_speed() -> void:
	var tuning := FlightTuning.new()
	var model := _model(tuning)
	var state := FlightState.new()
	_parked(state, tuning)
	state.velocity = Vector3(0.0, 0.0, -tuning.max_speed_mps())
	# Hold the nose down on the ground, which the ground model allows within its
	# rotation limit.
	state.basis = Basis(Vector3.RIGHT, deg_to_rad(-9.0))

	var command := FlightCommand.make(-1.0)
	command.throttle_target = 1.0
	for _step in int(3.0 / STEP):
		model.step(state, command, STEP, 0.0)

	_check("nose-down attitude does not lift off at max speed", state.grounded,
		"airborne at %.1f m/s" % state.airspeed)


## The pitch restoring term had an inverted sign, which drove the nose away from
## trim and made every scenario dive.
func _test_hands_off_flight_is_stable() -> void:
	for throttle: float in [0.4, 0.7, 1.0]:
		var tuning := FlightTuning.new()
		var model := _model(tuning)
		var state := FlightState.new()
		_flying(state, tuning.cruise_speed_mps())

		var command := FlightCommand.make()
		command.throttle_target = throttle
		var start_altitude := state.position.y
		for _step in int(30.0 / STEP):
			model.step(state, command, STEP, 0.0)

		var drift := absf(state.position.y - start_altitude)
		_check("hands-off flight holds altitude at throttle %.1f" % throttle, drift < 250.0,
			"drifted %.0f m over 30 s" % drift)
		_check("hands-off speed stays finite at throttle %.1f" % throttle,
			is_finite(state.airspeed) and state.airspeed < tuning.max_speed_mps() * 1.3,
			"%.1f kt" % state.airspeed_knots())


## Drag was originally derived from the thrust budget, giving an L/D ratio under
## 1 at cruise, which made banked turns physically impossible.
func _test_drag_is_below_lift() -> void:
	var tuning := FlightTuning.new()
	var cruise := tuning.cruise_speed_mps()
	var lift := tuning.lift_gain() * cruise * cruise
	var drag := tuning.drag_coefficient() * cruise * cruise
	var ratio := lift / drag

	_check("lift exceeds drag at cruise", lift > drag,
		"lift %.2f, drag %.2f" % [lift, drag])
	_check("lift-to-drag is in a plausible range", ratio > 3.0 and ratio < 25.0,
		"L/D %.1f (real light aircraft: 8-12)" % ratio)


## The definitive physics check: a banked turn must turn at g*tan(bank)/V.
func _test_banked_turn_matches_theory() -> void:
	for bank_degrees: float in [30.0, 45.0]:
		var tuning := FlightTuning.new()
		var model := _model(tuning)
		var state := FlightState.new()
		_flying(state, tuning.cruise_speed_mps(), 3000.0)
		# Rotating about the forward axis is a pure bank. Rotating about world up
		# would yaw instead, which is a mistake worth keeping covered.
		state.basis = Basis(Vector3.FORWARD, deg_to_rad(bank_degrees))

		var command := FlightCommand.make()
		command.throttle_target = 0.7
		for _step in int(8.0 / STEP):
			model.step(state, command, STEP, 0.0)

		var start_heading := state.heading_degrees
		var measure := 8.0
		for _step in int(measure / STEP):
			model.step(state, command, STEP, 0.0)
		var turned := absf(wrapf(state.heading_degrees - start_heading, -360.0, 360.0)) / measure

		var theory := Units.rad_to_deg(
			tuning.gravity * tan(deg_to_rad(bank_degrees)) / maxf(state.airspeed, 1.0)
		)
		var error := absf(turned - theory) / theory
		_check("%.0f degree bank turns within 20%% of theory" % bank_degrees, error < 0.20,
			"%.2f deg/s vs theory %.2f (%.0f%% off)" % [turned, theory, error * 100.0])


## The turn rate once ran away to several thousand degrees per second because
## velocity alignment was applying a full 3D rotation every tick and feeding on
## itself.
func _test_turn_rate_does_not_run_away() -> void:
	var tuning := FlightTuning.new()
	var model := _model(tuning)
	var state := FlightState.new()
	_flying(state, tuning.cruise_speed_mps(), 3000.0)
	state.basis = Basis(Vector3.FORWARD, deg_to_rad(45.0))

	var command := FlightCommand.make()
	command.throttle_target = 0.7
	var worst := 0.0
	for _step in int(20.0 / STEP):
		model.step(state, command, STEP, 0.0)
		worst = maxf(worst, absf(state.turn_rate_degrees))

	_check("turn rate stays physically plausible", worst < 60.0,
		"peak %.1f deg/s in a 45 degree bank" % worst)
	_check("aircraft remains stable through a sustained turn", is_finite(state.airspeed),
		"%.1f kt" % state.airspeed_knots())


## With weak alignment the aircraft flew tens of degrees sideways in a turn.
func _test_sideslip_stays_small() -> void:
	var tuning := FlightTuning.new()
	var model := _model(tuning)
	var state := FlightState.new()
	_flying(state, tuning.cruise_speed_mps(), 3000.0)
	state.basis = Basis(Vector3.FORWARD, deg_to_rad(45.0))

	var command := FlightCommand.make()
	command.throttle_target = 0.7
	for _step in int(15.0 / STEP):
		model.step(state, command, STEP, 0.0)

	var slip := Units.rad_to_deg(
		state.velocity.normalized().angle_to(Units.forward_of(state.basis))
	)
	_check("sideslip stays small in a banked turn", slip < 15.0, "%.1f deg" % slip)


## Auto-levelling at its original strength rolled a deliberate 45 degree bank
## down to 23 degrees in fifteen seconds.
func _test_bank_is_held_not_levelled() -> void:
	var tuning := FlightTuning.new()
	var model := _model(tuning)
	var state := FlightState.new()
	_flying(state, tuning.cruise_speed_mps(), 3000.0)
	state.basis = Basis(Vector3.FORWARD, deg_to_rad(45.0))

	var command := FlightCommand.make()
	command.throttle_target = 0.7
	for _step in int(15.0 / STEP):
		model.step(state, command, STEP, 0.0)

	_check("a deliberate bank is held", state.roll_degrees > 35.0,
		"bank decayed to %.1f deg" % state.roll_degrees)

	# A shallow bank with the stick centred should still be corrected, which is the
	# behaviour the assist exists for. It is an assist, not a return-to-level: a
	# small bank should shrink, not vanish.
	var shallow := FlightState.new()
	_flying(shallow, tuning.cruise_speed_mps(), 3000.0)
	shallow.basis = Basis(Vector3.FORWARD, deg_to_rad(8.0))
	for _step in int(30.0 / STEP):
		model.step(shallow, FlightCommand.make(), STEP, 0.0)
	_check("a shallow bank is gently levelled hands-off", shallow.roll_degrees < 8.0,
		"%.1f deg after 30 s, from 8.0" % shallow.roll_degrees)


## Trim is referenced to cruise speed, where lift and gravity balance. A non-zero
## trim there pitched the nose up, tilted thrust vertical and added energy with
## nothing to balance it.
func _test_pitch_does_not_dive_on_its_own() -> void:
	var tuning := FlightTuning.new()
	var model := _model(tuning)

	_check("trim is zero at cruise speed",
		absf(Units.rad_to_deg(model.trim_angle_for(tuning.cruise_speed_mps()))) < 0.5,
		"%.3f deg" % Units.rad_to_deg(model.trim_angle_for(tuning.cruise_speed_mps())))

	# Slower than cruise should trim nose-down, which is what makes a stall
	# recoverable.
	var slow_trim := Units.rad_to_deg(model.trim_angle_for(tuning.stall_speed_mps()))
	_check("trim is nose-down below cruise speed", slow_trim < -0.1, "%.2f deg" % slow_trim)


## A wing stalls because of the angle it is flown at, not its speed. The model
## used to conflate the two, so an aircraft descending normally at low speed would
## suddenly lose lift.
func _test_stall_is_an_angle_not_a_speed() -> void:
	var tuning := FlightTuning.new()
	var model := _model(tuning)
	var state := FlightState.new()
	_flying(state, tuning.cruise_speed_mps())

	var command := FlightCommand.make(1.0)
	command.throttle_target = 0.0
	var onset_angle := 0.0
	var onset_speed := 0.0
	for _step in 600:
		model.step(state, command, STEP, 0.0)
		if onset_speed == 0.0 and state.lift_efficiency < 0.999:
			onset_angle = model._angle_of_attack_degrees(state)
			onset_speed = state.airspeed_knots()
			break

	_check("full back stick stalls the wing", onset_speed > 0.0)
	_check(
		"stall begins near the configured stall angle",
		absf(onset_angle - tuning.stall_angle_degrees) < 4.0,
		"stalled at %.1f deg, configured %.1f deg" % [onset_angle, tuning.stall_angle_degrees]
	)
	_check("stall does not trigger at cruise speed in level flight",
		tuning.lift_efficiency_for_angle(0.0) == 1.0)
	_check("low speed alone does not stall the wing",
		tuning.lift_efficiency_for_angle(2.0) == 1.0,
		"2 deg of angle at any speed is not a stall")


## Once the nose drops far enough, the aircraft must fly again.
func _test_stall_recovers() -> void:
	var tuning := FlightTuning.new()
	var model := _model(tuning)
	var state := FlightState.new()
	_flying(state, tuning.cruise_speed_mps(), 800.0)

	var stall := FlightCommand.make(1.0)
	stall.throttle_target = 0.0
	var stalled := false
	for _step in 600:
		model.step(state, stall, STEP, 0.0)
		if state.lift_efficiency < 0.999:
			stalled = true
			break
	_check("the wing stalls under full back stick", stalled)

	var recovery := FlightCommand.make(-0.05)
	recovery.throttle_target = 0.5
	var recovered := false
	for _step in 1800:
		model.step(state, recovery, STEP, 0.0)
		if state.lift_efficiency > 0.99 and state.vertical_speed > -3.0:
			recovered = true
			break
	_check("the wing recovers from a stall", recovered,
		"efficiency %.2f at %.1f deg" % [
			state.lift_efficiency, model._angle_of_attack_degrees(state)
		])


## Turn rate is measured from the ground track. Taking it from the nose heading
## reported hundreds of degrees per second in a steady turn, because the nose
## hunts around the flight path as alignment corrects.
func _test_turn_rate_is_measured_from_the_track() -> void:
	var tuning := FlightTuning.new()
	var model := _model(tuning)
	var state := FlightState.new()
	_flying(state, tuning.cruise_speed_mps(), 3000.0)
	state.basis = Basis(Vector3.FORWARD, deg_to_rad(45.0))

	var command := FlightCommand.make()
	command.throttle_target = 0.7
	for _step in int(10.0 / STEP):
		model.step(state, command, STEP, 0.0)

	# Average the reported rate over a window and compare with the heading change
	# actually achieved. They should agree closely.
	var start_heading := state.heading_degrees
	var total_rate := 0.0
	var samples := 0
	var window := 6.0
	for _step in int(window / STEP):
		model.step(state, command, STEP, 0.0)
		total_rate += absf(state.turn_rate_degrees)
		samples += 1
	var mean_rate := total_rate / float(maxi(samples, 1))
	var measured := absf(wrapf(state.heading_degrees - start_heading, -360.0, 360.0)) / window

	_check(
		"reported turn rate matches the actual heading change",
		absf(mean_rate - measured) < 2.0,
		"reported %.2f deg/s vs measured %.2f deg/s" % [mean_rate, measured]
	)


## Velocity alignment once compared a degrees value against a radians value, which
## scaled the correction by 57 and stopped it ever converging.
func _test_alignment_units_are_consistent() -> void:
	var tuning := FlightTuning.new()
	var model := _model(tuning)
	var state := FlightState.new()
	_flying(state, tuning.cruise_speed_mps())

	# Yaw the aircraft well away from its direction of travel. Rotating about world up
	# yaws; rotating about the forward axis would bank instead.
	state.basis = Basis(Vector3.UP, deg_to_rad(40.0))
	var initial_offset := Units.rad_to_deg(
		Units.forward_of(state.basis).angle_to(state.velocity.normalized())
	)
	_check("alignment has real work to do", initial_offset > 20.0, "%.1f deg" % initial_offset)

	for _step in int(8.0 / STEP):
		model.step(state, FlightCommand.make(), STEP, 0.0)

	var final_offset := Units.rad_to_deg(
		Units.forward_of(state.basis).angle_to(state.velocity.normalized())
	)
	_check("alignment converges on the direction of travel", final_offset < 10.0,
		"offset went from %.1f to %.1f deg" % [initial_offset, final_offset])


## Angle of attack is the difference between where the nose points and where the
## aircraft is going. If it did not track the flight path, stall could not be
## modelled on it.
func _test_angle_of_attack_tracks_the_flight_path() -> void:
	var tuning := FlightTuning.new()
	var model := _model(tuning)

	var level := FlightState.new()
	_flying(level, tuning.cruise_speed_mps())
	_check_near("angle of attack is zero in level flight",
		model._angle_of_attack_degrees(level), 0.0, 1.0)

	var climbing := FlightState.new()
	climbing.position = Vector3(0.0, 1000.0, 0.0)
	# Nose level, but travelling upward at 10 degrees: the aircraft is descending
	# relative to its own flight path.
	climbing.velocity = Vector3(0.0, sin(deg_to_rad(10.0)), -cos(deg_to_rad(10.0))) * 60.0
	climbing.grounded = false
	_check_near("angle of attack reflects the flight path angle",
		model._angle_of_attack_degrees(climbing), -10.0, 0.5)

	var nose_up := FlightState.new()
	_flying(nose_up, tuning.cruise_speed_mps())
	nose_up.basis = Basis(Vector3.RIGHT, deg_to_rad(8.0))
	_check_near("angle of attack reflects nose-up attitude",
		model._angle_of_attack_degrees(nose_up), 8.0, 0.5)


## The two stall terms must stay distinct: angle of attack causes a stall, low
## airspeed only softens the wing.
func _test_stall_angle_beats_low_speed_softening() -> void:
	var tuning := FlightTuning.new()

	_check("cruise efficiency is unaffected by the stall term",
		is_equal_approx(tuning.lift_efficiency_for_angle(0.0), 1.0))
	_check("below the stall angle efficiency is unaffected",
		is_equal_approx(tuning.lift_efficiency_for_angle(tuning.stall_angle_degrees - 2.0), 1.0))
	_check("well past the stall angle efficiency collapses",
		tuning.lift_efficiency_for_angle(tuning.stall_angle_degrees + tuning.stall_angle_width_degrees * 2.0) < 0.5,
		"%.2f" % tuning.lift_efficiency_for_angle(tuning.stall_angle_degrees + tuning.stall_angle_width_degrees * 2.0))
	_check("the two terms are separable",
		is_equal_approx(
			tuning.lift_efficiency_for(tuning.cruise_speed_mps()),
			1.0
		))


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s%s" % [label, (" (%s)" % detail) if detail != "" else ""])


func _check_near(label: String, actual: float, expected: float, tolerance: float) -> void:
	_check(
		label,
		absf(actual - expected) <= tolerance,
		"expected %.3f +/- %.3f, got %.3f" % [expected, tolerance, actual]
	)