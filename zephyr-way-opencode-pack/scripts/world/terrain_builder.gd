## Builds the terrain mesh from a [TerrainGenerator].
##
## The mesh is chunked rather than one large grid, for three reasons:
##
## 1. Generation is spread across chunks instead of one long blocking call.
## 2. Only chunks near the aircraft need full detail; distant ones can use a coarser
##    step, which is where most of the triangle budget is saved.
## 3. A seam is impossible because chunk vertices are sampled from the same
##    function at the same world positions, so neighbours agree exactly.
##
## Geometry is deliberately coarse and flat shaded. `design/art_direction.json`
## asks for low detail with visible but clean faceting, and coarse triangles read
## as intentional at altitude, where fine tessellation would just shimmer.
class_name TerrainBuilder
extends RefCounted

## Chunk edge length in metres.
const CHUNK_SIZE := 500.0
## Grid cells across a chunk at the *far* detail level. 500 m / 12 = ~42 m cells.
##
## Coarse on purpose. `design/art_direction.json` asks for low detail with visible
## but clean faceting, and large facets read as deliberate from the air, where finer
## tessellation would only shimmer. Coarse cells are also what keeps generation fast:
## each cell costs one terrain evaluation.
const CELLS_PER_CHUNK := 12
## Grid cells across a chunk at the *near* detail level. 500 m / 25 = 20 m cells.
const CELLS_PER_CHUNK_NEAR := 25
## Distance in metres within which a chunk is built at [constant LOD_NEAR].
const LOD_DISTANCE := 900.0

## Extra chunks beyond the island's edge, so the horizon is water rather than the
## edge of the terrain.
const SEA_BORDER_CHUNKS := 2

var generator: TerrainGenerator

## Cached chunk origins. The grid is fixed by the island radius, so it is computed
## once: rebuilding the list on every aircraft movement was a per-frame allocation
## for no benefit.
var _origins: Array[Vector2] = []
## Half-extent of the grid, in chunks. Derived from the island radius so resizing the
## island does not leave the terrain short of its own shoreline.
var _grid_chunks := 0


func _init(terrain_generator: TerrainGenerator = null) -> void:
	generator = terrain_generator if terrain_generator != null else TerrainGenerator.new()
	_build_origin_cache()


## Half-extent of the chunk grid, in chunks.
func grid_chunks() -> int:
	return _grid_chunks


func _build_origin_cache() -> void:
	# Enough chunks to reach the island's land, plus a sea border. A fixed count was
	# wrong twice over: too small for a larger island, which left the shoreline
	# unbuilt, and larger than needed for a smaller one, which built a lot of ocean.
	_grid_chunks = int(ceil(generator.island_radius / CHUNK_SIZE)) + SEA_BORDER_CHUNKS
	_origins = []
	for x in range(-_grid_chunks, _grid_chunks + 1):
		for z in range(-_grid_chunks, _grid_chunks + 1):
			_origins.append(Vector2(float(x) * CHUNK_SIZE, float(z) * CHUNK_SIZE))


## Chunk origins covering the island, in world space.
func chunk_origins() -> Array[Vector2]:
	return _origins


## Build one chunk as a flat-shaded mesh.
##
## Vertices are emitted per face rather than shared, which is what makes the
## faceting visible; `generate_normals` averages coincident vertices and would
## smooth it away.
func build_chunk(origin: Vector2, near: bool) -> ArrayMesh:
	# Cells across the chunk at this detail level.
	#
	# A boolean rather than an integer level, because an integer invites the mistake
	# of dividing by it and getting *less* geometry for more detail. The two
	# resolutions are named constants instead, so the intent is visible at the call.
	var cells := CELLS_PER_CHUNK_NEAR if near else CELLS_PER_CHUNK
	var step := CHUNK_SIZE / float(cells)

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Sample once into a grid, then emit faces from it. Sampling per face would
	# evaluate the terrain function up to six times as often.
	#
	# No smoothing happens here: the generator already limits its own gradient, so
	# the mesh and the aircraft's collision sample are guaranteed to agree. Applying
	# a second limit here would make the drawn surface differ from the landed one.
	var heights := PackedFloat32Array()
	heights.resize((cells + 1) * (cells + 1))
	for row in cells + 1:
		for column in cells + 1:
			var x := origin.x + float(column) * step
			var z := origin.y + float(row) * step
			heights[row * (cells + 1) + column] = generator.height_at(x, z)

	for row in cells:
		for column in cells:
			var x0 := origin.x + float(column) * step
			var z0 := origin.y + float(row) * step
			var x1 := x0 + step
			var z1 := z0 + step
			var h00 := heights[row * (cells + 1) + column]
			var h10 := heights[row * (cells + 1) + column + 1]
			var h01 := heights[(row + 1) * (cells + 1) + column]
			var h11 := heights[(row + 1) * (cells + 1) + column + 1]

			var a := Vector3(x0, h00, z0)
			var b := Vector3(x1, h10, z0)
			var c := Vector3(x1, h11, z1)
			var d := Vector3(x0, h01, z1)

			# Split each cell along its shorter diagonal, so ridges stay sharp
			# instead of showing a stair-step along the longer axis.
			if absf(h00 - h11) < absf(h10 - h01):
				_add_face(tool, a, b, d, (a + b + d) / 3.0)
				_add_face(tool, b, c, d, (b + c + d) / 3.0)
			else:
				_add_face(tool, a, b, c, (a + b + c) / 3.0)
				_add_face(tool, a, c, d, (a + c + d) / 3.0)

	# Normals are already assigned per face by _add_face, so nothing is generated
	# here. Calling generate_normals would average the coincident vertices and
	# smooth away the faceting.
	return tool.commit()


