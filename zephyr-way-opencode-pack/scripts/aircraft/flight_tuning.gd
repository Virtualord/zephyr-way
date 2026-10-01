## Flight tuning for the arcade aircraft.
##
## The first block mirrors design/aircraft_design.json `flight` one-to-one and
## keeps the contract's parameter names and units (knots, m/s^2, rad/s). The
## remaining blocks are arcade specifics that the design file leaves to
## implementation, all exposed so feel can be tuned without touching logic.
##
## Speed equilibria are derived rather than typed in, so the numbers stay
## self-consistent when someone edits max speed or cruise:
##   lift_gain = gravity / cruise_speed^2  -> level flight at cruise
##   drag_coefficient = acceleration / max_speed^2 -> max speed at full throttle
class_name FlightTuning
extends Resource

@export_group("Contract values (design/aircraft_design.json)")
## Hard speed ceiling. Drag is derived from this plus `acceleration`.
@export_range(40.0, 400.0, 1.0) var max_speed_knots: float = 145.0
## Speed the aircraft is trimmed to hold in level flight. Lift is derived from
## this, so changing it changes level-flight attitude.
@export_range(30.0, 400.0, 1.0) var cruise_speed_knots: float = 110.0
## Initial forward acceleration at full throttle in m/s^2, at zero airspeed.
##
## This is *initial* thrust, not a steady-state value. Treating it as constant
## makes the design self-contradictory: 24 m/s^2 is 2.4 g of thrust, and balancing
## that against drag to reach the contract's top speed forces drag above lift at
## cruise, which gives an L/D ratio under 1 and leaves the aircraft unable to
## turn. Real propellers lose thrust as airspeed rises, so thrust here falls off
## toward zero as the aircraft approaches `max_speed_knots`. See
## [method thrust_at].
@export_range(1.0, 80.0, 0.5) var acceleration: float = 24.0
## Peak roll rate in rad/s.
@export_range(0.1, 6.0, 0.05) var roll_rate: float = 1.8
## Peak pitch rate in rad/s.
@export_range(0.1, 6.0, 0.05) var pitch_rate: float = 1.2
## Peak rudder yaw rate in rad/s.
@export_range(0.1, 6.0, 0.05) var yaw_rate: float = 0.7

@export_group("Envelope")
## Gravitational acceleration in m/s^2. Also the main scene's 3d/default_gravity,
## so the two must be edited together.
@export_range(1.0, 30.0, 0.1) var gravity: float = 9.8
## Below this the wing stalls and control authority collapses.
##
## Milestone 2 sets this from the wing's actual geometry rather than by feel. The
## stall speed of a wing is where its maximum lift equals its weight, and for a
## simple lifting surface that is:
##   v = sqrt(2 * mass * gravity / (rho * area * cl_max))
## Wing area (18 m^2) comes from the design file; cl_max 1.5 and sea-level air
## density are standard for a low-speed wing. Mass is inferred from cruise speed,
## because cruise is defined as level flight at maximum lift-to-drag ratio, where
## lift equals weight. See [method body_mass_kg].
@export_range(20.0, 120.0, 1.0) var stall_speed_knots: float = 46.0
## Effective minimum lift multiplier once fully stalled (the nose drops but the
## wing keeps a little shape).
@export_range(0.0, 1.0, 0.01) var stall_lift_floor: float = 0.22
## Extra nose-down pitch rate applied while stalled, in rad/s.
@export_range(0.0, 2.0, 0.05) var stall_nose_drop_rate: float = 0.55

@export_group("Lift and drag")
## Explicit lift gain in m^(-1). 0 derives it from gravity and cruise speed.
@export_range(0.0, 0.05, 0.0001) var lift_gain_override: float = 0.0
## Explicit quadratic drag coefficient. 0 derives it from thrust and max speed.
@export_range(0.0, 0.05, 0.0001) var drag_coefficient_override: float = 0.0
## Fraction of full thrust still available at `max_speed_knots`.
##
## Models the thrust falloff of a fixed-pitch propeller. Combined with the drag
## curve this is what sets the actual top speed: the aircraft settles where
## remaining thrust equals drag. A small value means thrust has nearly run out by
## then, which keeps top speed near the contract value even though drag is now
## sized from lift-to-drag rather than from the thrust budget.
@export_range(0.0, 0.5, 0.01) var thrust_at_max_speed: float = 0.06
## Shape of the thrust falloff. 1 is linear in speed, which is the usual
## approximation; higher values keep more thrust at mid speeds, giving livelier
## low-speed acceleration.
@export_range(0.5, 4.0, 0.05) var thrust_falloff_exponent: float = 1.6
## Drag multiplier while the airbrake input is held.
@export_range(1.0, 8.0, 0.1) var airbrake_drag_multiplier: float = 2.6

