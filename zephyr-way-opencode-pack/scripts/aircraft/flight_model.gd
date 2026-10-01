## Arcade flight dynamics.
##
## Deliberately not an aerospace simulation. The model is a compact set of
## readable forces with two properties that matter for feel:
##
## 1. Bank angle turns the aircraft, because lift acts along the aircraft's own
##    up vector rather than world up.
## 2. Thrust is a fraction of a fixed acceleration rather than a propeller
##    model, so response scales identically at every airspeed.
##
## It extends RefCounted and touches no nodes, so it can be stepped inside
## tests at any fixed delta without a scene tree.
class_name FlightModel
extends RefCounted

var tuning: FlightTuning

## Set by FlightController to sample terrain height under the aircraft.
## Optional; when unset the model treats the world as flat at y = 0.
var ground_height_sampler: Callable = Callable()

## Previous ground-track heading in radians, used to derive the turn rate.
var _previous_track := 0.0


func _init(flight_tuning: FlightTuning = null) -> void:
	tuning = flight_tuning if flight_tuning != null else FlightTuning.new()


## Advance the simulation by `delta` seconds and refresh derived telemetry.
##
## `ground_override` short-circuits terrain sampling, which is how the flat test
## environment and the unit tests avoid depending on a real world.
func step(state: FlightState, command: FlightCommand, delta: float, ground_override: float = NAN) -> void:
	if delta <= 0.0 or state == null or command == null:
		return

	_apply_throttle(state, command, delta)

	var ground_height := _ground_height_at(state.position, ground_override)
	var floor_y := ground_height + tuning.gear_height

	if state.position.y <= floor_y + GROUND_EPSILON and state.velocity.y <= 0.0:
		_step_on_ground(state, command, delta, floor_y, ground_height)
	else:
		_step_in_air(state, command, delta, floor_y)

	state.refresh(ground_height)
	_update_turn_rate(state, delta)


## Signed turn rate in degrees per second, positive to the right.
##
## Measured from the ground track rather than from where the nose points. The nose
## hunts around the flight path as weathervane stability corrects, so a heading
## taken from the attitude oscillates wildly even in a steady turn; the velocity
## vector is what actually rotates, and its rate is the turn rate a pilot means.
func _update_turn_rate(state: FlightState, delta: float) -> void:
	var speed := state.velocity.length()
	if speed < MIN_DRAG_SPEED:
		state.turn_rate_degrees = 0.0
		_previous_track = 0.0
		return

	var track := _heading_of_vector(state.velocity)
	if _previous_track == 0.0:
		_previous_track = track
		state.turn_rate_degrees = 0.0
		return

	var change := wrapf(track - _previous_track, -PI, PI)
	_previous_track = track
	state.turn_rate_degrees = Units.rad_to_deg(change / delta)


func _apply_throttle(state: FlightState, command: FlightCommand, delta: float) -> void:
	if command.has_throttle_target():
		# Analogue input places the throttle directly; a trigger is already a
		# position, so ramping toward it would only add lag.
		state.throttle = clampf(command.throttle_target, 0.0, 1.0)
	else:
		state.throttle = clampf(
			state.throttle + command.throttle_delta * tuning.throttle_rate * delta,
			0.0,
			1.0
		)


## Thrust as an acceleration along the nose, at the current airspeed.
func _thrust_acceleration(state: FlightState) -> float:
	return thrust_at(state.throttle, state.velocity.length())


