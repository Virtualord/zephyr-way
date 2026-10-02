## Deterministic terrain height and biome field for the island.
##
## This is the single source of truth for the shape of the world. The terrain mesh
## is built from it and [AircraftController] samples it for ground contact, so the
## visible surface and the collision surface cannot disagree.
##
## ## Why a function rather than generated mesh data
##
## Sampling height at an arbitrary point is what makes terrain interactive: the
## aircraft needs it every physics tick, and props will need the same answer. A
## heightfield function gives that for free and is deterministic by construction, so
## regenerating twice produces identical results and neighbouring chunks agree on
## shared vertices with no seam handling at all.
##
## ## Composition
##
## Height is built in layers, because each layer corresponds to something the
## design contract asks for:
##
## [codeblock]
##   coastline   domain-warped radial falloff, sets where land ends
##   base        gentle rolling ground, so flat areas are not dead level
##   mountains   ridged noise shaped by a broad summit and a linear skirt
##   valleys     troughs carved along defined lines
##   airport     a flat plateau at the design's airport position
##   seabed      relief below the waterline
## [/codeblock]
##
## Ridged noise forms crests rather than blobs, which is what makes a low-poly
## mountain read as a mountain.
##
## ## Steepness is a design constraint, not an afterthought
##
## The terrain has to be flyable: a slope steeper than the flight model can climb
## reads as passing through the ground. Every mountain is therefore built as a broad
## summit plateau above a long linear skirt, sized from the peak height rather than
## tuned by eye. See [_mountain_elevation] for why the obvious alternatives fail.
##
## Extends RefCounted and uses no nodes, so it can be sampled and tested freely.
class_name TerrainGenerator
extends RefCounted

## Sea level. Everything below this is underwater.
const SEA_LEVEL := 0.0

# --- Noise sources. Each is seeded and configured in configure().

var _coast_noise: FastNoiseLite
var _base_noise: FastNoiseLite
var _ridge_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _moisture_noise: FastNoiseLite

## Position, direction and shape of each carved valley, in world space.
var _valleys: Array[Dictionary] = []

## Peak absolute value the ridge noise actually reaches near the island.
##
## Sampled rather than assumed, because Simplex noise is bounded by 1 in principle
## but never attains it, and assuming a bound of 1 makes every mountain too short.
var _ridge_peak := 1.0


## Island radius in metres: the distance from the island centre at which the
## shoreline falls.
##
## Land starts submerging at [constant SHORE_LOW] of this and is gone by
## [constant SHORE_HIGH], so the usable interior is a fraction of it.
##
## Sized for the design's 72% water coverage and for the 650 m peaks. A peak that
## height needs roughly 590 m of base to stay within the flight model's climbable
## gradient, plus room for the airport plateau, and that does not fit on a smaller
## island.
@export var island_radius := 1500.0

## Peak elevation of the mountains, in metres. From design/world_design.json.
@export var max_elevation := 650.0

## How much the coastline is broken up, 0 to 1.
@export_range(0.0, 1.0, 0.01) var coastline_complexity := 0.7

## Number of mountain masses.
@export_range(1, 8, 1) var mountain_count := 4

## Number of carved valleys.
@export_range(0, 8, 1) var valley_count := 3

## Centre of the island in world space.
##
## At the origin, so the island sits centred in the design's 5000 m world.
##
## The design places its features at fixed coordinates relative to that origin —
## airport at (-850, 420), village at (200, 800), lighthouse at (1400, -700) — so
## the island has to be centred there for them to land in sensible places. Offsetting
## the centre to give the airport more clear ground pushed the island out through
## the world's western edge and put the village and lighthouse in open water.
@export var island_center := Vector2.ZERO

## Fraction of the island radius at which mountain summits sit.
@export_range(0.2, 0.7, 0.01) var mountain_ring_fraction := 0.5

