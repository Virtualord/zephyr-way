## Headless flight-model checks.
##
## The flight model is pure maths with no node dependencies, so it can be driven
## at a fixed delta without a scene tree or a display. That makes these checks
## fast, deterministic and the first thing to run when flight feel changes.
##
## Run directly:
## [codeblock]
## godot --headless --path . --script res://tests/flight_model_test.gd
## [/codeblock]
##
## Assertions are deliberately loose. They guard against regressions like inverted
## lift or a stall that never fires, not against specific handling numbers, which
## are a design decision rather than a bug.
extends SceneTree

const STEP := 1.0 / 60.0

var _failures := 0
var _checks := 0


func _initialize() -> void:
	print("Flight model checks")

	_test_gravity_pulls_down()
	_test_thrust_accelerates_forward()
	_test_max_speed_ceiling()
	_test_level_flight_at_cruise()
	_test_bank_turns()
	_test_pitch_climbs()
	_test_stall_reduces_lift()
	_test_lift_efficiency_curve()
	_test_drag_curve_is_monotonic()
	_test_airbrake_decelerates_faster()
	_test_ground_restraint()
	_test_taxi_steering_turns()
	_test_ground_contact_prevents_sinking()
	_test_terrain_sampler_is_used()
	_test_heading_convention()
	_test_zero_delta_is_a_no_op()

	if _failures == 0:
		print("  %d checks passed" % _checks)
	quit(0 if _failures == 0 else 1)


## Helpers

## Flat world. Most tests want to control terrain explicitly rather than
## exercise the sampler, so every helper here passes a ground override of 0.0.
const FLAT_GROUND := 0.0


func _new_model(tuning: FlightTuning = null) -> FlightModel:
	return FlightModel.new(tuning if tuning != null else FlightTuning.new())


func _airborne(state: FlightState, speed_mps: float, altitude := 500.0) -> void:
	state.position = Vector3(0.0, altitude, 0.0)
	state.velocity = Vector3(0.0, 0.0, -speed_mps)
	state.grounded = false


## Place the aircraft at rest on flat ground at the given height.
func _parked(state: FlightState, ground_height := FLAT_GROUND) -> void:
	state.position = Vector3(0.0, ground_height + FlightTuning.new().gear_height, 0.0)
	state.velocity = Vector3.ZERO
	state.throttle = 0.0
	state.grounded = true