func _step_in_air(state: FlightState, command: FlightCommand, delta: float, floor_y: float) -> void:
	var airspeed := state.velocity.length()
	var authority := tuning.authority_for(airspeed)
	# Stall is a function of angle of attack, not airspeed: a wing stalls because of
	# the angle it is flown at, so an aircraft descending normally at low speed must
	# not suddenly lose lift. The airspeed term is separate and only softens the wing
	# at very low dynamic pressure.
	var stall_efficiency := tuning.lift_efficiency_for_angle(_angle_of_attack_degrees(state))
	var efficiency := stall_efficiency * tuning.lift_efficiency_for(airspeed)

	var acceleration := Vector3.ZERO

	# Thrust along the nose. The aircraft keeps accelerating in whatever
	# direction it points, including straight down in a dive.
	acceleration += state.basis * Vector3(0.0, 0.0, -_thrust_acceleration(state))

	# Quadratic drag opposing the velocity vector, scaled by the airbrake.
	if airspeed > MIN_DRAG_SPEED:
		var drag_multiplier := tuning.airbrake_drag_multiplier if command.airbrake else 1.0
		var drag := tuning.drag_coefficient() * drag_multiplier * airspeed * airspeed
		acceleration -= (state.velocity / airspeed) * drag

	# Lift along the aircraft's own up vector. This single choice is what makes
	# bank angle produce a turn instead of merely tilting the aircraft.
	#
	# Capped at max_lift_g so the aircraft cannot pull more than its limit
	# regardless of airspeed. Without the cap, lift grows with the square of
	# speed and the aircraft becomes uncontrollable in a dive: at max speed it
	# would be trying to pull several times its own weight.
	var lift := _lift_acceleration(state)
	acceleration += state.basis.y * lift

	# Gravity always pulls down in world space, never along the aircraft's up.
	# Combined with the lift above, an inverted attitude stops generating lift and
	# the nose falls, which is what arcade pilots expect.
	acceleration.y -= tuning.gravity

	# Only the angle-of-attack stall drives the nose drop. Including the low-speed
	# softening term would pitch the nose down whenever the aircraft is merely slow,
	# which is wrong: descending at low speed is normal flight, not a stall.
	_apply_attitude(state, command, authority, delta, 1.0 - stall_efficiency)

	state.velocity += acceleration * delta
	state.position += state.velocity * delta

	# Terrain stop while flying: prevents tunnelling when a dive meets the ground
	# and stops the aircraft sinking through a rising slope.
	if state.position.y < floor_y:
		state.position.y = floor_y
		if state.velocity.y < 0.0:
			state.velocity.y *= GROUND_RESTITUTION

	state.lift_efficiency = efficiency
	state.gravity_load = lift / maxf(tuning.gravity, 0.001)
	state.grounded = state.position.y <= floor_y + GROUND_EPSILON