@export_group("Controls")
## Seconds for a digital key to travel from centre to full deflection. Gamepad
## sticks are analogue and bypass this entirely.
##
## Lives here rather than on FlightInput because it is a feel number: it sets how
## long the aircraft takes to respond after a key is pressed, which is a tuning
## decision about handling rather than about input plumbing. FlightInput reads it
## from the tuning Resource.
@export_range(0.02, 1.0, 0.01) var axis_smoothing_time: float = 0.14
## Control response as a fraction of the peak rate at stall speed.
@export_range(0.0, 1.0, 0.01) var authority_at_stall: float = 0.42
## Control response as a fraction of the peak rate once fully developed.
@export_range(0.5, 2.0, 0.01) var authority_at_cruise: float = 1.0
## Airspeed in knots at which authority reaches its plateau. 0 uses cruise speed.
@export_range(0.0, 300.0, 1.0) var control_authority_reference_knots: float = 0.0
## Passive roll levelling when the stick is centred, in rad/s^2 per rad of bank.
##
## Deliberately gentle. This is a training aid for casual players, not a stability
## system, and it competes with the commanded roll rate: at 1.1 it rolled a
## deliberate 45-degree bank down to 23 degrees within fifteen seconds. It should
## nudge a shallow bank back to level and otherwise leave the aircraft alone.
@export_range(0.0, 6.0, 0.01) var auto_level_strength: float = 0.12
## Pitch stability: how strongly the nose is pulled back toward its trim angle,
## in rad/s^2 per rad of error.
##
## This is what stops pitch from integrating forever. Without it, holding the
## stick back winds the nose up indefinitely and the aircraft porpoises or loops
## uncontrollably, because a rate command with no restoring term has no
## equilibrium. Real aircraft have this as pitch stiffness in the elevator.
@export_range(0.0, 12.0, 0.05) var pitch_stability: float = 3.2
## Stick deflection that holds the aircraft at maximum climb attitude. Because
## the restoring term is subtracted from the commanded rate, this is the fraction
## of full stick needed to cancel the restoring term at a typical climb angle.
@export_range(0.05, 1.0, 0.01) var climb_stick_fraction: float = 0.34
## How far the trim angle moves with airspeed, in degrees of trim per knot.
##
## Positive means slowing down trims the nose down, which is what makes a stall
## recoverable: as the wing gives up, the nose falls, airspeed builds, and lift
## returns.
@export_range(-0.05, 0.05, 0.001) var trim_pitch_per_knot: float = 0.012
## Airspeed at which the trim angle is zero, in knots. This must be the cruise
## speed, where lift and gravity balance; anything else and hands-off flight is
## either always climbing or always descending.
@export_range(20.0, 250.0, 1.0) var trim_reference_knots: float = 110.0
## How strongly the nose is pulled toward the direction of travel, in 1/s.
##
## This is the side-force-freeing term. In a hard banked turn, lift pushes the
## flight path sideways faster than the nose follows it, so without firm alignment
## the aircraft ends up flying tens of degrees sideways, which is both wrong and
## unreadable. 6.0 closes a 20-degree offset in roughly two seconds.
@export_range(0.0, 20.0, 0.1) var velocity_alignment: float = 6.0
## Airspeed in knots above which alignment eases off, as a fraction of full.
## Must not be 0: see [method FlightModel._apply_velocity_alignment].
@export_range(0.0, 200.0, 1.0) var velocity_alignment_speed_knots: float = 60.0
## Floor on velocity alignment at and above cruise speed, as a fraction of full.
## This is the weathervane term. Setting it to 0 lets the nose and the velocity
## vector diverge permanently, which looks like the flight model has come loose
## from the aircraft.
@export_range(0.0, 1.0, 0.01) var cruise_alignment: float = 0.35
## Yaw added in the direction of a roll input, turning crisp banked turns into
## coordinated ones. Scaled by bank amount.
@export_range(0.0, 2.0, 0.05) var roll_yaw_coupling: float = 0.32
## Unused by the model. Keyboard axis smoothing belongs to FlightInput, which
## owns the input device; only genuinely physics-adjacent rates live here.
## Kept out of this Resource to avoid two sources of truth for one number.

