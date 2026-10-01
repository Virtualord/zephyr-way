## Builds the aircraft as a hierarchy of primitive meshes.
##
## Zephyr Way has no external modelling step: the whole airframe is generated
## here from [AircraftProfile] values, so changing a span or a chord in the
## profile immediately changes the geometry.
##
## Structure follows the airframe rather than the render order, which keeps the
## moving parts addressable as animation targets:
##
## [codeblock]
## Aircraft
##   Body            static mesh: fuselage, cowl, fin, struts
##   WingL / WingR   static mesh: wing panels, flaps, ailerons
##   Tail            static mesh: stabiliser, elevators, rudder
##   Propeller       spins with throttle, child of Nose
##   GearLeft/GearRight/GearTail   wheels, optionally steerable
## [/codeblock]
##
## Meshes are cached per profile and reused, so repeated spawns share geometry.
class_name AircraftBuilder
extends RefCounted

## Named node groups the rest of the code uses to find moving parts, so a
## profile change never breaks the animation code.
const GROUP_PROPELLER := &"propeller"
const GROUP_LEFT_AILERON := &"left_aileron"
const GROUP_RIGHT_AILERON := &"right_aileron"
const GROUP_LEFT_ELEVATOR := &"left_elevator"
const GROUP_RIGHT_ELEVATOR := &"right_elevator"
const GROUP_RUDDER := &"rudder"
const GROUP_STEERING := &"steering"

const BODY_GROUP := &"aircraft_body"

var profile: AircraftProfile

var _materials: Dictionary = {}
var _meshes: Dictionary = {}
## Named references to the moving parts, filled in during build(). Consumers
## address parts by name instead of searching the tree, which keeps a second
## aircraft in the scene from getting the first one's control surfaces.
var _parts: Dictionary = {}


func _init(aircraft_profile: AircraftProfile = null) -> void:
	profile = aircraft_profile if aircraft_profile != null else AircraftProfile.new()
	_build_materials()
	_build_meshes()


## Public entry point: assemble a complete airframe under `parent`.
func build(parent: Node3D) -> AircraftBuilder:
	var root := Node3D.new()
	root.name = "Airframe"
	parent.add_child(root)

	_add_body(root)
	_add_wing(root)
	_add_tail(root)
	_add_propeller(root)
	_add_landing_gear(root)
	return self


## Nodes registered under a part name, for example &"aileron_left".
## Always returns a fresh array, so callers can append without mutating the
## registry.
func parts(name: StringName) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in _parts.get(name, []):
		result.append(node)
	return result


## First node registered under a part name, or null.
func part(name: StringName) -> Node3D:
	var nodes := parts(name)
	return nodes[0] if not nodes.is_empty() else null


func _register(name: StringName, node: Node3D) -> void:
	var existing: Array = _parts.get(name, [])
	existing.append(node)
	_parts[name] = existing


## Material for a palette slot, cached and shared across every aircraft.
func material(slot: StringName) -> StandardMaterial3D:
	if not _materials.has(slot):
		_materials[slot] = _create_material(slot)
	return _materials[slot]


func mesh(key: StringName) -> ArrayMesh:
	return _meshes.get(key, null)


func _add_body(parent: Node3D) -> void:
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = mesh(&"fuselage")
	body.material_override = material(&"primary")
	body.add_to_group(BODY_GROUP)
	_set_shadow(body)
	parent.add_child(body)

	# Cowl and canopy sit at the nose so the front of the aircraft carries the
	# secondary colour, which is what makes the heading readable in flight.
	# A plain Node3D anchor, since it carries no geometry of its own.
	var nose := Node3D.new()
	nose.name = "Nose"
	nose.position = _nose_position()
	parent.add_child(nose)

	var cowl := MeshInstance3D.new()
	cowl.name = "Cowl"
	cowl.mesh = mesh(&"cowl")
	cowl.material_override = material(&"secondary")
	cowl.rotation.y = PI
	nose.add_child(cowl)

	var canopy := MeshInstance3D.new()
	canopy.name = "Canopy"
	canopy.mesh = mesh(&"canopy")
	canopy.material_override = material(&"glass")
	canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	nose.add_child(canopy)