## Angle step used when searching the ring for a clear position, in radians.
const FOCUS_ANGLE_STEP := 0.06

## Outward growth of the search ring per angle step, in metres.
const FOCUS_RADIUS_STEP := 12.0

## Radius over which a mountain falls from summit to nothing, as a fraction of the
## island radius.
##
## Sized so the massifs are discrete hills with low ground between them, rather than
## one continuous range covering the island.
##
## This was originally 1.0, the same as the island radius, and that made every
## mountain cover the whole island: their contributions summed everywhere, so most of
## the land sat above 50 m and there was no low ground left for the airport. The
## airport ended up on a mountainside with 750 m of relief within 1.1 km, and the
## plateau blend had to span all of it.
##
## A steep mountain is acceptable. The aircraft cannot climb it, but it can fly
## around it, and the surface stays continuous either way — which is the property
## that actually matters. What is not acceptable is mountain everywhere, because then
## there is nowhere flat to put a runway.
@export_range(0.1, 1.0, 0.01) var mountain_reach_fraction := 0.3

## Flat plateau reserved for the airport, from design/world_design.json.
@export var airport_position := Vector2(-850.0, 420.0)
## Runway heading in degrees, from design/world_design.json.
##
## The terrain does not use this, but it belongs with the other airport fields
## because it is part of the same design contract, and the aircraft's start heading
## needs it.
@export var airport_heading_degrees := 72.0
## Runway length in metres, from design/world_design.json.
@export var runway_length := 850.0
## Radius of the flat area. Comfortably more than the runway's half-length.
@export var airport_radius := 500.0
## Elevation of the plateau.
@export var airport_elevation := 14.0

## Minimum distance from the airport to a mountain's focus, in metres.
##
## This is the distance to the *focus*, but the constraint is on the mountain's
## *edge*: a massif extends a full [method mountain_reach] beyond its focus, so the
## clearance that matters is this value minus the reach. Confusing the two put
## summits 806 m from the runway centre, well inside the 1130 m the approach needs,
## and the blend had to span a mountain flank.
##
## Sizing it from the runway outwards rather than picking a number:
## [codeblock]
##   clearance >= reach + plateau radius + blend
## [/codeblock]
## Below that, mountain relief falls inside the blend and the plateau edge has to
## climb several hundred metres. Measured here rather than asserted, because the
## reach and the plateau radius are both tunable and the relationship between them
## is the actual invariant.
##
## It must also stay below the island radius. Beyond that, no position on the
## mountain ring satisfies it, every focus falls back to the same position, and the
## range collapses into one mass. That bound is why the island centre sits where it
## Distance from the airport to a mountain's focus, in metres.
##
## Resolved to [method required_airport_clearance] in [method configure]. Not a
## configurable value: it is a consequence of the reach, the plateau and the blend,
## and letting it be set independently is how it came to disagree with all three.
var airport_clearance := 1580.0

## Extra clearance beyond the minimum the approach requires, in metres.
##
## A margin so ordinary retuning of the reach or the plateau radius does not
## immediately put a summit in the blend. The minimum is computed in
## [method required_airport_clearance]; this is headroom on top of it.
@export var airport_clearance_margin := 220.0

## Distance from the airport to the nearest mountain focus that keeps mountain relief
## out of the plateau blend.
##
## Derived rather than configured, because the three quantities it depends on are all
## tunable and the relationship between them is the real constraint. Hard-coding the
## result was how the clearance came to be 450 m short of what the approach needed.
func required_airport_clearance() -> float:
	return mountain_reach() + airport_radius + AIRPORT_BLEND_MIN + airport_clearance_margin


## Seed for every noise source. The same seed always produces the same island.
@export var terrain_seed := 20261


func _init() -> void:
	configure()