func _step_on_ground(
	state: FlightState,
	command: FlightCommand,
	delta: float,
	floor_y: float,
	ground_height: float
) -> void:
	state.position.y = floor_y
	state.velocity.y = 0.0

	# Hold the nose on the current heading but let the pilot rotate about it, so
	# the aircraft can raise its nose to rotate for take-off.
	var heading := Vector3(state.velocity.x, 0.0, state.velocity.z)
	if heading.length_squared() < MIN_HEADING_SPEED_SQUARED:
		heading = Units.forward_of(state.basis)
	heading.y = 0.0
	if heading.length_squared() < MIN_HEADING_SPEED_SQUARED:
		heading = Vector3(0.0, 0.0, -1.0)
	heading = heading.normalized()

	# Pitch rotates about the aircraft's own right axis. The angle is integrated
	# from the previous frame rather than restarting at zero, otherwise holding the
	# stick back would only ever advance by one frame's worth.
	var level := Basis.looking_at(heading, Vector3.UP)
	var current_pitch := Units.pitch_of(state.basis) * Units.DEG_TO_RAD
	var limit := maxf(tuning.ground_rotation_limit_degrees, 0.0) * Units.DEG_TO_RAD
	var requested := current_pitch + command.pitch * tuning.ground_rotation_rate * delta
	state.basis = (level * Basis(level.x, clampf(requested, -limit, limit))).orthonormalized()

	# Rolling motion is a 1D problem along the aircraft's ground track: thrust
	# pulls forward, drag and rolling resistance push back.
	#
	# Resistance is applied as a stiction band rather than a constant. Treating it
	# as a deadband is what lets the aircraft start moving from rest under
	# thrust, roll freely once moving, and still come to a definite stop instead
	# of creeping. Applying it as a plain subtraction would make a stationary
	# aircraft unable to overcome it and the takeoff roll would never begin.
	var ground_speed := Vector2(state.velocity.x, state.velocity.z).length()
	var thrust := _thrust_acceleration(state)

	if ground_speed > MIN_GROUND_SPEED:
		# Rolling drag uses the airbrake multiplier too, but the wheel brakes are
		# an additional fixed deceleration. Aerodynamic drag alone is far too weak
		# to stop the aircraft on the ground, because idle thrust almost exactly
		# cancels it at low speed: without a separate brake force the aircraft
		# holds its speed indefinitely.
		var drag_multiplier := tuning.ground_drag
		if command.airbrake:
			drag_multiplier *= tuning.airbrake_drag_multiplier
		var drag := tuning.drag_coefficient() * drag_multiplier * ground_speed * ground_speed
		var braking := tuning.wheel_brake_deceleration if command.airbrake else 0.0

		# Drag and braking always oppose motion and are subtracted unconditionally.
		#
		# Rolling resistance is applied only to a net that is still driving the
		# aircraft forward. Applying it symmetrically around zero turns it into a
		# band that holds speed constant against any braking force, which would
		# make the brakes do nothing. Its job is to stop the aircraft creeping on
		# idle power, not to cancel deceleration.
		var net := thrust - drag - braking
		if net > 0.0:
			net = maxf(net - tuning.ground_rolling_resistance, 0.0)

		var new_speed := maxf(ground_speed + net * delta, 0.0)
		var scale := new_speed / ground_speed
		state.velocity.x *= scale
		state.velocity.z *= scale
	else:
		# Standing still: thrust only moves the aircraft once it beats static
		# friction. Idle thrust alone will not creep it forward.
		if thrust > tuning.ground_static_friction:
			var roll_dir := state.basis * Vector3(0.0, 0.0, -1.0)
			roll_dir.y = 0.0
			roll_dir = roll_dir.normalized()
			var launch := thrust - tuning.ground_static_friction
			state.velocity.x = roll_dir.x * launch * delta
			state.velocity.z = roll_dir.z * launch * delta
		else:
			state.velocity.x = 0.0
			state.velocity.z = 0.0

	# Taxi steering rotates the whole aircraft, so velocity is rotated with it
	# and the aircraft tracks where it points.
	if absf(command.yaw) > YAW_INPUT_EPSILON:
		var steer := Basis(Vector3.UP, -command.yaw * tuning.taxi_steer_rate * delta)
		state.basis = (steer * state.basis).orthonormalized()
		state.velocity = (steer * state.velocity)
		state.velocity.y = 0.0

	# Advance position along the ground. This has to happen here as well as in the
	# airborne path: the ground branch updates velocity directly rather than
	# through an acceleration, so without this the aircraft builds speed on the
	# runway but never travels anywhere, and the take-off roll reads as zero
	# distance no matter how fast it is going.
	state.position.x += state.velocity.x * delta
	state.position.z += state.velocity.z * delta

	state.grounded = true
	state.lift_efficiency = 0.0
	state.gravity_load = 1.0

	_try_lift_off(state, command, delta, ground_height)


## Attempt to leave the ground.
##
## The wheels stay on the surface only while the wing cannot carry the aircraft's
## weight. Once lift exceeds gravity, the aircraft rotates off the runway on its
## own, which is what makes take-off a matter of accelerating to a speed rather
## than of jumping.
##
## Lift acts along the aircraft's own up vector, so the pitch set during the roll
## matters directly: a nose-up attitude projects more of the wing's lift
## vertically. That is exactly why rotating helps, and why the aircraft will not
## leave the ground at all if the pilot holds the nose down.
func _try_lift_off(
	state: FlightState,
	command: FlightCommand,
	delta: float,
	ground_height: float
) -> void:
	var airspeed := state.velocity.length()
	if airspeed < MIN_LIFT_OFF_SPEED:
		return

	var lift := _lift_acceleration(state)
	var surplus := state.basis.y.y * lift - tuning.gravity
	if surplus <= 0.0:
		return

	state.grounded = false
	# Convert part of the surplus into vertical speed so lift-off reads as a
	# rotation rather than a single-frame pop off the surface.
	state.velocity.y += clampf(surplus * LIFT_OFF_RESPONSE, 0.0, MAX_LIFT_OFF_SPEED)
	state.position.y = maxf(state.position.y, ground_height + tuning.gear_height)
	state.lift_efficiency = 1.0

	# Hand over to the airborne attitude model so the pitch the pilot is holding
	# is respected from the first frame of flight, rather than being levelled off.
	_apply_attitude(state, command, tuning.authority_for(airspeed), delta, 0.0)