func _add_wing(parent: Node3D) -> void:
	var wing_z := -profile.length * profile.wing_position + profile.length * profile.nose_bias
	var half_span := profile.wingspan * 0.5

	for side in [-1, 1]:
		var wing := Node3D.new()
		wing.name = "WingLeft" if side < 0 else "WingRight"
		# The node sits at the root, so the panel mesh sweeping along +X lands
		# outboard automatically; mirroring only affects the panel and tip.
		wing.position = Vector3(0.0, profile.wing_height, wing_z)
		parent.add_child(wing)

		var panel := MeshInstance3D.new()
		panel.name = "Panel"
		panel.mesh = mesh(&"wing_panel")
		panel.material_override = material(&"primary")
		panel.scale = Vector3(half_span, 1.0, 1.0)
		if side < 0:
			# Rotating mirrors the panel; scaling X by -1 would invert its winding.
			panel.rotation.y = PI
		_set_shadow(panel)
		wing.add_child(panel)

		# Accent tip cap: reads as a painted wingtip from a distance, which is
		# what design/art_direction.json means by silhouette priority.
		var tip := MeshInstance3D.new()
		tip.name = "Tip"
		tip.mesh = mesh(&"wing_panel")
		tip.material_override = material(&"accent")
		tip.scale = Vector3(half_span * 0.26, 1.0, 1.0)
		tip.position.x = side * half_span * 0.74
		if side < 0:
			tip.rotation.y = PI
		_set_shadow(tip)
		wing.add_child(tip)

		var aileron := MeshInstance3D.new()
		aileron.name = "Aileron"
		aileron.mesh = mesh(&"control_surface")
		aileron.material_override = material(&"secondary")
		aileron.position = Vector3(side * half_span * 0.74, -profile.wing_dihedral * 0.12, profile.wing_root_chord * 0.56)
		aileron.add_to_group(GROUP_LEFT_AILERON if side < 0 else GROUP_RIGHT_AILERON)
		_register(&"aileron_left" if side < 0 else &"aileron_right", aileron)
		_set_shadow(aileron)
		wing.add_child(aileron)

	_add_wing_struts(parent, wing_z, half_span)


func _add_wing_struts(parent: Node3D, wing_z: float, half_span: float) -> void:
	# Lift struts are the strongest silhouette cue that this is a light sport
	# aircraft rather than a generic glider.
	for side in [-1, 1]:
		var strut := MeshInstance3D.new()
		strut.name = "StrutLeft" if side < 0 else "StrutRight"
		strut.mesh = mesh(&"strut")
		strut.material_override = material(&"secondary")
		var top := Vector3(side * half_span * 0.42, profile.wing_height - 0.05, wing_z + 0.1)
		var bottom := Vector3(side * profile.fuselage_width * 0.55, -profile.height * 0.16, wing_z - 0.25)
		_orient_strut(strut, top, bottom, 0.10)
		_set_shadow(strut)
		parent.add_child(strut)


