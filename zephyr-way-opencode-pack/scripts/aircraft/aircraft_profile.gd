## Body proportions and livery for the aircraft, mirroring design/aircraft_design.json.
##
## Keeping these as a Resource rather than hard-coded numbers means the shape can
## be retuned without touching AircraftBuilder, and a second aircraft later only
## needs a new .tres. All lengths are in metres.
class_name AircraftProfile
extends Resource

@export_group("Envelope (design/aircraft_design.json)")
@export var length: float = 8.2
@export var wingspan: float = 10.6
@export var height: float = 2.8

@export_group("Proportions (design/aircraft_design.json)")
@export var fuselage_width: float = 0.9
## Area of the lifting surface in square metres. Drives the visual chord and the
## stall speed implied by the wing loading.
@export var wing_area: float = 18.0
## Scale of the tail surfaces relative to the wing, from the design file.
@export_range(0.3, 1.5, 0.01) var tail_scale: float = 0.72

@export_group("Visual palette (design/aircraft_design.json)")
## Primary body colour.
@export var primary_color: Color = Color.html("#E9E3D0")
## Secondary colour for cowl, belly and trim.
@export var secondary_color: Color = Color.html("#394B5A")
## Accent colour for the wingtips and fin flash.
@export var accent_color: Color = Color.html("#E58C5A")

@export_group("Layout")
## Fuselage cross-sections as fractions of length, measured from the nose at 0.
## The builder lofts through these, so silhouette is authored here.
@export var fuselage_sections: Array[Dictionary] = [
	{"z": -0.44, "width": 0.10, "height": 0.10, "y": -0.02},
	{"z": -0.34, "width": 0.78, "height": 0.72, "y": 0.00},
	{"z": -0.18, "width": 1.00, "height": 1.00, "y": 0.01},
	{"z": 0.02, "width": 0.98, "height": 0.96, "y": 0.01},
	{"z": 0.24, "width": 0.70, "height": 0.66, "y": 0.02},
	{"z": 0.40, "width": 0.36, "height": 0.34, "y": 0.05},
]
## Where the wing sits along the fuselage, as a fraction of length from the nose.
@export_range(0.2, 0.8, 0.01) var wing_position: float = 0.34
## Height of the wing plane above the fuselage centreline. High-wing layout.
@export_range(0.2, 2.5, 0.05) var wing_height: float = 0.86
## Wing chord at the root and at the tip, in metres.
@export var wing_root_chord: float = 1.85
@export var wing_tip_chord: float = 1.25
## Dihedral: how far the tips rise, in metres.
@export var wing_dihedral: float = 0.26
## Horizontal tail span and chord, in metres.
@export var tail_span: float = 3.6
@export var tail_chord: float = 1.05
## Vertical fin height above the fuselage and chord, in metres.
@export var fin_height: float = 1.25
@export var fin_chord: float = 1.55
## Propeller diameter and blade count.
@export var propeller_diameter: float = 2.1
@export var propeller_blades: int = 2
## Distance the nose sits ahead of the origin, as a fraction of length. Keeps
## the centre of gravity near the root rather than the geometric middle.
@export_range(0.3, 0.6, 0.01) var nose_bias: float = 0.44
## Height of the wheels below the origin.
@export var wheel_height: float = 1.05
## Main gear track: distance between the two main wheels.
@export var wheel_track: float = 2.35
## Wheel radius.
@export var wheel_radius: float = 0.32
## Tailwheel offset behind the origin, in metres.
@export var tailwheel_offset: float = 3.6

@export_group("Control surface travel")
## How far the elevator, ailerons and rudder deflect at full input, in degrees.
## Consumed by AircraftVisuals for animated surfaces.
@export var elevator_travel_degrees: float = 22.0
@export var aileron_travel_degrees: float = 18.0
@export var rudder_travel_degrees: float = 20.0
## How far the nose wheel or tailwheel steers, in degrees.
@export var ground_steering_degrees: float = 24.0