## Speeds below this never generate enough lift to leave the ground, whatever the
## throttle or pitch, so there is no point evaluating lift there.
const MIN_LIFT_OFF_SPEED := 0.5
## Fraction of surplus lift converted into vertical speed on the first airborne
## frame. Low enough that lift-off reads as a rotation rather than a pop.
const LIFT_OFF_RESPONSE := 0.35
const MAX_LIFT_OFF_SPEED := 4.0


## Rotate the aircraft. `stall_weight` is 0 in normal flight and 1 fully stalled,
## where the nose is pushed down regardless of what the pilot is doing.
func _apply_attitude(
	state: FlightState,
	command: FlightCommand,
	authority: float,
	delta: float,
	stall_weight: float
) -> void:
	# Roll gets an auto-levelling assist when the stick is centred, so casual banking
	# returns to level flight instead of settling into a barrel roll.
	#
	# The assist is a restoring torque competing with the commanded roll rate, not
	# an override of it: it fades out as stick is applied, so a pilot holding bank
	# keeps it. Scaling by (1 - authority) means the assist weakens as the wing
	# loses authority, which is what lets a stall roll the aircraft off level.
	var roll_input := command.roll
	var bank := Units.roll_of(state.basis) * Units.DEG_TO_RAD
	roll_input -= bank * tuning.auto_level_strength * delta * (1.0 - minf(absf(command.roll), 1.0))

	var roll_rate := roll_input * tuning.roll_rate * authority
	var yaw_rate := command.yaw * tuning.yaw_rate * authority

	# Pitch is a rate command plus a restoring term toward a trim angle, which is
	# what makes the aircraft stable rather than an integrator. Holding the stick
	# settles at an attitude; releasing it returns toward trim instead of leaving
	# the nose wherever it ended up.
	var pitch_rate := (command.pitch * tuning.pitch_rate - _pitch_restoring_rate(state)) * authority

	# Coordinated turn: rolling also yaws slightly in the same direction, which
	# makes a banked turn read as one continuous manoeuvre.
	yaw_rate += signf(command.roll) * absf(bank) * tuning.roll_yaw_coupling * authority

	# A stalled wing drops the nose. It is the cue that tells the pilot the
	# aircraft has stopped flying, so it overrides pitch-up demand.
	if stall_weight > 0.0:
		pitch_rate -= tuning.stall_nose_drop_rate * stall_weight

	# Godot's -Z is forward, so positive X rotation pitches the nose up, negative
	# Y rotation yaws right, and negative Z rotation rolls right.
	var rotation := Vector3(pitch_rate * delta, -yaw_rate * delta, -roll_rate * delta)
	state.basis = (state.basis * Basis.from_euler(rotation)).orthonormalized()

	_apply_velocity_alignment(state, delta)


## Forward thrust acceleration at a given throttle and airspeed, in m/s^2.
##
## Thrust falls off toward `thrust_at_max_speed` as the aircraft approaches its
## top speed. This is what lets drag be sized from lift-to-drag rather than from
## the thrust budget: without the falloff, the contract's 24 m/s^2 initial
## acceleration would have to be balanced by drag to reach top speed, which puts
## drag above lift at cruise and makes the aircraft unable to turn.
func thrust_at(throttle: float, airspeed: float) -> float:
	var top := tuning.max_speed_mps()
	var fraction := clampf(airspeed / maxf(top, 1.0), 0.0, 1.0)
	var falloff := pow(fraction, maxf(tuning.thrust_falloff_exponent, 0.01))
	var available := lerpf(1.0, tuning.thrust_at_max_speed, falloff)
	var commanded := clampf(throttle, 0.0, 1.0)
	return tuning.acceleration * available * (commanded + tuning.idle_thrust * (1.0 - commanded))