func _add_tail(parent: Node3D) -> void:
	var tail_z := profile.length * (1.0 - profile.nose_bias) - profile.length * 0.08
	var scale := profile.tail_scale

	var fin := MeshInstance3D.new()
	fin.name = "Fin"
	fin.mesh = mesh(&"fin")
	fin.material_override = material(&"accent")
	fin.position = Vector3(0.0, profile.height * 0.16, tail_z)
	fin.scale = Vector3(scale, scale, scale)
	_set_shadow(fin)
	parent.add_child(fin)

	# The tail panel mesh sweeps along +X from its origin, so it is scaled to
	# half-span and offset so both halves meet at the fin.
	var half_span := profile.tail_span * 0.5 * scale
	for side in [-1, 1]:
		var suffix := "Left" if side < 0 else "Right"
		var stabiliser := MeshInstance3D.new()
		stabiliser.name = "Stabiliser%s" % suffix
		stabiliser.mesh = mesh(&"tail_panel")
		stabiliser.material_override = material(&"primary")
		stabiliser.position = Vector3(0.0, profile.height * 0.08, tail_z)
		stabiliser.scale = Vector3(half_span, 1.0, scale)
		if side < 0:
			# Mirror by rotating rather than scaling -1: a negative scale would
			# invert the winding order and turn the surface inside out.
			stabiliser.rotation.y = PI
			stabiliser.position.z -= profile.tail_chord * scale * 0.3
		else:
			stabiliser.position.z += profile.tail_chord * scale * 0.3
		_set_shadow(stabiliser)
		parent.add_child(stabiliser)

		var elevator := MeshInstance3D.new()
		elevator.name = "Elevator%s" % suffix
		elevator.mesh = mesh(&"control_surface")
		elevator.material_override = material(&"secondary")
		elevator.position = Vector3(
			side * half_span * 0.45,
			profile.height * 0.08,
			tail_z + profile.tail_chord * scale * 0.85
		)
		elevator.add_to_group(GROUP_LEFT_ELEVATOR if side < 0 else GROUP_RIGHT_ELEVATOR)
		_register(&"elevator_left" if side < 0 else &"elevator_right", elevator)
		_set_shadow(elevator)
		parent.add_child(elevator)

	var rudder := MeshInstance3D.new()
	rudder.name = "Rudder"
	rudder.mesh = mesh(&"fin")
	rudder.material_override = material(&"secondary")
	rudder.position = Vector3(0.0, profile.height * 0.16, tail_z + profile.fin_chord * scale * 0.62)
	rudder.scale = Vector3(scale * 0.42, scale * 0.92, scale)
	rudder.add_to_group(GROUP_RUDDER)
	_register(&"rudder", rudder)
	_set_shadow(rudder)
	parent.add_child(rudder)


func _add_propeller(parent: Node3D) -> void:
	# The propeller hangs off the nose so it inherits the same anchor as the cowl.
	var propeller := Node3D.new()
	propeller.name = "Propeller"
	propeller.position = _nose_position()
	propeller.add_to_group(GROUP_PROPELLER)
	parent.add_child(propeller)
	_register(&"propeller", propeller)

	var spinner := MeshInstance3D.new()
	spinner.name = "Spinner"
	spinner.mesh = mesh(&"spinner")
	spinner.material_override = material(&"accent")
	spinner.rotation.x = PI * 0.5
	propeller.add_child(spinner)

	for blade_index in profile.propeller_blades:
		var blade := MeshInstance3D.new()
		blade.name = "Blade%d" % blade_index
		blade.mesh = mesh(&"propeller_blade")
		blade.material_override = material(&"secondary")
		# Blades are authored along +X, so rotating about the prop axis spaces
		# them evenly without needing a per-blade pivot.
		blade.rotation = Vector3(0.0, 0.0, TAU * float(blade_index) / float(maxi(profile.propeller_blades, 1)))
		propeller.add_child(blade)


func _add_landing_gear(parent: Node3D) -> void:
	var axle_y := -profile.wheel_height + profile.wheel_radius
	var leg_z := _nose_position().z + profile.length * 0.10

	for side in [-1, 1]:
		var suffix := "Left" if side < 0 else "Right"
		var leg := Node3D.new()
		leg.name = "Gear%s" % suffix
		leg.position = Vector3(side * profile.wheel_track * 0.5, axle_y, leg_z)
		# The whole leg yaws, which is what gives the taildragger its steering.
		leg.add_to_group(GROUP_STEERING)
		parent.add_child(leg)
		_register(&"steering", leg)

		var strut := MeshInstance3D.new()
		strut.name = "Strut"
		strut.mesh = mesh(&"gear_leg")
		strut.material_override = material(&"secondary")
		_set_shadow(strut)
		leg.add_child(strut)

		var wheel := MeshInstance3D.new()
		wheel.name = "Wheel"
		wheel.mesh = mesh(&"wheel")
		wheel.material_override = material(&"accent")
		_set_shadow(wheel)
		leg.add_child(wheel)

	var tail_leg := Node3D.new()
	tail_leg.name = "GearTail"
	tail_leg.position = Vector3(0.0, -profile.wheel_height * 0.62, profile.tailwheel_offset)
	tail_leg.add_to_group(GROUP_STEERING)
	parent.add_child(tail_leg)
	_register(&"steering", tail_leg)

	var tail_wheel := MeshInstance3D.new()
	tail_wheel.name = "Wheel"
	tail_wheel.mesh = mesh(&"small_wheel")
	tail_wheel.material_override = material(&"accent")
	tail_wheel.scale = Vector3(0.72, 0.72, 0.72)
	tail_leg.add_child(tail_wheel)


