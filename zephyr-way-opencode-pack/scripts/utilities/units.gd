## Unit conversions and attitude helpers shared by flight, world and UI code.
##
## Simulation units are always metres, seconds and radians. Knots only appear at
## the display/interface boundary, because design/aircraft_design.json specifies
## speeds in knots.
class_name Units
extends RefCounted

## International knot: one nautical mile (1852 m) per hour.
const KNOTS_PER_MPS := 1.9438445
const MPS_PER_KNOT := 1.0 / KNOTS_PER_MPS

const RAD_TO_DEG := 57.29577951308232
const DEG_TO_RAD := 0.017453292519943295


static func mps_to_knots(mps: float) -> float:
	return mps * KNOTS_PER_MPS


static func knots_to_mps(knots: float) -> float:
	return knots * MPS_PER_KNOT


static func rad_to_deg(radians: float) -> float:
	return radians * RAD_TO_DEG


static func deg_to_rad(degrees: float) -> float:
	return degrees * DEG_TO_RAD


## Forward vector for a basis. Godot's convention is that an object looks down -Z.
static func forward_of(basis: Basis) -> Vector3:
	return -basis.z


## Compass heading in degrees for a basis. 0 is north (-Z), 90 is east (+X),
## values increase clockwise when viewed from above and wrap to [0, 360).
static func heading_of(basis: Basis) -> float:
	var fwd := forward_of(basis)
	var degrees := rad_to_deg(atan2(fwd.x, -fwd.z))
	return wrapf(degrees, 0.0, 360.0)


## Signed pitch in degrees, nose-up positive.
static func pitch_of(basis: Basis) -> float:
	return rad_to_deg(asin(clampf(forward_of(basis).y, -1.0, 1.0)))


## Signed roll in degrees, right-wing-down positive.
##
## Measured from the aircraft's own right and up vectors, which is the rotation
## about its forward axis. The sign is negated because Godot's positive rotation
## about +Z rolls left, matching the negative Z rate used in FlightModel.
##
## Reading this from the world-horizontal projection of the up vector instead
## would be wrong: that approach reports a near-constant value for any banked
## attitude, because the projected up vector always points along a single
## horizontal direction once it has left vertical.
static func roll_of(basis: Basis) -> float:
	var up := basis.y
	var right := basis.x
	if absf(up.y) < ROLL_SINGULAR_EPSILON:
		# Looking straight up or down, where roll is undefined.
		return 0.0
	return rad_to_deg(-atan2(right.y, up.y))


## Guards the atan2 in [method roll_of], where up.y passes through zero.
const ROLL_SINGULAR_EPSILON := 0.0001


## Format a heading as a zero-padded three-digit compass string, e.g. "042".
static func format_heading(degrees: float) -> String:
	return "%03d" % int(round(wrapf(degrees, 0.0, 360.0)))