## Lift acceleration in m/s^2, directed along the aircraft's own up vector.
##
## Lift is the product of dynamic pressure and a lift coefficient that rises with
## angle of attack, so it is modelled as lift_gain * v^2 * (angle of attack
## relative to zero lift) / (reference angle relative to zero lift). Because
## [method tuning.lift_gain] is calibrated so that lift equals gravity at cruise
## speed and at the reference angle, a level cruise attitude produces exactly one
## g.
##
## Depending on angle of attack rather than airspeed alone is what gives the model
## negative feedback. Lift that scaled only with speed could not be reduced by the
## pilot: above cruise speed the wing would keep pulling more than the aircraft's
## weight, and the only way to shed that lift would be to descend, which raises
## airspeed and increases lift again. The aircraft would accelerate vertically
## without bound.
func _lift_acceleration(state: FlightState) -> float:
	var speed := state.velocity.length()
	if speed < MIN_DRAG_SPEED:
		return 0.0

	var angle := _angle_of_attack_degrees(state)
	var efficiency := (
		tuning.lift_efficiency_for_angle(angle)
		* tuning.lift_efficiency_for(speed)
	)
	var reference := tuning.lift_reference_angle_degrees - tuning.lift_zero_lift_angle_degrees
	var span := maxf(reference, 0.01)
	# Angle of attack relative to the zero-lift angle, normalised so that the
	# reference angle produces a coefficient of 1.
	var coefficient := (angle - tuning.lift_zero_lift_angle_degrees) / span
	coefficient = maxf(coefficient, 0.0)

	var lift := tuning.lift_gain() * speed * speed * efficiency * coefficient
	return minf(lift, tuning.gravity * tuning.max_lift_g())


## Angle between where the nose points and where the aircraft is travelling, in
## degrees. Zero in straight and level flight; positive when the nose is above the
## flight path.
func _angle_of_attack_degrees(state: FlightState) -> float:
	var speed := state.velocity.length()
	if speed < MIN_DRAG_SPEED:
		return tuning.lift_reference_angle_degrees
	var flight_path := asin(clampf(state.velocity.y / speed, -1.0, 1.0)) * Units.RAD_TO_DEG
	return Units.pitch_of(state.basis) - flight_path


## Rate, in rad/s, that pulls the nose back toward the trim angle.
##
## Positive when the nose is above trim, because the caller subtracts it from the
## commanded pitch rate. The trim angle itself moves with airspeed, so a slow
## aircraft trims nose-down and recovers from a stall by itself.
func _pitch_restoring_rate(state: FlightState) -> float:
	var trim := trim_angle_for(state.airspeed)
	var error := Units.pitch_of(state.basis) * Units.DEG_TO_RAD - trim
	return error * tuning.pitch_stability


## Trim angle in radians for a given airspeed.
##
## Trim angle in radians for a given airspeed.
##
## This is the attitude the aircraft settles at with the stick centred, and it
## exists so hands-off flight is stable rather than a slow tumble.
##
## Two properties matter:
##
## 1. It is zero at cruise speed. Lift equals gravity at cruise by construction,
##    so the only balanced attitude is level. A non-zero trim here would pitch the
##    nose up, which tilts thrust vertical and adds energy with nothing to balance
##    it: the aircraft would accelerate and climb without limit. That is a runaway,
##    not a trim.
## 2. It goes nose-down as speed falls toward the stall. That is what makes a
##    stall recoverable — the nose falls away, airspeed builds, lift returns —
##    rather than terminal.
func trim_angle_for(airspeed: float) -> float:
	var knots := Units.mps_to_knots(airspeed)
	return (knots - tuning.trim_reference_knots) * tuning.trim_pitch_per_knot * Units.DEG_TO_RAD


