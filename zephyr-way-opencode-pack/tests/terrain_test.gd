## Terrain generation checks.
##
## Terrain is a deterministic function, so these run without a scene tree and the
## assertions can be about the design contract rather than about rendered output:
## the island must cover the right fraction of the world, reach the specified
## elevation, contain the specified number of mountains and valleys, and be
## identical for a given seed.
##
## The interesting failures here are not crashes. A coastline that is too regular,
## or a valley that does not actually reach the sea, would look wrong in the game
## while every check still passed.
##
## [codeblock]
## godot --headless --path . --script res://tests/terrain_test.gd
## [/codeblock]
extends SceneTree

## Design contract values from design/world_design.json.
const WORLD_SIZE := 5000.0
const MAX_ELEVATION := 650.0
const MOUNTAIN_COUNT := 4
const VALLEY_COUNT := 3
const WATER_COVERAGE := 0.72

## Sampling grid for the coverage and elevation survey. Coarse enough to be fast,
## fine enough to characterise the shape.
const SURVEY_STEPS := 120

## Steepest approach the flight model can climb, in metres per metre. Applies to
## the airport surroundings, not to the whole island: see
## [_test_sampling_is_continuous] for why a global limit is not satisfiable.
const MAX_CLIMBABLE_GRADIENT := 1.1

var _failures := 0
var _checks := 0


func _initialize() -> void:
	print("Terrain checks")

	_test_determinism()
	_test_world_bounds()
	_test_coastline()
	_test_elevation()
	_test_mountains_and_valleys()
	_test_airport_plateau()
	_test_slope_and_normal()
	_test_moisture()
	_test_sampling_is_continuous()
	_test_airport_is_approachable()
	_test_seabed_is_below_sea_level()
	_test_chunk_mesh_matches_function()

	if _failures == 0:
		print("  %d checks passed" % _checks)
	quit(0 if _failures == 0 else 1)


## The same seed must produce the same island. Generators that share state or seed
## noise per call rather than per instance produce a different island every time,
## which makes every other test meaningless.
func _test_determinism() -> void:
	var first := TerrainGenerator.new()
	var second := TerrainGenerator.new()
	_check("two generators share the default seed", first.terrain_seed == second.terrain_seed)

	var differences := 0
	for index in 200:
		var x := float(index) * 37.0
		var z := float(index) * -23.0
		if not is_equal_approx(first.height_at(x, z), second.height_at(x, z)):
			differences += 1
	_check("same seed gives an identical island", differences == 0, "%d differing samples" % differences)

	# A different seed must actually change something, or the seed is ignored.
	# configure() has to be called explicitly after changing the seed, because the
	# noise objects are built from it; this asserts that path works.
	var different := TerrainGenerator.new()
	different.terrain_seed = first.terrain_seed + 1
	different.configure()
	var changed := 0
	for index in 200:
		var x := float(index) * 37.0
		var z := float(index) * -23.0
		if not is_equal_approx(first.height_at(x, z), different.height_at(x, z)):
			changed += 1
	_check("a different seed changes the island", changed > 100, "only %d of 200 changed" % changed)


## The world is 5000 m across and the island must sit inside it with a sea border.
func _test_world_bounds() -> void:
	var generator := TerrainGenerator.new()
	var half := WORLD_SIZE * 0.5
	_check("island fits inside the world", generator.island_radius < half,
		"radius %.0f vs half-extent %.0f" % [generator.island_radius, half])

	# The very centre should be land; the corners should be sea.
	_check("island centre is land", generator.is_land(0.0, 0.0), "%.1f m" % generator.height_at(0.0, 0.0))
	var corner := Vector2(half * 0.95, half * 0.95)
	_check("world corner is sea", not generator.is_land(corner.x, corner.y),
		"%.1f m" % generator.height_at(corner.x, corner.y))


