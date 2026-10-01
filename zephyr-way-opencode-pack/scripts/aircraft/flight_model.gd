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

## Previous heading, used to derive the signed turn rate for the HUD.
var _previous_heading := 0.0


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
	var on_ground := state.position.y <= floor_y + GROUND_EPSILON

	_previous_heading = state.heading_degrees

	if on_ground and state.velocity.y <= 0.0:
		_step_on_ground(state, command, delta, floor_y)
	else:
		_step_in_air(state, command, delta, floor_y)

	state.refresh(ground_height)

	# Signed turn rate, positive to the right, for the HUD and future autopilots.
	var heading_delta := wrapf(state.heading_degrees - _previous_heading, -180.0, 180.0)
	state.turn_rate_degrees = Units.rad_to_deg(heading_delta / delta)


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


## Thrust as an acceleration along the nose, plus the idle-thrust floor.
func _thrust_acceleration(state: FlightState) -> float:
	var throttle := clampf(state.throttle, 0.0, 1.0)
	return tuning.acceleration * (throttle + tuning.idle_thrust * (1.0 - throttle))


func _step_in_air(state: FlightState, command: FlightCommand, delta: float, floor_y: float) -> void:
	var airspeed := state.velocity.length()
	var authority := tuning.authority_for(airspeed)
	var efficiency := tuning.lift_efficiency_for(airspeed)

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
	var lift := tuning.lift_gain() * airspeed * airspeed * efficiency
	acceleration += state.basis.y * lift

	# Gravity always pulls down in world space, never along the aircraft's up.
	# Combined with the lift above, an inverted attitude stops generating lift and
	# the nose falls, which is what arcade pilots expect.
	acceleration.y -= tuning.gravity

	_apply_attitude(state, command, authority, delta, 1.0 - efficiency)

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


func _step_on_ground(state: FlightState, command: FlightCommand, delta: float, floor_y: float) -> void:
	state.position.y = floor_y
	state.velocity.y = 0.0

	# Level the aircraft on its current heading and keep it on the floor.
	var heading := Vector3(state.velocity.x, 0.0, state.velocity.z)
	if heading.length_squared() < MIN_HEADING_SPEED_SQUARED:
		heading = Units.forward_of(state.basis)
	heading.y = 0.0
	if heading.length_squared() < MIN_HEADING_SPEED_SQUARED:
		heading = Vector3(0.0, 0.0, -1.0)
	state.basis = Basis.looking_at(heading.normalized(), Vector3.UP)

	# Thrust drives rolling speed; drag and rolling resistance slow it. The
	# net force is floored by thrust so the aircraft always ends up stopped.
	var ground_speed := Vector2(state.velocity.x, state.velocity.z).length()
	var drag_multiplier := tuning.airbrake_drag_multiplier if command.airbrake else 1.0
	var drag := tuning.drag_coefficient() * drag_multiplier * ground_speed * ground_speed
	var resistance := tuning.ground_rolling_resistance
	var thrust := _thrust_acceleration(state)
	var net := clampf(thrust - drag, -thrust, resistance) - resistance

	if ground_speed > MIN_GROUND_SPEED:
		var new_speed := maxf(ground_speed + net * delta, 0.0)
		var scale := new_speed / ground_speed
		state.velocity.x *= scale
		state.velocity.z *= scale
	elif thrust > 0.0:
		var roll_dir := state.basis * Vector3(0.0, 0.0, -1.0)
		roll_dir.y = 0.0
		roll_dir = roll_dir.normalized()
		state.velocity.x = roll_dir.x * thrust * delta
		state.velocity.z = roll_dir.z * thrust * delta
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

	state.grounded = true
	state.lift_efficiency = 0.0
	state.gravity_load = 1.0


## Rotate the aircraft. `stall_weight` is 0 in normal flight and 1 fully stalled,
## where the nose is pushed down regardless of what the pilot is doing.
func _apply_attitude(
	state: FlightState,
	command: FlightCommand,
	authority: float,
	delta: float,
	stall_weight: float
) -> void:
	# Roll gets an auto-levelling assist when the stick is centred, so casual
	# banking returns to level flight instead of settling into a barrel roll.
	var roll_input := command.roll
	if absf(roll_input) < ROLL_CENTRE_DEADBAND:
		var bank := Units.roll_of(state.basis) * Units.DEG_TO_RAD
		roll_input -= bank * tuning.auto_level_strength * delta

	var pitch_input := command.pitch

	var pitch_rate := pitch_input * tuning.pitch_rate * authority
	var roll_rate := roll_input * tuning.roll_rate * authority
	var yaw_rate := command.yaw * tuning.yaw_rate * authority

	# Coordinated turn: rolling also yaws slightly in the same direction, which
	# makes a banked turn read as one continuous manoeuvre.
	var bank := absf(Units.roll_of(state.basis)) * Units.DEG_TO_RAD
	yaw_rate += signf(roll_input) * bank * tuning.roll_yaw_coupling * authority

	# A stalled wing drops the nose. It is the cue that tells the pilot the
	# aircraft has stopped flying, so it overrides pitch-up demand.
	if stall_weight > 0.0:
		pitch_rate -= tuning.stall_nose_drop_rate * stall_weight

	# Godot's -Z is forward, so positive X rotation pitches the nose up, negative
	# Y rotation yaws right, and negative Z rotation rolls right.
	var rotation := Vector3(pitch_rate * delta, -yaw_rate * delta, -roll_rate * delta)
	state.basis = (state.basis * Basis.from_euler(rotation)).orthonormalized()

	_apply_velocity_alignment(state, delta)


## Pull the nose toward the velocity vector at low airspeed. Without this the
## aircraft skids sideways at low speed instead of flying where it points.
func _apply_velocity_alignment(state: FlightState, delta: float) -> void:
	if tuning.velocity_alignment <= 0.0:
		return
	var speed := state.velocity.length()
	if speed < MIN_DRAG_SPEED:
		return

	var align_speed := maxf(Units.knots_to_mps(tuning.velocity_alignment_speed_knots), 1.0)
	var falloff := clampf(1.0 - speed / align_speed, 0.0, 1.0)
	if falloff <= 0.0:
		return

	var current := Units.forward_of(state.basis)
	var target := state.velocity / speed
	var angle := current.angle_to(target)
	if angle <= ALIGNMENT_ANGLE_EPSILON:
		return

	var axis := current.cross(target)
	var axis_length := axis.length()
	if axis_length <= ALIGNMENT_AXIS_EPSILON:
		return

	var weight := tuning.velocity_alignment * falloff * delta
	state.basis = (state.basis * Basis(axis / axis_length, angle * weight)).orthonormalized()


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
const ALIGNMENT_AXIS_EPSILON := 0.00001