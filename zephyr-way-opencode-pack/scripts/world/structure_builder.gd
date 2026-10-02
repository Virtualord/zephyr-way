## Accumulates many coloured primitives into a single flat-shaded mesh.
##
## Built structures -- a runway, a terminal, a lighthouse -- are dozens of boxes and
## cylinders. Emitted as individual MeshInstance3Ds that is dozens of draw calls and,
## worse, dozens of nodes to keep track of. This collects them into one SurfaceTool
## and commits one ArrayMesh, so a whole building costs one draw call.
##
## Colour is per-face and baked into the vertex stream rather than carried by a
## material. That is what lets a single mesh be a striped lighthouse tower and a
## marked runway at the same time, which is the whole reason these are worth merging.
##
## Winding order defines the outward normal, matching [MeshBuilder]: get it wrong and
## the face is culled, which reads as missing geometry rather than as a shading bug.
class_name StructureBuilder
extends RefCounted

var _tool: SurfaceTool
var _triangles := 0


func _init() -> void:
	_tool = SurfaceTool.new()
	_tool.begin(Mesh.PRIMITIVE_TRIANGLES)


## How many triangles have been added so far. A structure that silently produced
## nothing would otherwise be invisible rather than wrong.
func triangle_count() -> int:
	return _triangles


func is_empty() -> bool:
	return _triangles == 0


## Commit to a single mesh. Returns null if nothing was added, so callers have to
## decide what an empty structure means rather than getting a zero-triangle mesh.
func build() -> ArrayMesh:
	if is_empty():
		return null
	return _tool.commit()


## One triangle with a flat face normal and a single colour.
func triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal := (b - a).cross(c - a)
	if normal.is_zero_approx():
		return
	normal = normal.normalized()
	_tool.set_color(color)
	_tool.set_normal(normal)
	_tool.add_vertex(a)
	_tool.set_color(color)
	_tool.set_normal(normal)
	_tool.add_vertex(b)
	_tool.set_color(color)
	_tool.set_normal(normal)
	_tool.add_vertex(c)
	_triangles += 1


## A quad as two triangles, wound a-b-c-d.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	triangle(a, b, c, color)
	triangle(a, c, d, color)


## Axis-aligned box, transformed. Each face is wound so its normal points away from
## the centre.
func box(xform: Transform3D, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var corners := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z),
		Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	# Bottom ring is 0-3 and top ring is 4-7, so a side face joins i % 4 to
	# (i + 1) % 4 across the two runs.
	for i in 4:
		var j := (i + 1) % 4
		quad(
			xform * corners[i],
			xform * corners[i + 4],
			xform * corners[j + 4],
			xform * corners[j],
			color
		)


## A box with its own rotation and offset, given by a basis and a translation.
## Convenience over building a [Transform3D] at every call site.
func oriented_box(
	basis: Basis, at: Vector3, size: Vector3, color: Color
) -> void:
	box(Transform3D(basis, at), size, color)


## Horizontal quad at height [param y], spanning a rectangle in the XZ plane.
## [param z_forward] picks which edge the normal points along.
func slab(
	basis: Basis,
	at: Vector3,
	size_xz: Vector2,
	color: Color,
	face_up := true
) -> void:
	var h := Vector3(size_xz.x, 0.0, size_xz.y) * 0.5
	var a := basis * (at + Vector3(-h.x, 0.0, -h.z))
	var b := basis * (at + Vector3(h.x, 0.0, -h.z))
	var c := basis * (at + Vector3(h.x, 0.0, h.z))
	var d := basis * (at + Vector3(-h.x, 0.0, h.z))
	if face_up:
		quad(a, d, c, b, color)
	else:
		quad(a, b, c, d, color)


## Faceted cylinder or cone, base at the transform's origin, growing along +Y.
##
## [param sides] is the point count around the axis. Kept low deliberately: eight sides
## reads as a deliberate faceted cylinder in this art direction, and sixteen starts to
## look smooth enough to belong to a different style.
func cylinder(
	xform: Transform3D,
	radius_bottom: float,
	radius_top: float,
	height: float,
	color: Color,
	sides := 8,
	cap_top := true,
	cap_bottom := false
) -> void:
	var ring_a := PackedVector3Array()
	var ring_b := PackedVector3Array()
	for i in sides:
		var angle := TAU * float(i) / float(sides)
		var unit := Vector3(cos(angle), 0.0, sin(angle))
		ring_a.append(xform * (unit * radius_bottom))
		ring_b.append(xform * (unit * radius_top + Vector3(0.0, height, 0.0)))
	for i in sides:
		var j := (i + 1) % sides
		quad(ring_a[i], ring_b[i], ring_b[j], ring_a[j], color)
	if cap_top and radius_top > 0.0:
		for i in sides:
			triangle(ring_b[0], ring_b[(i + 1) % sides], ring_b[i], color)
	if cap_bottom and radius_bottom > 0.0:
		for i in sides:
			triangle(ring_a[0], ring_a[i], ring_a[(i + 1) % sides], color)