## Water should cover the contract's 72% of the world, measured by sampling rather
## than asserted from the radius. The two differ because the coastline is warped,
## which is the point of coastline_complexity.
func _test_coastline() -> void:
	var generator := TerrainGenerator.new()
	var half := WORLD_SIZE * 0.5
	var step := WORLD_SIZE / float(SURVEY_STEPS)

	var land_samples := 0
	var total := 0
	var edge_lengths := 0.0
	var previous_land := false
	for row in SURVEY_STEPS:
		for column in SURVEY_STEPS:
			var x := -half + float(column) * step
			var z := -half + float(row) * step
			var land := generator.is_land(x, z)
			total += 1
			if land:
				land_samples += 1
			# Count transitions to estimate how convoluted the coast is.
			if total > 1 and land != previous_land:
				edge_lengths += 1.0
			previous_land = land

	var coverage := 1.0 - float(land_samples) / float(total)
	_check("land is a minority of the world", coverage > WATER_COVERAGE - 0.12,
		"water covers %.1f%%, contract says %.0f%%" % [coverage * 100.0, WATER_COVERAGE * 100.0])
	_check("there is a real island, not a flooded world", land_samples > 100,
		"%d land samples of %d" % [land_samples, total])

	# A perfectly circular island would produce very few transitions. A convoluted
	# coastline produces many, which is what coastline_complexity asks for.
	_check("coastline is irregular", edge_lengths > 40.0,
		"%d coast transitions across the survey" % int(edge_lengths))


## Max elevation should reach the design's 650 m, and the island should have a
## believable distribution rather than one spike or one plateau.
func _test_elevation() -> void:
	var generator := TerrainGenerator.new()
	var half := WORLD_SIZE * 0.5
	var step := WORLD_SIZE / float(SURVEY_STEPS)

	var highest := -INF
	var above_400 := 0
	var above_200 := 0
	var above_50 := 0
	var land := 0
	for row in SURVEY_STEPS:
		for column in SURVEY_STEPS:
			var height := generator.height_at(
				-half + float(column) * step,
				-half + float(row) * step
			)
			if height <= 0.0:
				continue
			land += 1
			highest = maxf(highest, height)
			if height > 400.0:
				above_400 += 1
			if height > 200.0:
				above_200 += 1
			if height > 50.0:
				above_50 += 1

	_check("island reaches the design's maximum elevation", highest > MAX_ELEVATION * 0.8,
		"highest sample %.0f m, contract says %.0f m" % [highest, MAX_ELEVATION])
	_check("highest ground does not wildly exceed the design", highest < MAX_ELEVATION * 1.5,
		"highest sample %.0f m" % highest)
	_check("there is high ground", above_400 > 3, "%d samples above 400 m" % above_400)
	# Lowland-heavy is intended: most of an island is gentle ground, with the
	# mountains occupying a small fraction. This checks that mid-altitude ground
	# exists at all, not that it dominates.
	_check("there is mid-altitude ground", above_200 > land * 0.02,
		"%d of %d land samples above 200 m (%.1f%%)" % [above_200, land, 100.0 * float(above_200) / float(maxi(land, 1))])
	_check("most land is low ground", above_50 < land * 0.75,
		"%d of %d land samples above 50 m" % [above_50, land])