## Weathervane stability: turn the nose toward the direction of travel.
##
## Both the horizontal and vertical misalignment are corrected, but each is capped
## per tick. Correcting only yaw is not enough: a pitch error that alignment never
## touches lets the velocity vector rotate away from the nose until the aircraft is
## flying sideways, which is both unrecoverable and unreadable.
##
## The per-tick cap is what makes this stable. In a sustained turn the velocity
## vector legitimately trails the nose, because lift rotates the airframe faster
## than the velocity can follow. Correction applied without a cap chases that
## permanent offset every tick and accumulates into a runaway, since each
## correction feeds the next.
##
## Alignment never falls to zero above the reference speed. Nothing else turns the
## velocity back toward the nose, so if it decayed the two could diverge
## permanently and the aircraft would fly with its nose pointing somewhere other
## than where it is going.
func _apply_velocity_alignment(state: FlightState, delta: float) -> void:
	if tuning.velocity_alignment <= 0.0:
		return
	var speed := state.velocity.length()
	if speed < MIN_DRAG_SPEED:
		return

	var align_speed := maxf(Units.knots_to_mps(tuning.velocity_alignment_speed_knots), 1.0)
	var falloff := maxf(
		clampf(1.0 - speed / align_speed, 0.0, 1.0),
		tuning.cruise_alignment
	)
	if falloff <= 0.0:
		return

	var weight := tuning.velocity_alignment * falloff * delta
	var current := Units.forward_of(state.basis)
	var target := state.velocity / speed

	# Yaw error as a signed angle about world up, in radians. Both terms are
	# converted to radians before being subtracted: Units.heading_of reports
	# degrees while _heading_of_vector reports radians, and mixing them silently
	# scales the error by 57 and leaves alignment unable to converge.
	var heading_error := wrapf(
		Units.deg_to_rad(Units.heading_of(state.basis)) - _heading_of_vector(target),
		-PI,
		PI
	)
	# Pitch error, as a signed angle about the aircraft's own right axis. Positive
	# means the nose is above the flight path.
	var pitch_error := _angle_of_attack_degrees(state) * Units.DEG_TO_RAD

	var yaw_step := clampf(heading_error * weight, -MAX_ALIGNMENT_STEP, MAX_ALIGNMENT_STEP)
	var pitch_step := clampf(pitch_error * weight, -MAX_ALIGNMENT_STEP, MAX_ALIGNMENT_STEP)
	if absf(yaw_step) <= ALIGNMENT_ANGLE_EPSILON and absf(pitch_step) <= ALIGNMENT_ANGLE_EPSILON:
		return

	# Pre-multiply, because these axes are defined in world space. Post-multiplying
	# would apply the rotation in the aircraft's own frame, where "up" is the
	# aircraft's up rather than the world's, so the correction would be applied
	# about the wrong axis entirely and would never converge.
	state.basis = (Basis(Vector3.UP, yaw_step) * Basis(state.basis.x, pitch_step) * state.basis).orthonormalized()


## Compass heading of a direction vector, in radians.
##
## Matches [method Units.heading_of], which returns degrees. The conversion is
## explicit at the call site because mixing the two here is easy to do and
## produces an error term that is wrong by a factor of 57, which silently stops
## alignment from ever converging.
func _heading_of_vector(direction: Vector3) -> float:
	return atan2(direction.x, -direction.z)


func _ground_height_at(position: Vector3, override: float) -> float:
	if not is_nan(override):
		return override
	if ground_height_sampler.is_valid():
		return float(ground_height_sampler.call(position))
	return 0.0


## Tolerances shared by the model and its tests.
const GROUND_EPSILON := 0.02
const GROUND_RESTITUTION := 0.2
const MIN_DRAG_SPEED := 0.05
const MIN_GROUND_SPEED := 0.01
const MIN_HEADING_SPEED_SQUARED := 0.0001
const ROLL_CENTRE_DEADBAND := 0.05
const YAW_INPUT_EPSILON := 0.001
const ALIGNMENT_ANGLE_EPSILON := 0.001
## Largest attitude correction velocity alignment may apply in a single tick, in
## radians. Capping this is what stops the correction from feeding on itself.
const MAX_ALIGNMENT_STEP := 0.012