## Emit one triangle with its face normal and biome colour.
##
## Colour is written per vertex so the terrain can be tinted by height and slope
## with no textures. Setting it here rather than afterwards is what Godot's API
## requires: ArrayMesh has no surface_set_color, because colours are a property of
## the vertex data rather than something applied afterwards.
func _add_face(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, centre: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	if normal.is_zero_approx():
		return
	normal = normal.normalized()
	# Slope comes from the face normal, which is free, rather than from
	# generator.slope_at(). That call takes four more terrain samples, and at two
	# faces per cell across a whole island it dominated chunk generation.
	var slope := _slope_from_normal(normal)
	var color := face_color(generator, centre, slope)
	tool.set_normal(normal)
	tool.set_color(color)
	tool.add_vertex(a)
	tool.set_normal(normal)
	tool.set_color(color)
	tool.add_vertex(b)
	tool.set_normal(normal)
	tool.set_color(color)
	tool.add_vertex(c)


## Steepness implied by a face normal, in metres per metre.
##
## Equivalent to the gradient of the plane the face lies in, and derived from data
## already in hand.
static func _slope_from_normal(normal: Vector3) -> float:
	var vertical := absf(normal.y)
	if vertical >= 1.0:
		return 0.0
	return sqrt(1.0 - vertical * vertical) / maxf(vertical, 0.0001)


## Colour for a face, chosen from the design palette by height and slope.
##
## Palette groups rather than literal colours, so retinting the island means editing
## design/color_palette.json rather than this script.
static func face_color(generator: TerrainGenerator, centre: Vector3, slope: float) -> Color:
	var height := centre.y

	# Steep ground is bare rock regardless of altitude.
	if slope > STEEP_SLOPE:
		var rock := Palette.color("rock.cool_grey")
		# Higher rock is darker and colder.
		var high := Palette.color("rock.dark")
		return rock.lerp(high, clampf(height / 450.0, 0.0, 0.6))

	# Snow on the highest, flattest ground.
	if height > SNOW_LINE:
		return Palette.color("snow.top").lerp(Palette.color("snow.shade"), clampf(slope * 2.0, 0.0, 0.5))

	# Beach at the waterline.
	if height < BEACH_HEIGHT:
		return Palette.color("sand.dry").lerp(Palette.color("sand.wet"), 1.0 - clampf(height / BEACH_HEIGHT, 0.0, 1.0))

	# Grass, greener where it is damp.
	#
	# Moisture is asked for without a height, because the height is already known
	# here. The generator's version samples the terrain again to work out how damp the
	# ground is, which is a wasted evaluation per face.
	var grass := Palette.color("grass.meadow").lerp(
		Palette.color("grass.lush"),
		generator.moisture_at_height(centre.x, centre.z, height)
	)
	# High ground dries out towards the palette's highland tone.
	return grass.lerp(Palette.color("grass.highland"), clampf((height - 200.0) / 320.0, 0.0, 0.65))


## Ground slope above which terrain is treated as cliff, in metres per metre.
const STEEP_SLOPE := 0.55
## Altitude above which snow appears, in metres.
const SNOW_LINE := 520.0
## Altitude below which sand appears, in metres.
const BEACH_HEIGHT := 12.0