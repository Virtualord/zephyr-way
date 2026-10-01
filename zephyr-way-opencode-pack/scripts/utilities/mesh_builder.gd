## Low-level procedural mesh construction helpers.
##
## Everything Zephyr Way renders is built in code, so this is the shared
## vocabulary for that: flat-shaded boxes, tapered prisms, tapered cylinders and
## cross-section lofts. Surfaces come out non-indexed with per-face normals,
## which is exactly the faceted look design/art_direction.json asks for.
class_name MeshBuilder
extends RefCounted

## Unit cross-sections used by loft(). Each entry is a 2D outline in the local
## plane; loft() walks them in order, so they must all have the same point count
## for a clean bridge. The outlines are deliberately soft-edged (corners cut)
## rather than circular so faces stay large and readable at low polygon counts.
const PROFILE_BOX: Array[Vector2] = [
	Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5),
]

const PROFILE_OCTAGON: Array[Vector2] = [
	Vector2(-0.5, -0.5), Vector2(-0.28, -0.5), Vector2(0.28, -0.5), Vector2(0.5, -0.28),
	Vector2(0.5, 0.28), Vector2(0.28, 0.5), Vector2(-0.28, 0.5), Vector2(-0.5, 0.28),
]

const PROFILE_HEXAGON: Array[Vector2] = [
	Vector2(-0.5, -0.32), Vector2(0.5, -0.32), Vector2(0.5, 0.32),
	Vector2(0.22, 0.5), Vector2(-0.22, 0.5), Vector2(-0.5, 0.32),
]

const PROFILE_DIAMOND: Array[Vector2] = [
	Vector2(0.0, -0.5), Vector2(0.5, 0.0), Vector2(0.0, 0.5), Vector2(-0.5, 0.0),
]

const PROFILE_WING: Array[Vector2] = [
	Vector2(-0.5, -0.28), Vector2(-0.34, -0.5), Vector2(0.34, -0.5), Vector2(0.5, -0.28),
	Vector2(0.5, 0.28), Vector2(0.34, 0.5), Vector2(-0.34, 0.5), Vector2(-0.5, 0.28),
]


## Finalise a SurfaceTool into an ArrayMesh. Normals are assigned per face as
## triangles are added, so there is nothing to generate here.
static func commit(tool: SurfaceTool) -> ArrayMesh:
	return tool.commit()


## Add one triangle with an explicit flat face normal.
##
## The normal is computed per triangle rather than with generate_normals() on
## purpose. SurfaceTool.generate_normals() groups coincident vertices, so a box's
## three faces meeting at a corner average into one wrong normal and the faceted
## look collapses. Assigning the face normal here guarantees flat shading, costs
## nothing extra, and keeps vertices unshared.
static func add_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Winding order defines the outward normal; cull_mode is left at the default
	# so a mistake in the winding shows up as a hole rather than as bad lighting.
	var normal := (b - a).cross(c - a)
	if normal.is_zero_approx():
		return
	normal = normal.normalized()
	tool.set_normal(normal)
	tool.add_vertex(a)
	tool.set_normal(normal)
	tool.add_vertex(b)
	tool.set_normal(normal)
	tool.add_vertex(c)


## Add a quad as two triangles, wound a-b-c-d.
static func add_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	add_triangle(tool, a, b, c)
	add_triangle(tool, a, c, d)


## Axis-aligned box centred on the origin, flat shaded.
##
## Each face is wound counter-clockwise when viewed from outside, so face normals
## point away from the centre. Get this wrong and the faces are culled, which
## looks like missing geometry rather than a shading bug.
static func box(size: Vector3) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	# +Z and -Z
	add_quad(tool, Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z))
	add_quad(tool, Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z))
	# -Y and +Y
	add_quad(tool, Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z))
	add_quad(tool, Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z))
	# -X and +X
	add_quad(tool, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z))
	add_quad(tool, Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z))
	return commit(tool)


## Box sheared so the top face is offset, producing slanted walls. Used for
## tapered shapes that a pure loft would over-complicate.
static func tapered_box(bottom: Vector3, top: Vector3, top_offset: Vector3 = Vector3.ZERO) -> ArrayMesh:
	var bh := bottom * 0.5
	var th := top * 0.5
	var lo := Vector3(-bh.x, -bh.y, bh.z)
	var ro := Vector3(bh.x, -bh.y, bh.z)
	var ri := Vector3(bh.x, -bh.y, -bh.z)
	var li := Vector3(-bh.x, -bh.y, -bh.z)
	var lt := Vector3(-th.x, th.y, th.z) + top_offset
	var rt := Vector3(th.x, th.y, th.z) + top_offset
	var ri_t := Vector3(th.x, th.y, -th.z) + top_offset
	var li_t := Vector3(-th.x, th.y, -th.z) + top_offset

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	add_quad(tool, lo, ro, rt, lt)
	add_quad(tool, ri, li, li_t, ri_t)
	add_quad(tool, lo, li, li_t, lt)
	add_quad(tool, ro, ri, ri_t, rt)
	add_quad(tool, li, lo, ro, ri)
	add_quad(tool, lt, rt, ri_t, li_t)
	return commit(tool)


## Prism swept along +Z from z=0 to z=length, centred on the X axis. `top_scale`
## below 1 shrinks the far end, giving the tapered struts and pylons the world
## needs.
static func prism(length: float, start_width: float, end_width: float, start_height: float, end_height: float) -> ArrayMesh:
	return sweep(length, Vector2(start_width, start_height), Vector2(end_width, end_height))