## Cone with a polygonal base, base at the transform's origin, apex along +Y.
func cone(
	xform: Transform3D, radius: float, height: float, color: Color, sides := 8
) -> void:
	cylinder(xform, radius, 0.0, height, color, sides, false, false)


## A four-sided pyramid, apex along +Y. Used for roofs that should read as angular
## rather than as a cone.
func pyramid(
	xform: Transform3D, size_xz: Vector2, height: float, color: Color
) -> void:
	var h := Vector3(size_xz.x, 0.0, size_xz.y) * 0.5
	var corners := [
		xform * Vector3(-h.x, 0.0, -h.z),
		xform * Vector3(h.x, 0.0, -h.z),
		xform * Vector3(h.x, 0.0, h.z),
		xform * Vector3(-h.x, 0.0, h.z),
	]
	var apex := xform * Vector3(0.0, height, 0.0)
	for i in 4:
		triangle(corners[i], apex, corners[(i + 1) % 4], color)
	# Base, wound so the normal points down and out of the shape. The other winding
	# points it up, into the interior, where it is culled from every angle that can
	# actually see it.
	quad(corners[0], corners[1], corners[2], corners[3], color)


## Triangular gable roof over a rectangular footprint.
##
## Built as a prism rather than a pyramid so a long building gets a ridge line, which
## is what makes a hangar or a terminal read as a building from the air rather than as
## a lump. [param overhang] extends past the walls.
func gable_roof(
	basis: Basis,
	at: Vector3,
	size_xz: Vector2,
	height: float,
	overhang: float,
	color: Color
) -> void:
	var half_x := size_xz.x * 0.5 + overhang
	var half_z := size_z_half(size_xz, overhang)
	var x0 := basis * Vector3(-half_x, at.y, at.z - half_z)
	var x1 := basis * Vector3(half_x, at.y, at.z - half_z)
	var x2 := basis * Vector3(half_x, at.y, at.z + half_z)
	var x3 := basis * Vector3(-half_x, at.y, at.z + half_z)
	var ridge_a := basis * Vector3(-half_x, at.y + height, at.z)
	var ridge_b := basis * Vector3(half_x, at.y + height, at.z)
	# Two long slopes.
	quad(x0, x1, ridge_b, ridge_a, color)
	quad(x3, x2, ridge_b, ridge_a, color)
	# Gable ends, slightly darker would be nice but one material keeps it to one call.
	triangle(x0, x3, ridge_a, color)
	triangle(x1, ridge_b, x2, color)
	# Underside, so the roof is not see-through from a low camera.
	quad(x0, x1, x2, x3, color)


func size_z_half(size_xz: Vector2, overhang: float) -> float:
	return size_xz.y * 0.5 + overhang


## The one material every structure mesh uses.
##
## Vertex colours as albedo is what makes merging worthwhile: a striped lighthouse
## tower and a marked runway are the same draw call because the colour lives in the
## vertices rather than in a material per part. Shared and static so the whole airport
## is one material, and so it matches the terrain's own flat-shaded, unlit-by-specular
## treatment.
##
## `SPECULAR_DISABLED` is deliberate and matches `TerrainBuilder`. A soft specular
## sheen on a low-poly runway is the one thing that would make these read as a
## different art style from the island they sit on.
static func material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	return mat


## A structure mesh with the shared material already assigned.
##
## Returns null for an empty builder, and warns, rather than producing a
## zero-triangle mesh that looks like a deliberate hole in the world.
static func to_mesh_instance(name: String, builder: StructureBuilder) -> MeshInstance3D:
	if builder == null or builder.is_empty():
		push_warning("StructureBuilder: '%s' produced no geometry." % name)
		return null
	var mesh := builder.build()
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.material_override = material()
	# Structures sit on terrain that is itself a shadow caster and receiver. Leaving
	# this on would have the runway stripe its own shadow and the building shadow the
	# apron twice over.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## A flat marker plate standing on end, for signs and approach-light heads.
## [param height] is above the local origin.
func plate(
	basis: Basis, at: Vector3, size: Vector2, height: float, color: Color
) -> void:
	var h := size * 0.5
	var a := basis * Vector3(at.x - h.x, at.y, at.z)
	var b := basis * Vector3(at.x + h.x, at.y, at.z)
	var c := basis * Vector3(at.x + h.x, at.y + height, at.z)
	var d := basis * Vector3(at.x - h.x, at.y + height, at.z)
	quad(a, b, c, d, color)
	quad(b, a, d, c, color)