@export_group("Throttle")
## Throttle travel per second for keyboard input.
@export_range(0.1, 3.0, 0.05) var throttle_rate: float = 0.55
## Idle thrust fraction available when the throttle is at zero.
@export_range(0.0, 0.3, 0.01) var idle_thrust: float = 0.04

@export_group("Ground")
## Height of the wheels below the centre of gravity, in metres.
@export_range(0.2, 3.0, 0.05) var gear_height: float = 1.05
## Extra drag multiplier while rolling on the surface, on top of the aerodynamic
## curve. Tyres and grass cost more than clean air.
@export_range(0.0, 3.0, 0.05) var ground_drag: float = 1.0
## Rolling resistance in m/s^2, opposing motion once the aircraft is already
## rolling. Applied as a deadband so it cannot reverse the direction of travel.
@export_range(0.0, 4.0, 0.05) var ground_rolling_resistance: float = 0.42
## Static friction in m/s^2. Thrust must exceed this before the aircraft starts
## to roll, so idle power leaves it parked. Must be below `acceleration` or the
## aircraft could never take off.
@export_range(0.0, 8.0, 0.05) var ground_static_friction: float = 1.1
## Wheel braking deceleration in m/s^2 at full brake.
##
## A separate force from aerodynamic drag because drag alone cannot stop the
## aircraft on the ground: at low speed idle thrust almost exactly cancels it, so
## the aircraft would hold its speed indefinitely. Sized against what a landing
## needs: stopping from about 30 m/s in roughly five seconds means averaging about
## 6 m/s^2, so full brake is set slightly above that. Using a 0-1 strength here
## made the brakes roughly fifteen times too weak to stop anything.
@export_range(0.0, 15.0, 0.1) var wheel_brake_deceleration: float = 7.0
## Steering rate while taxiing, in rad/s.
@export_range(0.1, 3.0, 0.05) var taxi_steer_rate: float = 0.7
## How fast the nose rotates while rolling, in rad/s of stick. A taildragger
## lifts off by rotating, so this has to be quick enough to raise the nose
## before the wing reaches flying speed.
@export_range(0.05, 2.0, 0.01) var ground_rotation_rate: float = 0.42
## Largest nose-up angle the aircraft can hold on the ground, in degrees. Past
## this the tail would strike the ground.
@export_range(0.0, 25.0, 0.5) var ground_rotation_limit_degrees: float = 11.0
## Rudder authority retained while airborne, as a fraction of airborne yaw rate.
## Real aircraft lose this; arcade flight keeps it so the rudder stays useful.
@export_range(0.0, 1.0, 0.01) var rudder_authority_grounded: float = 1.0


## Lift acceleration per m^2/s^2 of airspeed squared, at the reference angle of
## attack.
##
## Anchored so that lift equals gravity at cruise speed *and* at
## `lift_reference_angle_degrees`, which is what makes those two the aircraft's
## natural cruise condition.
##
## Lift is then scaled by angle of attack in [method FlightModel._lift_acceleration],
## not by speed alone. This matters more than it looks: lift that depends only on
## airspeed cannot be reduced by the pilot, so above cruise speed the aircraft
## pulls more than its weight continuously and accelerates vertically without
## bound, since the only way to shed lift is to descend, which raises airspeed
## again. Tying lift to angle of attack gives the model the negative feedback that
## makes a climb settle at a steady rate.
func lift_gain() -> float:
	if lift_gain_override > 0.0:
		return lift_gain_override
	var cruise := Units.knots_to_mps(cruise_speed_knots)
	return gravity / maxf(cruise * cruise, 1.0)


## Angle of attack at which [method lift_gain] is calibrated, in degrees. Lift is
## measured relative to [member lift_zero_lift_angle_degrees], so this is the
## angle that produces one g at cruise speed.
@export_range(0.5, 20.0, 0.1) var lift_reference_angle_degrees: float = 4.0
## Angle of attack at which the wing produces no lift, in degrees. Negative,
## because a cambered wing still produces lift when pointed slightly downwards.
@export_range(-15.0, 5.0, 0.1) var lift_zero_lift_angle_degrees: float = -2.0
## Angle of attack beyond which the wing stalls, in degrees.
##
## A wing stalls when its angle of attack exceeds the point where the airflow
## separates, which is an angle limit rather than a speed limit: an aircraft stalls
## at low speed when flown nose-high, and can be flown fast at low angle without
## stalling at all. Airspeed only enters through the dynamic pressure term.
@export_range(0.0, 25.0, 0.5) var stall_angle_degrees: float = 14.0
## Extra angle of attack beyond the stall, in degrees, over which lift collapses
## to zero. A real stall is abrupt; this width keeps it from being a single frame.
@export_range(0.0, 10.0, 0.25) var stall_angle_width_degrees: float = 4.0


