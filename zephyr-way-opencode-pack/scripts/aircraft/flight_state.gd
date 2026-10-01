## Snapshot of everything the simulation knows about the aircraft right now.
##
## This is the single source of truth for telemetry. Physics writes it, the
## scene controller copies it onto the transform, and any future HUD or mission
## system reads it. Nothing in here reads input or touches nodes, which keeps
## the flight model testable in isolation.
class_name FlightState
extends RefCounted

## World transform of the aircraft, integrated directly by FlightModel.
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var basis: Basis = Basis.IDENTITY

## Commanded throttle in [0, 1].
var throttle: float = 0.0

## True while the wheels are carrying the aircraft.
var grounded: bool = true

## Derived telemetry, refreshed at the end of every simulation step.
var airspeed: float = 0.0
var altitude: float = 0.0
var altitude_agl: float = 0.0
var vertical_speed: float = 0.0
var heading_degrees: float = 0.0
var pitch_degrees: float = 0.0
var roll_degrees: float = 0.0
var gravity_load: float = 1.0
## 1.0 flying normally, 0.0 fully stalled.
var lift_efficiency: float = 0.0
## Banked turn rate in degrees per second, signed by turn direction.
var turn_rate_degrees: float = 0.0


func forward() -> Vector3:
	return -basis.z


func up() -> Vector3:
	return basis.y


func right() -> Vector3:
	return basis.x


func airspeed_knots() -> float:
	return Units.mps_to_knots(airspeed)


## Recompute derived telemetry. The model calls this after integration; tests
## call it directly after mutating position or velocity by hand.
func refresh(ground_height: float) -> void:
	airspeed = velocity.length()
	altitude = position.y
	altitude_agl = position.y - ground_height
	vertical_speed = velocity.y
	heading_degrees = Units.heading_of(basis)
	pitch_degrees = Units.pitch_of(basis)
	roll_degrees = Units.roll_of(basis)


func to_dictionary() -> Dictionary:
	return {
		"position": position,
		"velocity": velocity,
		"throttle": throttle,
		"airspeed_mps": airspeed,
		"airspeed_knots": airspeed_knots(),
		"altitude_m": altitude,
		"altitude_agl_m": altitude_agl,
		"vertical_speed_mps": vertical_speed,
		"heading_degrees": heading_degrees,
		"pitch_degrees": pitch_degrees,
		"roll_degrees": roll_degrees,
		"grounded": grounded,
		"lift_efficiency": lift_efficiency,
		"gravity_load": gravity_load,
	}