## Build or rebuild the noise sources and valley layout.
##
## Separate from the constructor because these are derived from the exported fields,
## and a caller that assigns a seed afterwards must be able to apply it. Constructing
## them in `_init` means an assigned seed is silently ignored and every instance
## produces the same island.
func configure() -> void:
	_coast_noise = _make_noise(0.00055, 4, 0.5, terrain_seed + 11)
	_base_noise = _make_noise(0.0016, 4, 0.5, terrain_seed + 23)
	_ridge_noise = _make_noise(RIDGE_FREQUENCY, RIDGE_OCTAVES, 0.5, terrain_seed + 37)
	_detail_noise = _make_noise(0.0068, 3, 0.45, terrain_seed + 53)
	_moisture_noise = _make_noise(0.0011, 3, 0.5, terrain_seed + 71)
	_measure_ridge_peak()
	_place_valleys()
	airport_clearance = required_airport_clearance()
	_measure_saturation_ceiling()


func _make_noise(frequency: float, octaves: int, gain: float, seed_value: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	noise.fractal_gain = gain
	noise.fractal_lacunarity = 2.0
	return noise


## Largest absolute value the ridge noise reaches anywhere near the island.
func _measure_ridge_peak() -> void:
	var peak := 0.0
	var reach := island_radius * 1.2
	var samples := RIDGE_PEAK_SAMPLES
	for row in samples:
		for column in samples:
			var x := lerpf(-reach, reach, float(column) / float(samples - 1))
			var z := lerpf(-reach, reach, float(row) / float(samples - 1))
			peak = maxf(peak, absf(_ridge_noise.get_noise_2d(x, z)))
	_ridge_peak = maxf(peak, 0.05)


## Resolution of the ridge peak search, per axis.
const RIDGE_PEAK_SAMPLES := 40
## Sharpness of the ridge crests. Higher is sharper.
const RIDGE_SHARPNESS := 1.6
## Ridge noise frequency, and therefore the size of its features.
##
## Low enough that a feature spans hundreds of metres. The terrain is sampled every
## 17 m by the mesh and continuously by the aircraft, so a feature only a few tens
## of metres across varies faster than the climbable gradient allows no matter what
## the falloff does.
const RIDGE_FREQUENCY := 0.00042
## Octaves of ridge noise. Few, so the finest detail stays broad.
const RIDGE_OCTAVES := 3


## Lay out the carved valleys, spread around the island and pointing outward so
## they run from the interior down to the coast.
func _place_valleys() -> void:
	_valleys.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed + 101
	for index in maxi(valley_count, 0):
		_valleys.append({
			"angle": TAU * float(index) / float(maxi(valley_count, 1)) + rng.randf_range(-0.4, 0.4),
			"length": island_radius * rng.randf_range(0.7, 1.0),
			"width": rng.randf_range(160.0, 300.0),
			"depth": rng.randf_range(40.0, 95.0),
		})


## Terrain height in metres at a world position.
##
## The authoritative value: the mesh and the aircraft both use it, so what you see
## is what you land on.
func height_at(x: float, z: float) -> float:
	return SEA_LEVEL + _height(Vector2(x, z))


## Steepest terrain the flight model can climb, in metres per metre. Must stay in
## step with FlightTuning's equivalent limit: terrain and aircraft have to agree on
## what counts as a wall.
const MAX_GRADIENT := 1.1


## Height above sea level at a point.
##
## Layers are composed, then the airport plateau is blended in over the top. The
## order matters: the plateau has to be able to raise land that the coast mask would
## otherwise treat as seabed, because the design's runway reaches 350 m from the
## plateau centre and that is close enough to the shore for the mask to be zero.
func _height(point: Vector2) -> float:
	var mask := _land_mask(point)
	var natural := _seabed_depth(point)
	if mask > 0.0:
		natural = _base_elevation(point) * mask
		natural += _mountain_elevation(point) * mask
		natural += _detail_elevation(point) * mask
		natural -= _valley_depth(point) * mask

	return _apply_airport(point, natural)


## Blend the airport plateau into natural terrain.
##
## The blend is the whole point of this function. Returning a constant across the
## plateau disc, which is what an earlier version did, makes the plateau edge a
## vertical cliff: measured as a 638 m step over 1 m, because a 650 m mountain's
## flank reaches the plateau. The blend width is what makes that join a slope
## instead, and it has to be wide enough for the height difference it spans, so it
## is derived from the terrain rather than fixed:
##
## [codeblock]
##   width  >=  (natural - plateau) / MAX_GRADIENT
## [/codeblock]
##
## A constant blend width cannot work here, because the height it has to span varies
## from a few metres of rolling ground to a full mountain.
func _apply_airport(point: Vector2, natural: float) -> float:
	var distance := point.distance_to(airport_position)
	if distance <= airport_radius:
		# Flat plateau. Raised above sea level regardless of what is underneath, so
		# the runway is never partly submerged.
		return maxf(airport_elevation, SEA_LEVEL)
	if distance >= airport_radius + AIRPORT_BLEND_MAX:
		return natural

	# Rise from the plateau edge to natural ground, over a width that accommodates
	# whatever height difference is actually there.
	var difference := absf(natural - airport_elevation)
	var width := maxf(
		AIRPORT_BLEND_MIN,
		minf(difference / MAX_GRADIENT, AIRPORT_BLEND_MAX)
	)
	var t := (distance - airport_radius) / width
	# Smoothstep so the join has no derivative discontinuity at either end.
	return lerpf(airport_elevation, natural, smoothstep(0.0, 1.0, t))


## Narrowest the plateau blend may be, in metres.
##
## Below this the join looks like a constructed platform rather than terrain, even
## when the gradient is legal.
const AIRPORT_BLEND_MIN := 180.0

## Widest the plateau blend may be, in metres.
##
## A cap so that flattening the runway does not reshape a large part of the island.
## Where natural ground is higher than this allows, the blend is steepest allowed
## rather than wide enough to be gentle: the alternative is erasing the mountain.
const AIRPORT_BLEND_MAX := 900.0


## 1 well inland, 0 at sea, smoothly blended between. Also used to place props.
##
## The shore band sits near the outer edge of the radius, because the interior has
## to be fully land for the mountains to survive in it. At 0.42 and 0.62 the land
## ended at 483 m when the radius said 1150 m, so the real island was 42% of its
## intended size and every mountain was attenuated to nothing.
func _land_mask(point: Vector2) -> float:
	var offset := point - island_center
	# Domain warping: the coastline noise displaces the radius the falloff uses, which
	# breaks the island out of a circle without needing a different noise type. This
	# is what coastline_complexity controls.
	var warp := _coast_noise.get_noise_2d(offset.x, offset.y) * coastline_complexity
	var warped := offset.length() - warp * 260.0
	var normalized := warped / maxf(island_radius, 1.0)
	return 1.0 - smoothstep(SHORE_LOW, SHORE_HIGH, normalized)


## Shore fade band, as fractions of island_radius.
const SHORE_LOW := 0.86
const SHORE_HIGH := 1.06


## Gentle rolling ground, so flat areas are not dead level.
func _base_elevation(point: Vector2) -> float:
	var n := _base_noise.get_noise_2d(point.x, point.y) * 0.5 + 0.5
	return n * 58.0 + 6.0


## Mountain elevation in metres at a point.
##
## Built as a broad summit plateau above a linear skirt rather than a smooth
## falloff, because the shape of that curve is what decides whether the island is
## flyable.
##
## The alternatives were all tried and all produced unflyable terrain:
##
## - Squaring a linear falloff reaches full height only exactly at the focus, so the
##   flank either is too steep or the summit is too low.
## - Averaging the field to bound the gradient converges, but costs 17 evaluations
##   per sample. At 0.33 ms each that made one chunk take seconds.
## - Clamping samples toward their neighbours does not converge at all: a sample
##   with one neighbour high and one low has no satisfying value, so the error
##   propagates. Worst steps stayed between 40 and 250 m.
##
## So the gradient constraint is satisfied by construction. [constant SUMMIT_FALLOFF]
## and [member mountain_reach_fraction] are sized from `max_elevation` and
## [constant MAX_GRADIENT] rather than chosen by eye.
func _mountain_elevation(point: Vector2) -> float:
	var count := maxi(mountain_count, 1)
	var total := 0.0

	for index in count:
		var focus := _mountain_focus(index, count)
		var local := point - focus
		# Elongate each mass rather than making it round.
		local.y *= 1.3
		# Falloff from this mountain's own focus. Measuring from the island centre put
		# every summit at a falloff near 0.09, which made the whole range 20 m tall.
		var falloff := 1.0 - clampf(local.length() / mountain_reach(), 0.0, 1.0)
		if falloff <= 0.0:
			continue

		# Flat top, then a linear skirt down to nothing.
		#
		# The height change is bounded by construction rather than filtered: over the
		# skirt the shape falls from SUMMIT_FLOOT to 0 across
		# (1 - SUMMIT_FALLOFF) * reach, so the gradient is
		# SUMMIT_FLOOT * max_elevation / ((1 - SUMMIT_FALLOFF) * reach). The measured
		# worst step with the earlier curve was a gradient of 1.44 against a limit of
		# 1.10, because the plateau edge dropped away faster than the skirt.
		var shaped: float
		if falloff > SUMMIT_FALLOFF:
			var t := (falloff - SUMMIT_FALLOFF) / (1.0 - SUMMIT_FALLOFF)
			# Smoothstep on the skirt rather than linear: its zero derivative at the
			# plateau edge is what removes the step there.
			shaped = lerpf(SUMMIT_FLOOT, 0.0, smoothstep(0.0, 1.0, t))
		else:
			shaped = SUMMIT_FLOOT * smoothstep(0.0, 1.0, falloff / SUMMIT_FALLOFF)
		# Each massif samples the ridge field in its own frame, so its relief is
		# bounded by its own falloff.
		#
		# A single shared world-space ridge field looked equivalent and was not: the
		# ridge peaks where the noise crosses zero, which can be up to a full reach
		# outside the falloff of any focus. Those peaks escaped their falloff entirely,
		# so the island reached 779 m against a 650 m contract while the massifs at
		# their own foci measured 9 to 58 m. Sampling per massif ties the ridge to the
		# focus, so a summit is always inside the mountain that owns it.
		#
		# The frame is rotated per index so the massifs do not share crests.
		var angle := _ridge_rotation(index)
		var rotated := local.rotated(angle)
		var ridge := _ridge_value(rotated)
		# Softened below the plateau so overlapping massifs approach a single
		# mountain's contribution rather than stacking linearly.
		total += shaped * pow(ridge, RIDGE_SOFTENING)

	return _saturate(total) * max_elevation


## Rotation applied to a massif's ridge frame, in radians.
##
## Offset per index so neighbouring massifs do not sample the same part of the ridge
## field and end up with identical silhouettes.
func _ridge_rotation(index: int) -> float:
	return RIDGE_ROTATION_STEP * float(index)


## Exponent applied to the ridge value before summing massifs.
##
## Below 1, so a massif with a mediocre ridge still contributes meaningfully. This is
## what lets a mountain reach a useful fraction of [member max_elevation] without
## every one of them being a full-height peak.
const RIDGE_SOFTENING := 0.7

## Rotation between successive massifs' ridge frames, in radians.
##
## Large enough that two adjacent massifs sample visibly different parts of the
## ridge field, so the range does not read as one shape repeated four times.
const RIDGE_ROTATION_STEP := 1.7


## Radius over which a mountain falls from summit to nothing, in metres.
func mountain_reach() -> float:
	return island_radius * mountain_reach_fraction


## Compress a summed massif height into 0..1.
##
## Massifs overlap, so their contributions sum past what one mountain should reach,
## and a straight scale to [member max_elevation] produces peaks well above the
## design contract: measured 917 m against 650 m, where two massifs 184 m apart
## stacked.
##
## The reference is [method _saturation_ceiling] and nothing else. Two alternatives
## were both wrong:
##
## - Normalising against the sum of all four massifs bounds the total correctly but
##   leaves every *isolated* peak short, because one mountain only ever reaches
##   SUMMIT_FLOOT of a reference four times larger. Measured 472 m.
## - Normalising against a single massif, with no allowance for overlap, lets two
##   stacked massifs overshoot. Measured 917 m.
##
## So the reference sits between the two, and is derived from the actual separation
## of the foci rather than chosen. Overlap is what needs compressing, and overlap is
## a function of how close the massifs are.
##
## Saturating rather than clamping because min() is non-differentiable, and the point
## where the total crossed the cap was exactly where the terrain gradient spiked.
func _saturate(value: float) -> float:
	if _saturation_ceiling <= 0.0:
		return 0.0
	return (1.0 - exp(-SATURATION * value)) / (1.0 - exp(-SATURATION * _saturation_ceiling))


## Summed field value that maps to exactly [member max_elevation], computed once in
## [method configure].
##
## Cached rather than computed per sample: the foci do not move between samples, and
## walking them inside the height function made terrain generation unusably slow.
var _saturation_ceiling := 0.0


## Compute [_saturation_ceiling] from the current focus layout.
func _measure_saturation_ceiling() -> void:
	var count := maxi(mountain_count, 1)
	var overlap_limit := mountain_reach() * SATURATION_OVERLAP_SPAN
	var overlapping := 0
	for a in count:
		for b in range(a + 1, count):
			if _mountain_focus(a, count).distance_to(_mountain_focus(b, count)) < overlap_limit:
				overlapping += 1
	# Each overlapping pair adds headroom, capped by the count so a dense cluster
	# cannot inflate the ceiling without limit.
	var extra := minf(float(overlapping), float(count - 1))
	_saturation_ceiling = SUMMIT_FLOOT * (1.0 + extra * SATURATION_OVERLAP_GAIN)


## Multiple of the mountain reach within which two massifs count as overlapping.
const SATURATION_OVERLAP_SPAN := 1.4

## Ceiling headroom per overlapping pair.
##
## Below 1.0 because two massifs at full height is not a realistic maximum: at their
## closest, neither is at full falloff, since each focus is at distance from the
## other's peak.
const SATURATION_OVERLAP_GAIN := 0.7


## Curvature of the massif saturation. Higher means overlap compresses more gently.
##
## Low enough that a single isolated massif still reaches [member max_elevation].
## A steeper curve saturates faster, so an isolated mountain falls short of the
## design's elevation: at 4.0 a lone massif came out at 460 m against a 650 m
## contract, because a single mountain only ever reaches SUMMIT_FLOOT of the summed
## field and the exponential had already flattened that far out.
const SATURATION := 0.55


## Fraction of the falloff over which the summit holds its full height.
const SUMMIT_FALLOFF := 0.55
## Summit height relative to the mountain's maximum.
const SUMMIT_FLOOT := 0.82


## No airport exclusion radius exists, and adding one was a mistake worth recording.
##
## Suppressing mountains near the airport was tried three ways and each failed. A
## hard cutoff is a step in the height field, measured as a 316 m cliff. A fade
## spanning the mountain's own reach converges, but at this island's scale that band
## is wider than the island, so it faded out every peak and the range disappeared
## entirely. A fade narrower than the reach compressed each mountain into a 250 m
## step at the band edge.
##
## The layout solves this instead, by placing the foci clear of the airport in
## [_mountain_focus]. There is no reason to suppress a mountain that is not there.


## Ridge value at a world position, 0 to 1.
##
## Ridged noise, `1 - abs(noise)`, normalised against the field's measured peak.
## Simplex noise never reaches 1.0, so dividing by an assumed bound caps the
## mountains at well under the configured elevation.
func _ridge_value(point: Vector2) -> float:
	var raw := _ridge_noise.get_noise_2d(point.x, point.y)
	return pow(clampf(1.0 - absf(raw) / _ridge_peak, 0.0, 1.0), RIDGE_SHARPNESS)


## Where each mountain sits.
##
## Foci go on a ring at [member mountain_ring_fraction] of the island radius, which
## must sit inside the falloff reach or every summit is at a negligible falloff.
## Varied radii looked reasonable but produced nothing at all.
##
## Foci that would land on the airport are rotated around the ring until clear.
## Rotating rather than pushing outward matters: pushing outward moves a focus past
## the reach, which removes the mountain instead of relocating it.
func _mountain_focus(index: int, count: int) -> Vector2:
	var radius := island_radius * mountain_ring_fraction
	var base_angle := TAU * float(index) / float(maxi(count, 1))

	# Rejection sampling around the ring: walk angles in small steps and take the
	# first that clears the airport.
	#
	# A fixed list of offsets, or a single radial push, both fail badly. Offsets only
	# covered part of the circle and every focus fell back to the same last entry, so
	# all four mountains stacked on one point and the island lost its range. The
	# fallback below is the one that would run out of options.
	var steps := int(ceil(TAU / FOCUS_ANGLE_STEP))
	for step in steps:
		# Alternate sides of the base angle so the mountains spread either way.
		var offset := FOCUS_ANGLE_STEP * float(step) * (1.0 if step % 2 == 0 else -1.0)
		var angle := base_angle + offset
		# The ring is pushed outwards as the angle search advances. A fixed ring
		# cannot satisfy the airport clearance at all when the airport is off-centre:
		# the reachable arc is limited, and four foci all landing in it ends up with
		# them crowded into one massif. Growing the radius with the angle lets each
		# mountain find its own clear position on the far side of the island.
		var grown := minf(radius + float(step) * FOCUS_RADIUS_STEP, island_radius * 0.9)
		var focus := island_center + Vector2(cos(angle), sin(angle)) * grown
		if focus.distance_to(airport_position) >= airport_clearance:
			return focus

	# Nothing on the ring satisfies the clearance. Rather than collapse every focus
	# onto one point, place them evenly around the part of the ring that is furthest
	# from the airport, so the range stays four separate mountains.
	var away := (island_center - airport_position).normalized()
	var spread := TAU / float(maxi(count, 1))
	for step in count:
		var angle := away.angle() + spread * (float(step) - float(count - 1) * 0.5)
		var focus := island_center + Vector2(cos(angle), sin(angle)) * radius
		if focus.distance_to(airport_position) >= airport_clearance:
			return focus
	return island_center + away * radius


## Troughs along the carved valley lines.
##
## Each valley is a capsule: the perpendicular distance from the line running
## outward from the island centre sets the depth. A rounded profile with soft
## shoulders reads better than a crease.
func _valley_depth(point: Vector2) -> float:
	var depth := 0.0
	var offset := point - island_center
	for valley in _valleys:
		var direction := Vector2(cos(valley["angle"]), sin(valley["angle"]))
		var along := offset.dot(direction)
		var length: float = valley["length"]
		if along < 0.0 or along > length:
			continue
		var across := absf(offset.cross(direction))
		var width: float = valley["width"]
		if across >= width:
			continue
		var profile := 1.0 - smoothstep(0.0, 1.0, across / width)
		# Fade at both ends so the valley neither cuts a line in the sea nor starts
		# abruptly inland.
		var t := along / maxf(length, 1.0)
		var ends := smoothstep(0.0, 0.22, t) * (1.0 - smoothstep(0.72, 1.0, t))
		depth += profile * ends * float(valley["depth"])
	return depth


## Small-scale roughness, so the surface is not glassy at low polygon counts.
func _detail_elevation(point: Vector2) -> float:
	return _detail_noise.get_noise_2d(point.x, point.y) * 6.0


## Seabed relief below the waterline, shallowing toward the shore.
##
## Must reach exactly 0 where the land mask does, since the two meet at the
## shoreline. An earlier version started the seabed at 4 m depth while land faded to
## 0, which left a 4 m step across the waterline — measured as the largest
## discontinuity on the island, since the shoreline is the longest boundary there
## is. The relief is also faded out over the same interval, so the detail noise
## cannot reintroduce a step at the join.
func _seabed_depth(point: Vector2) -> float:
	var normalized := (point - island_center).length() / maxf(island_radius, 1.0)
	# How far past the shoreline this point is, 0 at the shore and 1 offshore.
	var offshore := clampf((normalized - SHORE_HIGH) / SEABED_FADE_SPAN, 0.0, 1.0)
	# The fade is squared as well as smoothstepped.
	#
	# The mask stops being positive at exactly SHORE_HIGH, so any dependence on
	# `offshore` that is not zero there leaves a step across the waterline: measured
	# as 2.5 m over 1 m, because smoothstep already has a zero derivative at its start
	# but the detail noise term did not, and the depth term's own slope was still
	# finite. Squaring guarantees both the value and the slope reach zero together.
	var faded := smoothstep(0.0, 1.0, offshore)
	faded *= faded
	var depth := lerpf(0.0, 85.0, faded)
	# Detail noise scaled by the same fade, so it cannot put height back at the join.
	depth += _detail_noise.get_noise_2d(point.x, point.y) * 9.0 * faded
	return -maxf(depth, 0.0)


## Distance past the shoreline, as a fraction of the island radius, over which the
## seabed reaches full depth.
const SEABED_FADE_SPAN := 0.6


## Steepness at a position, in metres per metre. Used to keep props off cliffs.
func slope_at(x: float, z: float, step := SLOPE_SAMPLE_STEP) -> float:
	var dx := height_at(x + step, z) - height_at(x - step, z)
	var dz := height_at(x, z + step) - height_at(x, z - step)
	return Vector2(dx, dz).length() / (2.0 * step)


## Unit surface normal, for orienting props to the ground.
func normal_at(x: float, z: float, step := SLOPE_SAMPLE_STEP) -> Vector3:
	var dx := height_at(x + step, z) - height_at(x - step, z)
	var dz := height_at(x, z + step) - height_at(x, z - step)
	return Vector3(-dx, 2.0 * step, -dz).normalized()


## Spacing used for slope and normal estimates, in metres. Large enough to smooth
## out the small-scale detail noise, which would otherwise make every sample look
## like a cliff.
const SLOPE_SAMPLE_STEP := 12.0


## 0 at the driest high ground, 1 in damp low ground. Drives biome colour and later
## vegetation placement.
func moisture_at(x: float, z: float) -> float:
	return moisture_at_height(x, z, height_at(x, z))


## Moisture with the height supplied by the caller.
##
## Separate from [method moisture_at] because the mesh builder colours every face and
## already knows each one's height; having it resampled the terrain for each face was
## a measurable cost during chunk generation.
func moisture_at_height(x: float, z: float, height: float) -> float:
	var n := _moisture_noise.get_noise_2d(x, z) * 0.5 + 0.5
	# Lower ground is wetter, which keeps vegetation down in the valleys.
	var height_factor := clampf(1.0 - height / 220.0, 0.0, 1.0)
	return clampf(n * 0.55 + height_factor * 0.45, 0.0, 1.0)


## True where the terrain is dry land above the waterline.
func is_land(x: float, z: float) -> bool:
	return height_at(x, z) > SEA_LEVEL