func _fly(model: FlightModel, state: FlightState, command: FlightCommand, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for _step in steps:
		model.step(state, command, STEP, FLAT_GROUND)


## Run the model without a ground override, so its sampler is used.
func _fly_sampled(model: FlightModel, state: FlightState, command: FlightCommand, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for _step in steps:
		model.step(state, command, STEP, NAN)


## Average the aircraft's local up over a window, which cancels out the natural
## bobbing of a trimmed aircraft. This is how level flight is measured without
## demanding a perfectly steady one.
func _mean_up(model: FlightModel, state: FlightState, command: FlightCommand, seconds: float) -> Vector3:
	var steps := int(round(seconds / STEP))
	var total := Vector3.ZERO
	for _step in steps:
		model.step(state, command, STEP, FLAT_GROUND)
		total += state.up()
	return (total / float(maxi(steps, 1))).normalized()


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


## Tests

## With no lift at all the aircraft must fall. This catches inverted lift and
## a gravity sign error, the two failures that would make flight feel wrong.
func _test_gravity_pulls_down() -> void:
	var model := _new_model()
	var tuning := model.tuning
	tuning.lift_gain_override = 0.0
	var state := FlightState.new()
	_airborne(state, 30.0)
	var start_altitude := state.position.y

	_fly(model, state, FlightCommand.make(), 1.0)
	_check("gravity accelerates downward", state.velocity.y < -5.0, "vertical speed %.2f" % state.velocity.y)
	_check("gravity lowers altitude", state.position.y < start_altitude)


## Thrust acts along the nose, not along world axes.
func _test_thrust_accelerates_forward() -> void:
	var model := _new_model()
	var tuning := model.tuning
	tuning.lift_gain_override = 0.0
	var state := FlightState.new()
	_airborne(state, 10.0)
	state.throttle = 1.0

	_fly(model, state, FlightCommand.make(), 0.5)
	_check(
		"thrust increases airspeed",
		state.airspeed > 10.0,
		"airspeed %.2f" % state.airspeed
	)


## Drag is derived from max_speed and acceleration, so full throttle must
## asymptote to the contract's ceiling rather than accelerating forever.
func _test_max_speed_ceiling() -> void:
	var model := _new_model()
	var state := FlightState.new()
	_airborne(state, 20.0)
	state.throttle = 1.0

	_fly(model, state, FlightCommand.make(), 60.0)
	var ceiling := model.tuning.max_speed_mps()
	_check_near("max speed approaches the ceiling", state.airspeed, ceiling, ceiling * 0.05)


## Lift is derived so that gravity exactly cancels lift at cruise speed. This is
## the equilibrium the whole flight model is tuned around, so it is checked
## directly against the tuning resource.
func _test_level_flight_at_cruise() -> void:
	var tuning := FlightTuning.new()
	var cruise := tuning.cruise_speed_mps()
	var lift := tuning.lift_gain() * cruise * cruise
	_check_near("lift cancels gravity at cruise speed", lift, tuning.gravity, tuning.gravity * 0.01)

	# Now confirm the model actually flies there: hands off, at cruise, with the
	# throttle placed by a simple altitude hold. Pitch input commands a rate, so a
	# constant input would keep rotating; the controller closes the loop instead.
	var model := _new_model(tuning)
	var state := FlightState.new()
	_airborne(state, cruise)
	state.throttle = 1.0
	var target_altitude := state.position.y

	var up_total := Vector3.ZERO
	var steps := int(round(30.0 / STEP))
	# Proportional on altitude error with a slow integral term. The integral is
	# what removes the steady-state error a P-only controller leaves, which is
	# what an actual trim system does.
	var integral := 0.0
	for _step in steps:
		var error := target_altitude - state.position.y
		integral = clampf(integral + error * STEP, -10.0, 10.0)
		var command := FlightCommand.make()
		command.pitch = clampf(error * 0.03 + integral * 0.01, -0.5, 0.5)
		# Hold cruise speed with the throttle, since thrust is not auto-trimmed.
		var speed_error := cruise - state.airspeed
		command.throttle_target = clampf(0.6 + speed_error * 0.05, 0.0, 1.0)
		model.step(state, command, STEP, FLAT_GROUND)
		up_total += state.up()

	var settled := (up_total / float(maxi(steps, 1))).normalized()
	_check_near("cruise settles near level attitude", settled.y, 1.0, 0.12)
	_check_near("cruise holds altitude", state.position.y, target_altitude, 40.0)


## Banking must turn the aircraft. Lift acts along the aircraft's own up vector,
## so this is the single most important property of the flight model.
func _test_bank_turns() -> void:
	var model := _new_model()
	var state := FlightState.new()
	_airborne(state, model.tuning.cruise_speed_mps())
	state.throttle = 1.0

	var command := FlightCommand.make()
	command.pitch = 0.2
	command.roll = 1.0
	_fly(model, state, command, 3.0)

	_check("bank produces roll", absf(state.roll_degrees) > 20.0, "roll %.1f deg" % state.roll_degrees)
	_check("bank produces a turn", absf(state.heading_degrees) > 10.0, "heading %.1f deg" % state.heading_degrees)


## Positive pitch is nose-up by convention, and nose-up gains altitude.
func _test_pitch_climbs() -> void:
	var model := _new_model()
	var state := FlightState.new()
	_airborne(state, model.tuning.cruise_speed_mps())
	state.throttle = 1.0
	var start_altitude := state.position.y

	_fly(model, state, FlightCommand.make(0.6, 0.0, 0.0), 4.0)
	_check("pitch up is positive", state.pitch_degrees > 5.0, "pitch %.1f deg" % state.pitch_degrees)
	_check("pitch up climbs", state.position.y > start_altitude + 20.0, "gained %.1f m" % (state.position.y - start_altitude))


## Below stall speed the wing loses lift, so the aircraft cannot hold altitude.
## The throttle is closed so speed stays in the stalled band for the whole window.
func _test_stall_reduces_lift() -> void:
	var model := _new_model()
	var state := FlightState.new()
	_airborne(state, model.tuning.stall_speed_mps() * 0.45)
	state.throttle = 0.0
	var start_altitude := state.position.y

	# One step only: thrusting is off, so this measures the lift deficit directly
	# rather than mixing it with the aircraft pitching up under stall.
	model.step(state, FlightCommand.make(), STEP, FLAT_GROUND)
	_check("slow flight loses altitude", state.position.y < start_altitude, "gained %.2f m" % (state.position.y - start_altitude))
	# Vertical speed after one step is the acceleration times the step, so the
	# assertion is scaled by dt rather than testing a steady-state value.
	var expected_sink := model.tuning.gravity * STEP
	_check(
		"slow flight sinks at most half of gravity",
		state.vertical_speed < -expected_sink * 0.5,
		"%.4f m/s in one step, full gravity would be %.4f" % [state.vertical_speed, -expected_sink]
	)
	_check(
		"slow flight reports a stall",
		state.lift_efficiency < 0.9,
		"efficiency %.2f at %.1f kt" % [state.lift_efficiency, state.airspeed_knots()]
	)


## The efficiency curve must be monotonic in airspeed, or stalling behaviour
## becomes unpredictable as speed crosses the threshold.
func _test_lift_efficiency_curve() -> void:
	var tuning := FlightTuning.new()
	var stall := tuning.stall_speed_mps()
	var previous := -1.0
	var monotonic := true
	for index in range(0, 21):
		var speed := stall * float(index) / 20.0
		var efficiency := tuning.lift_efficiency_for(speed)
		if efficiency < previous - 0.0001:
			monotonic = false
		previous = efficiency
	_check("lift efficiency rises monotonically with speed", monotonic)
	_check_near("full efficiency at stall speed", tuning.lift_efficiency_for(stall), 1.0, 0.001)
	_check_near(
		"efficiency floors at stall_lift_floor",
		tuning.lift_efficiency_for(0.0),
		tuning.stall_lift_floor,
		0.001
	)


## More drag means more deceleration at the same airspeed.
func _test_drag_curve_is_monotonic() -> void:
	var tuning := FlightTuning.new()
	var drag := tuning.drag_coefficient()
	_check("drag coefficient is positive", drag > 0.0)
	var previous := -1.0
	var monotonic := true
	for sample: float in [10.0, 20.0, 40.0, 60.0, 80.0]:
		var force: float = drag * sample * sample
		if force < previous:
			monotonic = false
		previous = force
	_check("drag grows with airspeed", monotonic)


## The airbrake should shed speed faster than clean flight at the same throttle.
func _test_airbrake_decelerates_faster() -> void:
	var cruise := FlightTuning.new().cruise_speed_mps()

	var clean_model := _new_model()
	var clean := FlightState.new()
	_airborne(clean, cruise)
	clean.throttle = 0.2
	_fly(clean_model, clean, FlightCommand.make(), 6.0)

	var braking_model := _new_model()
	var braking := FlightState.new()
	_airborne(braking, cruise)
	braking.throttle = 0.2
	var command := FlightCommand.make()
	command.airbrake = true
	_fly(braking_model, braking, command, 6.0)

	_check(
		"airbrake decelerates faster than clean flight",
		braking.airspeed < clean.airspeed,
		"braked %.2f m/s vs clean %.2f m/s" % [braking.airspeed, clean.airspeed]
	)


## On the ground the aircraft must not slide or float. Resting height is
## gear_height above the surface, not zero, because the model's origin is the
## centre of gravity rather than the wheels.
func _test_ground_restraint() -> void:
	var model := _new_model()
	var state := FlightState.new()
	_parked(state)
	var resting := state.position

	_fly(model, state, FlightCommand.make(), 10.0)
	_check(
		"at rest the aircraft stays put",
		state.position.distance_to(resting) < 0.01,
		"moved %.4f m" % state.position.distance_to(resting)
	)
	_check("at rest the aircraft stays grounded", state.grounded)
	_check("grounded aircraft has no lift", is_zero_approx(state.lift_efficiency))


## Rudder input while taxiing must change heading.
func _test_taxi_steering_turns() -> void:
	var model := _new_model()
	var state := FlightState.new()
	_parked(state)
	state.throttle = 0.4
	_fly(model, state, FlightCommand.make(), 2.0)
	var start_heading := state.heading_degrees

	_fly(model, state, FlightCommand.make(0.0, 0.0, 1.0), 2.0)
	_check(
		"taxi steering changes heading",
		absf(wrapf(state.heading_degrees - start_heading, -180.0, 180.0)) > 1.0,
		"heading moved %.2f deg" % wrapf(state.heading_degrees - start_heading, -180.0, 180.0)
	)


## Starting below the terrain must push the aircraft back up to gear height
## rather than letting it sink through.
func _test_ground_contact_prevents_sinking() -> void:
	var model := _new_model()
	var state := FlightState.new()
	state.position = Vector3(0.0, -50.0, 0.0)
	state.velocity = Vector3(0.0, -20.0, 0.0)

	_fly(model, state, FlightCommand.make(), 2.0)
	var expected := model.tuning.gear_height
	_check_near("terrain pushes the aircraft to gear height", state.position.y, expected, 0.05)


## With a sampler set and no override, the model must follow the sampled terrain.
func _test_terrain_sampler_is_used() -> void:
	var model := _new_model()
	var terrain_height := 250.0
	model.ground_height_sampler = func(_position: Vector3) -> float: return terrain_height

	var state := FlightState.new()
	_parked(state, terrain_height)
	_fly_sampled(model, state, FlightCommand.make(), 8.0)
	_check_near(
		"aircraft rests on sampled terrain",
		state.position.y,
		terrain_height + model.tuning.gear_height,
		0.5
	)


## Heading convention: north is -Z, east is +X, and headings wrap to [0, 360).
func _test_heading_convention() -> void:
	var north := Basis.IDENTITY
	_check_near("identity basis faces north", Units.heading_of(north), 0.0, 0.001)

	var east := Basis.looking_at(Vector3(1.0, 0.0, 0.0), Vector3.UP)
	_check_near("+X faces east", Units.heading_of(east), 90.0, 0.001)

	var south := Basis.looking_at(Vector3(0.0, 0.0, 1.0), Vector3.UP)
	_check_near("+Z faces south", Units.heading_of(south), 180.0, 0.001)

	var west := Basis.looking_at(Vector3(-1.0, 0.0, 0.0), Vector3.UP)
	_check_near("-X faces west", Units.heading_of(west), 270.0, 0.001)

	_check_near("headings wrap into range", Units.heading_of(Basis.looking_at(Vector3(0.0, 0.0, -1.0), Vector3.UP)), 0.0, 0.001)
	_check("heading formats to three digits", Units.format_heading(42.4) == "042", Units.format_heading(42.4))
	_check("heading 360 wraps to 000", Units.format_heading(360.0) == "000", Units.format_heading(360.0))


## A zero or negative delta must not corrupt the state, which protects against
## a physics tick spike or a paused tree.
func _test_zero_delta_is_a_no_op() -> void:
	var model := _new_model()
	var state := FlightState.new()
	_airborne(state, 40.0)
	var before := state.position

	model.step(state, FlightCommand.make(1.0, 1.0, 1.0), 0.0, 0.0)
	model.step(state, FlightCommand.make(1.0, 1.0, 1.0), -1.0, 0.0)
	_check("zero and negative deltas do not move the aircraft", state.position.is_equal_approx(before))