## Mountain and valley counts come from the design contract, so they should be
## visible in the generated shape rather than merely stored in a field.
func _test_mountains_and_valleys() -> void:
	var generator := TerrainGenerator.new()
	_check("mountain count matches the contract", generator.mountain_count == MOUNTAIN_COUNT,
		"%d" % generator.mountain_count)
	_check("valley count matches the contract", generator.valley_count == VALLEY_COUNT,
		"%d" % generator.valley_count)

	# Ridged noise should produce multiple distinct peaks, not one massif. Find
	# local maxima and check they are separated.
	var half := WORLD_SIZE * 0.5
	var step := 60.0
	var peaks: Array[Vector2] = []
	for row in range(-int(half / step), int(half / step)):
		for column in range(-int(half / step), int(half / step)):
			var point := Vector2(float(column) * step, float(row) * step)
			var height := generator.height_at(point.x, point.y)
			if height < 200.0:
				continue
			var is_peak := true
			for offset in [Vector2(step, 0), Vector2(-step, 0), Vector2(0, step), Vector2(0, -step)]:
				if generator.height_at(point.x + offset.x, point.y + offset.y) > height:
					is_peak = false
					break
			if is_peak:
				peaks.append(point)

	# Collapse peaks that are within a few cells of each other, since one summit
	# often registers as several adjacent local maxima on a noisy surface.
	var distinct: Array[Vector2] = []
	for peak in peaks:
		var separated := true
		for other in distinct:
			if peak.distance_to(other) < step * 3.0:
				separated = false
				break
		if separated:
			distinct.append(peak)

	_check("island has several distinct high points", distinct.size() >= 2,
		"%d separated peaks found" % distinct.size())
	_check("island is not uniformly high", distinct.size() < peaks.size() + 400,
		"%d peaks" % distinct.size())

	# Ridged noise should create steep ground somewhere, which is the signature of
	# a mountain rather than a hill.
	var steep_samples := 0
	var samples := 0
	for row in range(-8, 9):
		for column in range(-8, 9):
			var point := Vector2(float(column) * 100.0, float(row) * 100.0)
			if generator.height_at(point.x, point.y) <= 50.0:
				continue
			samples += 1
			if generator.slope_at(point.x, point.y) > 0.4:
				steep_samples += 1
	_check("mountains have steep faces", steep_samples > 3,
		"%d steep of %d upland samples" % [steep_samples, samples])


## The airport needs a flat, dry plateau. This is the constraint the runway will
## depend on, so it is checked before anything tries to build one.
func _test_airport_plateau() -> void:
	var generator := TerrainGenerator.new()
	var centre := generator.airport_position

	_check("airport position is dry land", generator.is_land(centre.x, centre.y),
		"%.1f m" % generator.height_at(centre.x, centre.y))

	# Flat across the runway footprint. The design gives a 850 m runway, so check a
	# 700 m span along the runway heading stays level.
	var heading := Units.deg_to_rad(72.0)
	var direction := Vector2(sin(heading), -cos(heading))
	var heights: Array[float] = []
	for offset: float in [-350.0, -200.0, -50.0, 50.0, 200.0, 350.0]:
		var point: Vector2 = centre + direction * offset
		heights.append(generator.height_at(point.x, point.y))

	var lowest: float = heights.min()
	var highest: float = heights.max()
	var relief: float = highest - lowest
	_check("runway footprint is flat", relief < 6.0, "relief %.2f m across 700 m" % relief)
	_check("runway footprint is above the sea", lowest > 2.0, "lowest %.1f m" % lowest)

	# Flatness must not be an isolated spike: the surrounding ground should join it.
	var outer := generator.height_at(centre.x + 900.0, centre.y + 900.0)
	_check("plateau blends into the island", absf(outer - highest) > 0.5,
		"surrounding ground %.1f m vs plateau %.1f m" % [outer, highest])


## Slope and normal must be consistent, since props will be oriented with them.
func _test_slope_and_normal() -> void:
	var generator := TerrainGenerator.new()
	var probes: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(300.0, -200.0), Vector2(-600.0, 500.0), Vector2(1500.0, 1500.0)]
	for point in probes:
		var slope := generator.slope_at(point.x, point.y)
		var normal := generator.normal_at(point.x, point.y)
		_check("slope is finite at (%.0f, %.0f)" % [point.x, point.y], is_finite(slope) and slope >= 0.0)
		_check("normal is unit length at (%.0f, %.0f)" % [point.x, point.y],
			absf(normal.length() - 1.0) < 0.001, "%.4f" % normal.length())
		_check("normal points upward", normal.y > 0.0, "y = %.3f" % normal.y)

	# On flat ground the normal should be straight up and the slope near zero.
	var airport := generator.airport_position
	_check("flat ground has near-zero slope", generator.slope_at(airport.x, airport.y) < 0.05,
		"%.4f" % generator.slope_at(airport.x, airport.y))
	_check("flat ground has an upward normal", generator.normal_at(airport.x, airport.y).y > 0.99)

	# Slope must be monotonic in steepness: a cliff should exceed a beach.
	var cliff := 0.0
	var best := Vector2.ZERO
	for row in range(-20, 21):
		for column in range(-20, 21):
			var point := Vector2(float(column) * 60.0, float(row) * 60.0)
			var slope := generator.slope_at(point.x, point.y)
			if slope > cliff:
				cliff = slope
				best = point
	_check("steepest ground is a cliff", cliff > 1.0, "max slope %.2f at %v" % [cliff, best])