## Regular prism centred on the origin with `length` along +Y, optionally tapered
## toward the top. `up_taper` below 1 shrinks the top face.
static func cylinder(radius: float, length: float, sides := 8, up_taper := 1.0) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := length * 0.5
	var lower := PackedVector3Array()
	var upper := PackedVector3Array()
	for index in sides:
		var angle := TAU * float(index) / float(sides)
		var offset := Vector2(cos(angle), sin(angle)) * radius
		lower.append(Vector3(offset.x, -half, offset.y))
		upper.append(Vector3(offset.x * up_taper, half, offset.y * up_taper))
	_bridge_rings(tool, lower, upper, true, true)
	return commit(tool)


## Cone along +Y, base at y=0 and apex at y=height.
static func cone(radius: float, height: float, sides := 8) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lower := PackedVector3Array()
	for index in sides:
		var angle := TAU * float(index) / float(sides)
		lower.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	for index in sides:
		var angle := TAU * float(index) / float(sides)
		var next := TAU * float((index + 1) % sides) / float(sides)
		add_triangle(tool, lower[index], lower[next], Vector3(0.0, height, 0.0))
	add_triangle(tool, lower[0], lower[sides - 1], Vector3(0.0, height, 0.0))
	return commit(tool)


## Direction the section stack advances in. Wings and tail panels sweep along X
## (span), fuselages and fins along Z (length).
enum Axis { Z, X }

## Bridge a stack of cross-sections into a closed solid.
##
## Each section is a Dictionary; omitted keys default to zero, `width`/`height`
## to 1.0 and `scale` to 1.0:
## [codeblock]
## width   chord along the profile's first axis
## height  thickness along the profile's second axis
## y       vertical offset of this section
## z       position along the sweep axis
## [/codeblock]
## All sections share one `profile` outline, which is what keeps the quads
## between them a clean grid. Caps are optional so open shells stay possible.
static func loft(
	sections: Array,
	profile: Array[Vector2] = PROFILE_OCTAGON,
	cap_start := true,
	cap_end := true,
	axis: Axis = Axis.Z
) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rings: Array[PackedVector3Array] = []
	for section in sections:
		var data: Dictionary = section
		var width := float(data.get("width", 1.0))
		var height := float(data.get("height", 1.0))
		var scale := float(data.get("scale", 1.0))
		var y := float(data.get("y", 0.0))
		var along := float(data.get("z", 0.0))
		var offset_x := float(data.get("offset_x", 0.0))
		var offset_z := float(data.get("offset_z", 0.0))
		var ring := PackedVector3Array()
		for point in profile:
			# Profile x drives width (chord) and profile y drives height
			# (thickness); which world axis each lands on depends on the sweep.
			var chord := point.x * width * scale
			var thickness := point.y * height * scale
			var vertex := (
				Vector3(along, y + thickness, chord + offset_z)
				if axis == Axis.X
				else Vector3(chord + offset_x, y + thickness, along)
			)
			ring.append(vertex)
		rings.append(ring)

	for index in range(rings.size() - 1):
		_bridge_rings(tool, rings[index], rings[index + 1], false, false)

	if cap_start:
		_add_cap(tool, rings[0], true)
	if cap_end:
		_add_cap(tool, rings[rings.size() - 1], false)

	return commit(tool)


## Two-section tapered box sweeping along +Z, its origin at the wide end.
## Thin convenience wrapper over loft() for struts, poles, masts and gate markers.
static func sweep(length: float, start: Vector2, end: Vector2, profile: Array[Vector2] = PROFILE_BOX) -> ArrayMesh:
	return loft([
		{"width": start.x, "height": start.y, "z": 0.0},
		{"width": end.x, "height": end.y, "z": length},
	], profile, true, true)


## Single triangle, flat shaded. Useful for fins and small detail plates.
static func wedge(a: Vector3, b: Vector3, c: Vector3) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	add_triangle(tool, a, b, c)
	return commit(tool)


## Flat-shaded material for the faceted low-poly look: no smoothing across
## shared vertices, so large planes keep reading as planes.
static func flat_material(color: Color, roughness := 0.85, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	material.metallic_specular = 0.35
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return material


## Material for forms that should read as solid volumes rather than flat panels:
## a short specular highlight on curved surfaces, no transparency.
static func solid_material(color: Color, roughness := 0.7) -> StandardMaterial3D:
	return flat_material(color, roughness)


static func _add_cap(tool: SurfaceTool, ring: PackedVector3Array, reverse: bool) -> void:
	var count := ring.size()
	if count < 3:
		return
	# Fan from the ring centroid so non-convex outlines still cap cleanly.
	var centroid := Vector3.ZERO
	for point in ring:
		centroid += point
	centroid /= float(count)
	for index in range(count):
		var a := ring[index]
		var b := ring[(index + 1) % count]
		if reverse:
			add_triangle(tool, centroid, b, a)
		else:
			add_triangle(tool, centroid, a, b)


static func _bridge_rings(
	tool: SurfaceTool,
	lower: PackedVector3Array,
	upper: PackedVector3Array,
	cap_lower: bool,
	cap_upper: bool
) -> void:
	var count := lower.size()
	if count < 3 or upper.size() != count:
		return
	for index in range(count):
		var next := (index + 1) % count
		add_triangle(tool, lower[index], upper[index], upper[next])
		add_triangle(tool, lower[index], upper[next], lower[next])
	if cap_lower:
		_add_cap(tool, lower, true)
	if cap_upper:
		_add_cap(tool, upper, false)