## Ceiling on lift, as a multiple of the aircraft's weight.
##
## This is a structural limit the wing cannot exceed, not a normal operating
## point. Banked turns genuinely need more than 1 g, so the ceiling is above 1, but
## it sits well above the roughly 1 g the aircraft needs in normal flight so that
## turns and pull-ups have headroom without the aircraft resting against the limit.
func max_lift_g() -> float:
	return maxf(max_lift_g_override, 1.0)


## Explicit lift ceiling in g.
@export_range(1.0, 6.0, 0.05) var max_lift_g_override: float = 3.0


## Quadratic drag coefficient in 1/m.
##
## Anchored on the target lift-to-drag ratio at cruise speed, not on thrust. Drag
## has to be derived from aerodynamics rather than from the thrust budget: sizing
## drag to "consume all the thrust at max speed" forces drag above lift at cruise,
## and since drag opposes the velocity vector, that cancels the lateral component
## of lift and makes the aircraft unable to bank into a turn at all.
##
## A light sport aircraft sits around 9:1. This is a deliberately draggy arcade
## value: lower glide performance than reality in exchange for responsive
## deceleration and strong airbrake authority.
func drag_coefficient() -> float:
	if drag_coefficient_override > 0.0:
		return drag_coefficient_override
	var cruise := Units.knots_to_mps(cruise_speed_knots)
	var ratio := maxf(cruise_lift_to_drag, 0.5)
	# Lift at cruise equals gravity, so drag at cruise is gravity / ratio.
	return gravity / (ratio * maxf(cruise * cruise, 1.0))


## Lift-to-drag ratio at cruise speed. Real light aircraft achieve 9 to 12.
@export_range(1.0, 20.0, 0.1) var cruise_lift_to_drag: float = 9.0


func max_speed_mps() -> float:
	return Units.knots_to_mps(max_speed_knots)


func cruise_speed_mps() -> float:
	return Units.knots_to_mps(cruise_speed_knots)


func stall_speed_mps() -> float:
	return Units.knots_to_mps(stall_speed_knots)


## Scalar control authority in [0, ~1] for a given airspeed. Controls go mushy as
## the wing stalls and stay at least partly alive all the way to stall speed.
##
## Saturates at cruise rather than cruise_speed_mps(). A real wing gains
## effectiveness with dynamic pressure up to its best-climb angle and then falls
## off, so letting authority keep climbing above cruise would make fast flight
## progressively twitchier for no good reason.
func authority_for(airspeed: float) -> float:
	var stall := maxf(stall_speed_mps(), 1.0)
	var reference := maxf(stall_speed_reference_knots(), 1.0)
	if airspeed >= reference:
		return authority_at_cruise
	var t := clampf(airspeed / stall, 0.0, 1.0)
	return lerpf(authority_at_stall, authority_at_cruise, t)


## Airspeed at which control authority reaches its plateau. Derived from the wing
## geometry as the speed at which lift equals weight in level flight.
func stall_speed_reference_knots() -> float:
	if control_authority_reference_knots > 0.0:
		return control_authority_reference_knots
	return cruise_speed_knots


## 1.0 when flying normally, falling to `stall_lift_floor` at zero airspeed.
func lift_efficiency_for(airspeed: float) -> float:
	var stall := maxf(stall_speed_mps(), 1.0)
	if airspeed >= stall:
		return 1.0
	return lerpf(stall_lift_floor, 1.0, clampf(airspeed / stall, 0.0, 1.0))


## Lift multiplier at a given angle of attack, which is what a real stall is.
##
## Returns 1.0 below the stall angle, falling to `stall_lift_floor` as the angle
## of attack reaches stall angle plus [member stall_angle_width_degrees].
##
## This is the actual stall model. [method lift_efficiency_for] is a separate
## low-speed term: a wing stalls because of the angle it is flown at, not because
## of how fast it is going, so conflating the two makes an aircraft that is
## descending normally suddenly lose lift.
func lift_efficiency_for_angle(angle_of_attack_degrees: float) -> float:
	if angle_of_attack_degrees <= stall_angle_degrees:
		return 1.0
	var width := maxf(stall_angle_width_degrees, 0.01)
	var depth := clampf((angle_of_attack_degrees - stall_angle_degrees) / width, 0.0, 1.0)
	return lerpf(1.0, stall_lift_floor, depth)