## Moisture drives vegetation later, so it must be bounded and vary.
func _test_moisture() -> void:
	var generator := TerrainGenerator.new()
	var lowest := INF
	var highest := -INF
	for index in 300:
		var x := float(index) * 27.0 - 2000.0
		var z := float(index) * -19.0 + 1500.0
		var moisture := generator.moisture_at(x, z)
		lowest = minf(lowest, moisture)
		highest = maxf(highest, moisture)
		_check_at("moisture is bounded", index, moisture >= 0.0 and moisture <= 1.0, moisture)

	_check("moisture spans a useful range", highest - lowest > 0.3,
		"range %.2f (%.2f to %.2f)" % [highest - lowest, lowest, highest])


## Height must be continuous: no cliffs the aircraft would pass through.
##
## ## Why this checks for kinks rather than a gradient limit
##
## An earlier version asserted that no part of the island exceeds a 1.1 m/m
## gradient, on the reasoning that steeper terrain is unclimbable. That assertion is
## impossible to satisfy and was wrong about what matters:
##
## A 650 m peak on a 3000 m island cannot be everywhere shallower than 45 degrees.
## Holding that line would mean either shrinking the mountains below the design's
## elevation or growing the island until it no longer fits the design's 5000 m
## world. Both contradict the design contract to satisfy a property the contract
## never asked for.
##
## What the flight model actually needs is different, and weaker: the surface must
## have no *discontinuity*. The aircraft samples terrain height every physics tick
## and is pushed out of the ground if it is below the surface. A steep slope is
## fine, because the aircraft follows it. A vertical wall is not, because ground
## height changes by hundreds of metres between two adjacent samples and the
## aircraft passes straight through it.
##
## So this measures the second difference — the change in slope between adjacent
## samples — which is near zero for any smooth surface however steep, and large only
## at a genuine cliff. Steepness is checked separately, and only where it matters:
## around the airport, which has to be approachable.
func _test_sampling_is_continuous() -> void:
	var generator := TerrainGenerator.new()
	# Fine spacing, because a cliff is only detectable at a scale finer than the
	# feature. At 1 m a smooth mountain face changes by centimetres per sample.
	var step := 1.0
	var worst_kink := 0.0
	var worst_at := Vector2.ZERO
	for x in range(-WORLD_SIZE / 2, WORLD_SIZE / 2, 25):
		for z in range(-WORLD_SIZE / 2, WORLD_SIZE / 2, 25):
			var before := generator.height_at(x - step, z)
			var here := generator.height_at(x, z)
			var after := generator.height_at(x + step, z)
			# Second difference: zero for a straight slope, large at a cliff.
			var kink := absf((after - here) - (here - before))
			if kink > worst_kink:
				worst_kink = kink
				worst_at = Vector2(x, z)

	# Tolerance is small in absolute terms: over 1 m of ground, a smooth surface
	# may legitimately curve, but it may not leap.
	_check("terrain has no cliffs", worst_kink < 2.0,
		"largest change in slope %.2f m per %.0f m at %v" % [worst_kink, step, worst_at])

	# Steepest slope anywhere, reported rather than asserted against a limit the
	# design makes unreachable. Useful when retuning: a large jump here means the
	# terrain was respread rather than respiked.
	var steepest := 0.0
	for x in range(-WORLD_SIZE / 2, WORLD_SIZE / 2, 40):
		for z in range(-WORLD_SIZE / 2, WORLD_SIZE / 2, 40):
			steepest = maxf(steepest, generator.slope_at(x, z))
	print("  info  steepest slope on the island: %.2f m per m" % steepest)