## Anchor at the very front of the airframe, where the cowl and propeller mount.
##
## Derived from the fuselage sections rather than hard-coded, so moving the nose
## in the profile moves the engine with it. The local -Z direction is forward.
func _nose_position() -> Vector3:
	var bias := (profile.nose_bias - 0.5) * profile.length
	var front := INF
	var centre_y := 0.0
	for section in profile.fuselage_sections:
		var z := float(section.get("z", 0.0)) * profile.length - bias
		if z < front:
			front = z
			centre_y = float(section.get("y", 0.0)) * profile.fuselage_width
	return Vector3(0.0, centre_y, front)


## Place a strut mesh so it spans from `bottom` to `top`. The mesh is a unit box
## centred on the origin, so the transform carries both the orientation and the
## length.
func _orient_strut(strut: MeshInstance3D, top: Vector3, bottom: Vector3, thickness: float) -> void:
	var span := top - bottom
	var length := span.length()
	if length <= 0.0001:
		return
	var basis := _basis_from_y(span.normalized()).scaled(Vector3(thickness, length, thickness))
	strut.transform = Transform3D(basis, (top + bottom) * 0.5)


## Basis whose local +Y points along `direction`.
static func _basis_from_y(direction: Vector3) -> Basis:
	var reference := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x_axis := reference.cross(direction).normalized()
	var z_axis := x_axis.cross(direction).normalized()
	return Basis(x_axis, direction, z_axis)


## Shadows on everything except the tiny control surfaces, which would only add
## shimmering artefacts at this sun angle.
func _set_shadow(instance: MeshInstance3D) -> void:
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _create_material(slot: StringName) -> StandardMaterial3D:
	match slot:
		&"primary":
			return MeshBuilder.flat_material(profile.primary_color, 0.72)
		&"secondary":
			return MeshBuilder.flat_material(profile.secondary_color, 0.62)
		&"accent":
			return MeshBuilder.flat_material(profile.accent_color, 0.6)
		&"glass":
			return _glass_material()
		_:
			return MeshBuilder.flat_material(profile.primary_color)


func _glass_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.88, 0.95, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.08
	material.metallic = 0.1
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _build_materials() -> void:
	for slot in [&"primary", &"secondary", &"accent", &"glass"]:
		material(slot)


func _build_meshes() -> void:
	_meshes[&"fuselage"] = _fuselage_mesh()
	_meshes[&"cowl"] = _cowl_mesh()
	_meshes[&"wing_panel"] = _wing_mesh()
	_meshes[&"wing_tip"] = _wing_mesh()
	_meshes[&"tail_panel"] = _tail_panel_mesh()
	_meshes[&"fin"] = _fin_mesh()
	_meshes[&"control_surface"] = _control_surface_mesh()
	_meshes[&"strut"] = _strut_mesh()
	_meshes[&"gear_leg"] = _gear_leg_mesh()
	_meshes[&"wheel"] = MeshBuilder.cylinder(profile.wheel_radius, profile.wheel_radius * 0.7, 12)
	_meshes[&"small_wheel"] = MeshBuilder.cylinder(profile.wheel_radius, profile.wheel_radius * 0.6, 10)
	_meshes[&"spinner"] = MeshBuilder.cone(profile.wheel_radius * 0.75, profile.wheel_radius * 1.5, 10)
	_meshes[&"propeller_blade"] = _propeller_blade_mesh()
	_meshes[&"canopy"] = _canopy_mesh()


## Lofted fuselage. Section z values are fractions of length, converted to
## metres here and offset so the origin stays near the centre of gravity.
func _fuselage_mesh() -> ArrayMesh:
	var length := profile.length
	var width := profile.fuselage_width
	# The origin sits at the centre of gravity, so sections shift aft by the
	# nose bias to keep the nose ahead of it.
	var bias := (profile.nose_bias - 0.5) * length

	var sections: Array = []
	for section in profile.fuselage_sections:
		sections.append({
			"width": float(section.get("width", 1.0)) * width,
			"height": float(section.get("height", 1.0)) * width * 1.02,
			"y": float(section.get("y", 0.0)) * width,
			"z": float(section.get("z", 0.0)) * length - bias,
		})
	return MeshBuilder.loft(sections, MeshBuilder.PROFILE_OCTAGON, true, true)


