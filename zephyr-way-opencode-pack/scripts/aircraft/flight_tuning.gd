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
## Forward acceleration at full throttle in m/s^2.
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
@export_range(20.0, 120.0, 1.0) var stall_speed_knots: float = 46.0
## Effective minimum lift multiplier once fully stalled (the nose drops but the
## wing keeps a little shape).
@export_range(0.0, 1.0, 0.01) var stall_lift_floor: float = 0.22
## Extra nose-down pitch rate applied while stalled, in rad/s.
@export_range(0.0, 2.0, 0.05) var stall_nose_drop_rate: float = 0.55

@export_group("Lift and drag")
## Explicit lift gain in m^(-1). 0 derives it from gravity and cruise speed.
@export_range(0.0, 0.05, 0.0001) var lift_gain_override: float = 0.0
## Explicit quadratic drag coefficient. 0 derives it from acceleration and max speed.
@export_range(0.0, 0.05, 0.0001) var drag_coefficient_override: float = 0.0
## Drag multiplier while the airbrake input is held.
@export_range(1.0, 8.0, 0.1) var airbrake_drag_multiplier: float = 2.6

@export_group("Controls")
## Control response as a fraction of the peak rate at stall speed.
@export_range(0.0, 1.0, 0.01) var authority_at_stall: float = 0.42
## Control response as a fraction of the peak rate at or above cruise speed.
@export_range(0.5, 2.0, 0.01) var authority_at_cruise: float = 1.0
## Passive roll levelling when the stick is centred, in rad/s^2 per rad of bank.
## Keeps casual banking from becoming a permanent barrel roll.
@export_range(0.0, 6.0, 0.05) var auto_level_strength: float = 1.1
## How strongly the nose is pulled toward the velocity vector at low airspeed,
## which keeps slow flight from sliding sideways or backwards.
@export_range(0.0, 8.0, 0.05) var velocity_alignment: float = 2.4
## Airspeed in knots at which velocity alignment stops helping.
@export_range(20.0, 200.0, 1.0) var velocity_alignment_speed_knots: float = 60.0
## Yaw added in the direction of a roll input, turning crisp banked turns into
## coordinated ones. Scaled by bank amount.
@export_range(0.0, 2.0, 0.05) var roll_yaw_coupling: float = 0.32
## Input ramp applied before the model reads an axis, in units per second.
@export_range(0.5, 20.0, 0.1) var input_smoothing: float = 7.5

@export_group("Throttle")
## Throttle travel per second for keyboard input.
@export_range(0.1, 3.0, 0.05) var throttle_rate: float = 0.55
## Idle thrust fraction available when the throttle is at zero.
@export_range(0.0, 0.3, 0.01) var idle_thrust: float = 0.04

@export_group("Ground")
## Height of the wheels below the centre of gravity, in metres.
@export_range(0.2, 3.0, 0.05) var gear_height: float = 1.05
## Fraction of ground speed shed per second from tyres and grass.
@export_range(0.0, 6.0, 0.05) var ground_drag: float = 0.55
## Rolling resistance in m/s^2, so the aircraft always comes to rest.
@export_range(0.0, 4.0, 0.05) var ground_rolling_resistance: float = 0.42
## Steering rate while taxiing, in rad/s.
@export_range(0.1, 3.0, 0.05) var taxi_steer_rate: float = 0.7
## Rudder authority retained while airborne, as a fraction of airborne yaw rate.
## Real aircraft lose this; arcade flight keeps it so the rudder stays useful.
@export_range(0.0, 1.0, 0.01) var rudder_authority_grounded: float = 1.0


## Lift acceleration per m^2/s^2 of airspeed squared.
func lift_gain() -> float:
	if lift_gain_override > 0.0:
		return lift_gain_override
	var cruise := Units.knots_to_mps(cruise_speed_knots)
	return gravity / maxf(cruise * cruise, 1.0)


## Quadratic drag coefficient in 1/m.
func drag_coefficient() -> float:
	if drag_coefficient_override > 0.0:
		return drag_coefficient_override
	var top := Units.knots_to_mps(max_speed_knots)
	return acceleration / maxf(top * top, 1.0)


func max_speed_mps() -> float:
	return Units.knots_to_mps(max_speed_knots)


func cruise_speed_mps() -> float:
	return Units.knots_to_mps(cruise_speed_knots)


func stall_speed_mps() -> float:
	return Units.knots_to_mps(stall_speed_knots)


## Scalar control authority in [0, ~1] for a given airspeed. Controls go mushy as
## the wing stalls and stay at least partly alive all the way to stall speed.
func authority_for(airspeed: float) -> float:
	var stall := maxf(stall_speed_mps(), 1.0)
	var cruise := maxf(cruise_speed_mps(), 1.0)
	if airspeed >= cruise:
		return authority_at_cruise
	var t := clampf(airspeed / stall, 0.0, 1.0)
	return lerpf(authority_at_stall, authority_at_cruise, t)


## 1.0 when flying normally, falling to `stall_lift_floor` at zero airspeed.
func lift_efficiency_for(airspeed: float) -> float:
	var stall := maxf(stall_speed_mps(), 1.0)
	if airspeed >= stall:
		return 1.0
	return lerpf(stall_lift_floor, 1.0, clampf(airspeed / stall, 0.0, 1.0))