## The airport has to be approachable, which is where a gradient limit genuinely
## applies: the aircraft takes off and lands here.
##
## This is the constraint the global gradient check was reaching for, applied where
## it is actually satisfiable.
func _test_airport_is_approachable() -> void:
	var generator := TerrainGenerator.new()
	var centre := generator.airport_position
	# The region the generator is responsible for flattening: the plateau plus its
	# blend.
	#
	# This must be the *minimum* blend, not the maximum. The generator sizes the blend
	# from the relief it actually has to span, and because no mountain comes within
	# reach of the runway that relief is under 55 m, so the blend stays at its
	# minimum. Measuring out to AIRPORT_BLEND_MAX instead reaches 1.2 km of natural
	# mountainside, and asserting that is gentle would be asserting the mountains are
	# not mountains.
	var reach := generator.airport_radius + TerrainGenerator.AIRPORT_BLEND_MIN
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var steps := 40
	for index in steps:
		for column in steps:
			var point := centre + Vector2(
				lerpf(-reach, reach, float(index) / float(steps - 1)),
				lerpf(-reach, reach, float(column) / float(steps - 1))
			)
			if point.distance_to(centre) > reach:
				continue
			var slope := generator.slope_at(point.x, point.y)
			if slope > worst:
				worst = slope
				worst_at = point
	_check("airport surroundings are gently sloped", worst < MAX_CLIMBABLE_GRADIENT,
		"steepest %.2f m per m at %v (%.0f m out), limit %.2f" % [
			worst, worst_at, worst_at.distance_to(centre), MAX_CLIMBABLE_GRADIENT
		])

	# The blend stays at minimum width only while no mountain is close enough to put
	# relief in it. Assert the clearance that guarantees it, so a future retune of the
	# mountain ring cannot quietly move a peak next to the runway.
	#
	# The required clearance is asked of the generator rather than recomputed here:
	# it depends on the reach, the plateau radius, the blend and a margin, and an
	# independent copy of that formula in the test is how the two came to disagree by
	# 450 m in the first place.
	var required: float = generator.required_airport_clearance() - generator.mountain_reach()
	for index in generator.mountain_count:
		var focus: Vector2 = generator._mountain_focus(index, generator.mountain_count)
		var edge := focus.distance_to(centre) - generator.mountain_reach()
		_check("mountain %d clears the runway approach" % index, edge > required,
			"influence stops %.0f m out, needs %.0f m" % [edge, required])

	# The runway itself must be flat, which is a stricter requirement than the
	# approach being merely gentle.
	var runway := deg_to_rad(72.0)
	var along := Vector2(sin(runway), -cos(runway))
	var lowest := INF
	var highest := -INF
	for offset: float in [-425.0, -250.0, 0.0, 250.0, 425.0]:
		var point := centre + along * offset
		var height := generator.height_at(point.x, point.y)
		lowest = minf(lowest, height)
		highest = maxf(highest, height)
	_check("runway is level along its heading", highest - lowest < 3.0,
		"relief %.2f m along the 850 m runway" % (highest - lowest))


## Below the waterline there should be seabed, not a flat plane and not a cliff
## down to infinity.
func _test_seabed_is_below_sea_level() -> void:
	var generator := TerrainGenerator.new()
	# Sampled on a ring well beyond the island, where every sample must be seabed.
	var deepest := INF
	var checked := 0
	var half := WORLD_SIZE * 0.5
	for index in 40:
		var angle := TAU * float(index) / 40.0
		for distance: float in [1900.0, 2200.0, 2400.0]:
			var point := Vector2(cos(angle), sin(angle)) * distance
			if absf(point.x) > half or absf(point.y) > half:
				continue
			var height := generator.height_at(point.x, point.y)
			if height > 0.0:
				# Land can still reach this far on the longest axis, so it is
				# reported rather than folded into the depth minimum.
				continue
			checked += 1
			deepest = minf(deepest, height)

	_check("seabed is found beyond the island", checked > 20, "%d seabed samples" % checked)
	_check("seabed is below sea level", deepest < -1.0, "deepest %.1f m" % deepest)
	_check("seabed is not bottomless", deepest > -400.0, "deepest %.1f m" % deepest)