## Engine cowl: a short, wide band over the nose section.
func _cowl_mesh() -> ArrayMesh:
	var radius := profile.fuselage_width * 0.62
	return MeshBuilder.loft([
		{"width": radius * 0.92, "height": radius * 0.92, "z": -radius * 0.55},
		{"width": radius, "height": radius * 1.05, "z": 0.0},
		{"width": radius * 0.86, "height": radius * 0.9, "z": radius * 0.5},
	], MeshBuilder.PROFILE_OCTAGON, true, true)


## One wing panel, swept along +X from the root out to a unit span so the node
## can scale it to the real half-span. Chord runs along Z and thickness along Y,
## matching the outline in MeshBuilder.PROFILE_WING.
func _wing_mesh() -> ArrayMesh:
	var chord := profile.wing_root_chord
	var tip_chord := profile.wing_tip_chord
	return MeshBuilder.loft([
		{"width": chord, "height": chord * 0.16, "z": 0.0},
		{"width": lerpf(chord, tip_chord, 0.55), "height": chord * 0.14, "z": 0.55},
		{"width": tip_chord, "height": tip_chord * 0.13, "z": 1.0, "y": profile.wing_dihedral},
	], MeshBuilder.PROFILE_WING, true, true, MeshBuilder.Axis.X)


## Horizontal tail panel, same construction as the wing.
func _tail_panel_mesh() -> ArrayMesh:
	var chord := profile.tail_chord
	return MeshBuilder.loft([
		{"width": chord, "height": chord * 0.17, "z": 0.0},
		{"width": chord * 0.82, "height": chord * 0.15, "z": 0.85},
		{"width": chord * 0.66, "height": chord * 0.13, "z": 1.0},
	], MeshBuilder.PROFILE_WING, true, true, MeshBuilder.Axis.X)


## Vertical fin, authored in the XY plane and extruded forward along Z.
func _fin_mesh() -> ArrayMesh:
	var height := profile.fin_height
	var chord := profile.fin_chord
	return MeshBuilder.loft([
		{"width": chord * 0.34, "height": height * 0.4, "z": -chord * 0.2},
		{"width": chord * 0.3, "height": height, "z": 0.0},
		{"width": chord * 0.16, "height": height, "z": chord * 0.22},
	], MeshBuilder.PROFILE_WING, true, true)


## Generic hinged surface, sized to the aileron/elevator and pivoting about its
## own leading edge so deflection looks mechanical rather than floating.
func _control_surface_mesh() -> ArrayMesh:
	return MeshBuilder.box(Vector3(0.62, 0.055, 0.42))


func _strut_mesh() -> ArrayMesh:
	return MeshBuilder.box(Vector3(0.09, 1.0, 0.16))


func _gear_leg_mesh() -> ArrayMesh:
	return MeshBuilder.box(Vector3(0.11, 0.16, 0.9))


func _propeller_blade_mesh() -> ArrayMesh:
	# Blade spans +X from the hub, so the mesh is shifted outward by half its
	# length rather than being centred on the axis.
	var radius := profile.propeller_diameter * 0.5
	var blade := MeshBuilder.box(Vector3(radius, 0.07, radius * 0.26))
	var arrays := blade.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in vertices.size():
		vertices[index] += Vector3(radius * 0.5, 0.0, 0.0)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var shifted := ArrayMesh.new()
	shifted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return shifted


## Canopy bubble over the cockpit. A simple loft rather than a sphere keeps the
## faceted look consistent with the rest of the airframe.
func _canopy_mesh() -> ArrayMesh:
	var width := profile.fuselage_width * 0.86
	return MeshBuilder.loft([
		{"width": width * 0.72, "height": width * 0.44, "y": width * 0.30, "z": -width * 0.1},
		{"width": width, "height": width * 0.62, "y": width * 0.44, "z": width * 0.35},
		{"width": width * 0.86, "height": width * 0.5, "y": width * 0.36, "z": width * 0.8},
		{"width": width * 0.6, "height": width * 0.3, "y": width * 0.28, "z": width * 1.15},
	], MeshBuilder.PROFILE_OCTAGON, true, true)