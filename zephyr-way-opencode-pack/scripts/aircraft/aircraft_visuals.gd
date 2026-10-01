## Visual response of the aircraft to flight state.
##
## Separate from FlightModel because animation is presentation, not simulation.
## Reads [FlightState] and [FlightCommand] and drives the procedural airframe:
## propeller speed, control-surface deflection and ground steering.
##
## Parts are addressed through [AircraftBuilder]'s registry rather than node
## groups, so two aircraft in one scene cannot pick up each other's surfaces.
## Nothing here writes back into flight state, so the visual layer can be
## disabled or replaced without affecting how the aircraft flies.
class_name AircraftVisuals
extends Node3D

## Propeller angular speed at idle and at full throttle, in rad/s. What matters is
## the ratio, which is what sells engine speed.
@export_range(0.0, 200.0, 1.0) var idle_propeller_speed: float = 6.0
@export_range(1.0, 600.0, 1.0) var max_propeller_speed: float = 105.0
## Seconds for propeller speed to catch up with the throttle, so spool-up is felt.
@export_range(0.01, 3.0, 0.01) var propeller_response: float = 0.45

## Control-surface deflection limits, in degrees.
@export_range(0.0, 60.0, 1.0) var elevator_travel_degrees: float = 22.0
@export_range(0.0, 60.0, 1.0) var aileron_travel_degrees: float = 18.0
@export_range(0.0, 60.0, 1.0) var rudder_travel_degrees: float = 20.0
@export_range(0.0, 60.0, 1.0) var ground_steering_degrees: float = 24.0

## Chord of the hinged control surfaces, in metres. Used to pivot them about
## their leading edge instead of their centres.
@export_range(0.1, 1.5, 0.01) var control_surface_chord: float = 0.42

var profile: AircraftProfile

var _builder: AircraftBuilder
var _propeller: Node3D
var _propeller_speed := 0.0
var _propeller_angle := 0.0
var _left_ailerons: Array[Node3D] = []
var _right_ailerons: Array[Node3D] = []
var _elevators: Array[Node3D] = []
var _rudders: Array[Node3D] = []
var _steering: Array[Node3D] = []
var _built := false


func _ready() -> void:
	ensure_built()


## Assemble the airframe if it does not exist yet. Safe to call more than once.
func ensure_built() -> void:
	if _built:
		return
	if profile == null:
		profile = AircraftProfile.new()

	_builder = AircraftBuilder.new(profile)
	_builder.build(self)

	_propeller = _builder.part(&"propeller")
	_left_ailerons = _builder.parts(&"aileron_left")
	_right_ailerons = _builder.parts(&"aileron_right")
	_elevators = _builder.parts(&"elevator_left")
	_elevators.append_array(_builder.parts(&"elevator_right"))
	_rudders = _builder.parts(&"rudder")
	_steering = _builder.parts(&"steering")

	# Record the rest pose so deflection is applied from the built geometry every
	# frame instead of accumulating.
	for node in _hinged_nodes():
		node.set_meta(&"rest_rotation", node.rotation)
		node.set_meta(&"rest_position", node.position)

	_built = true


## Drive the visual state. Called from AircraftController after each simulation
## step, so visuals stay in lockstep with physics rather than drifting a frame.
func update_visuals(state: FlightState, command: FlightCommand, delta: float) -> void:
	if not _built or state == null:
		return

	_update_propeller(state, delta)
	_update_control_surfaces(command)
	_update_steering(state, command)


func _update_propeller(state: FlightState, delta: float) -> void:
	var target := lerpf(idle_propeller_speed, max_propeller_speed, clampf(state.throttle, 0.0, 1.0))
	# Exponential approach: the prop spools up quickly but visibly lags the
	# throttle, which is most of why an engine reads as an engine.
	var weight := 1.0 - exp(-delta / maxf(propeller_response, 0.01))
	_propeller_speed = lerpf(_propeller_speed, target, weight)

	if _propeller != null:
		_propeller_angle = wrapf(_propeller_angle + _propeller_speed * delta, 0.0, TAU)
		_propeller.rotation.x = _propeller_angle


func _update_control_surfaces(command: FlightCommand) -> void:
	if command == null:
		return

	# Pitch moves both elevator halves together.
	_hinge(_elevators, Units.deg_to_rad(elevator_travel_degrees) * command.pitch, HingeAxis.PITCH)
	# Roll splits the ailerons, so they always move in opposition.
	_hinge(_left_ailerons, Units.deg_to_rad(aileron_travel_degrees) * command.roll, HingeAxis.PITCH)
	_hinge(_right_ailerons, -Units.deg_to_rad(aileron_travel_degrees) * command.roll, HingeAxis.PITCH)
	# Yaw moves the rudder and, on the ground, the nose wheel.
	_hinge(_rudders, Units.deg_to_rad(rudder_travel_degrees) * command.yaw, HingeAxis.YAW)


func _update_steering(state: FlightState, command: FlightCommand) -> void:
	if command == null:
		return
	# The nose wheel only steers on the ground; in the air the rudder does it.
	var amount := Units.deg_to_rad(ground_steering_degrees) * command.yaw
	if not state.grounded:
		amount = 0.0
	for node in _steering:
		var rest: Vector3 = node.get_meta(&"rest_rotation", Vector3.ZERO)
		node.rotation = Vector3(rest.x, amount, rest.z)


enum HingeAxis { PITCH, YAW }


## Rotate hinged surfaces about their leading edge by sliding them along Z as
## they swing, so the pivot stays where it should be.
func _hinge(nodes: Array[Node3D], angle: float, axis: HingeAxis) -> void:
	var half_chord := control_surface_chord * 0.5
	var swing := sin(angle) * half_chord
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var rest: Vector3 = node.get_meta(&"rest_rotation", Vector3.ZERO)
		var rest_position: Vector3 = node.get_meta(&"rest_position", node.position)
		var yaw := angle if axis == HingeAxis.YAW else 0.0
		var pitch := 0.0 if axis == HingeAxis.YAW else -angle
		node.rotation = Vector3(rest.x + pitch, rest.y + yaw, rest.z)
		node.position = rest_position + Vector3(0.0, 0.0, swing if axis == HingeAxis.PITCH else 0.0)


func _hinged_nodes() -> Array[Node3D]:
	var all: Array[Node3D] = []
	all.append_array(_elevators)
	all.append_array(_left_ailerons)
	all.append_array(_right_ailerons)
	all.append_array(_rudders)
	return all