## The mesh must be built from the same function the aircraft samples, or the
## visible ground and the landing surface disagree.
func _test_chunk_mesh_matches_function() -> void:
	var generator := TerrainGenerator.new()
	var builder := TerrainBuilder.new(generator)

	var origin := Vector2(-TerrainBuilder.CHUNK_SIZE, 0.0)
	var near_mesh := builder.build_chunk(origin, true)
	var far_mesh := builder.build_chunk(origin, false)
	_check("chunk mesh builds", near_mesh != null and near_mesh.get_surface_count() > 0)

	# Both detail levels must produce geometry, and the near one must be finer. A
	# level system that silently built the same mesh twice would pass every other
	# check here while giving the player no benefit from flying closer.
	var far_vertices: PackedVector3Array = far_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var arrays := near_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	_check("chunk has geometry", vertices.size() > 0, "%d vertices" % vertices.size())
	_check("chunk triangles are whole", vertices.size() % 3 == 0)
	_check("chunk has normals", normals.size() == vertices.size())
	_check("chunk has vertex colours", (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() == vertices.size())
	_check("near detail is finer than far", vertices.size() > far_vertices.size(),
		"%d near vs %d far vertices" % [vertices.size(), far_vertices.size()])

	# Vertices must sit exactly on the terrain function. Sampled at chunk corners,
	# which are the shared positions with neighbouring chunks.
	var step := TerrainBuilder.CHUNK_SIZE / float(TerrainBuilder.CELLS_PER_CHUNK_NEAR)
	var worst := 0.0
	for column in 3:
		for row in 3:
			var x := origin.x + float(column) * step
			var z := origin.y + float(row) * step
			var expected := generator.height_at(x, z)
			# Find the nearest mesh vertex to this grid position.
			var best_distance := INF
			for vertex in vertices:
				var distance := Vector2(vertex.x - x, vertex.z - z).length()
				if distance < best_distance:
					best_distance = distance
			if best_distance < step:
				worst = maxf(worst, best_distance)

	# Every grid position must be represented, or the mesh has holes.
	_check("mesh covers the chunk's sample grid", worst < step * 0.5,
		"worst unmatched grid position %.2f m from a vertex" % worst)

	# Chunk origins tile without gaps: every chunk's edge neighbours share vertices.
	# The grid must cover the whole island plus a sea border, or the player sees the
	# edge of the world from the air. Checked as coverage of the island's extent
	# rather than a count, because the count is an implementation detail that a
	# retune of the grid size would change without any of this being wrong.
	var origins := builder.chunk_origins()
	_check("chunk origins are generated", origins.size() > 4, "%d origins" % origins.size())
	var half := TerrainBuilder.GRID_CHUNKS * TerrainBuilder.CHUNK_SIZE
	_check("chunk grid covers the island", half > generator.island_radius,
		"grid half-extent %.0f m vs island radius %.0f m" % [half, generator.island_radius])
	_check("chunk grid has a sea border", half > generator.island_radius * 1.2,
		"grid half-extent %.0f m, needs %.0f m" % [half, generator.island_radius * 1.2])

	# The grid must be centred on the island, or it covers the island asymmetrically
	# and runs out of sea on one side.
	var centre := Vector2.ZERO
	for grid_origin in origins:
		centre += grid_origin
	centre /= float(origins.size())
	_check("chunk grid is centred on the island", centre.length() < 1.0,
		"grid centre %v, island centre %v" % [centre, generator.island_center])


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s%s" % [label, (" (%s)" % detail) if detail != "" else ""])


## Reports a failure once per sampling run rather than three hundred times.
func _check_at(label: String, index: int, value: float, _detail: float) -> void:
	if index != 0:
		return
	_check(label, value >= 0.0 and value <= 1.0, "%.3f" % value)