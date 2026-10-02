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
## [constant SHORE_LOW], so the usable interior is a fraction of it.
##
## ## Why the island is this size
##
## Island radius, mountain reach and mountain count are one budget, not three
## independent knobs. Two requirements meet:
##
## - A peak of [member max_elevation] needs a reach of about
##   `max_elevation * PI / (2 * MAX_GRADIENT)` to stay within the flight model's
##   climbable gradient, since the falloff curve's steepest slope is `PI/2` times its
##   average.
## - Four massifs of reach R need a mountain ring of at least 2R, or they merge into
##   one range instead of reading as separate mountains.
##
## Together those need a ring of about 1860 m, so the radius has to exceed that by
## enough to leave the airport flat ground on the far side. At 1500 m the ring could
## not hold the massifs: separation failed outright, the foci collapsed onto each
## other, and the peaks fell to 506 m against a 650 m contract.
##
## The design's 72% water coverage is what this trades against. A circular island
## covering 28% of a 5000 m square has a radius near 1500 m, so the island is now
## larger than the coverage figure implies and measures nearer 76% water. Coverage is
## a soft aesthetic target; four flyable, distinguishable 650 m peaks are the
## requirement the terrain actually has to meet.
@export var island_radius := 2000.0

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

## Radius of the ring the mountain foci sit on, in metres.
##
## Must exceed [method mountain_reach] or every summit sits outside its own massifs
## reach and produces nothing, and must be large enough for the foci to be
## [method minimum_focus_separation] apart: four foci evenly spaced on a ring of
## radius R are `R * sqrt(2)` apart, so the ring needs at least `separation * 2 / sqrt(2)`.
##
## Derived rather than set, because both bounds move when the reach, the count or the
## island size changes, and a value that ignores them produces either invisible
## mountains or a range collapsed into one massif.
func mountain_ring_radius() -> float:
	var separation := minimum_focus_separation()
	var by_count := separation * 2.0 / sqrt(2.0)
	var by_reach := mountain_reach() * RING_CLEARANCE
	# Never outside the island's land, however large the other bounds push.
	return minf(maxf(island_radius * mountain_ring_fraction, maxf(by_count, by_reach)),
		island_radius * 0.85)


## Margin between the mountain ring and the massif reach, as a multiple.
##
## Above 1 so the massifs stand inside the shoreline rather than being cut by it.
const RING_CLEARANCE := 1.05


## Nominal ring position, as a fraction of the island radius. A floor for
## [method mountain_ring_radius], not the answer on its own.
@export_range(0.2, 0.9, 0.01) var mountain_ring_fraction := 0.6

## Angle step used when searching the ring for a clear position, in radians.
const FOCUS_ANGLE_STEP := 0.06

## Outward growth of the search ring per angle step, in metres.
const FOCUS_RADIUS_STEP := 12.0

## Radius over which a mountain falls from summit to nothing, as a fraction of the
## island radius.
##
## Radius over which a mountain falls from summit to nothing, as a fraction of the
## island radius.
##
## Sized for the massifs to be distinct rather than one continuous range.
##
## This was originally 1.0, the same as the island radius, and that made every
## mountain cover the whole island: their contributions summed everywhere, most of
## the land sat above 50 m, and there was nowhere flat to put a runway.
##
## Sized from [member max_elevation] and [constant MAX_GRADIENT] rather than chosen by
## eye. The falloff is a quarter sine, so its steepest slope is `PI/2` times the
## average, and the average is the relief divided by the reach. Requiring that
## steepest slope to be climbable gives:
##
## [codeblock]
##   reach >= max_elevation * PI / (2 * MAX_GRADIENT)
##         = 650 * PI / (2 * 1.1)  =  928 m
## [/codeblock]
##
## 0.46 of a 2000 m radius is 920 m, that value to within a percent. A fraction rather
## than an absolute distance so the relationship survives a change to either the
## elevation or the island size, both of which the design file owns.
@export_range(0.1, 1.0, 0.01) var mountain_reach_fraction := 0.46

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

## Where the coastal lighthouse stands, from design/world_design.json's landmarks.
##
## An export like the airport fields above rather than a read of the JSON at runtime:
## the design file is a specification, and this is the same pattern the rest of the
## world contract already follows here.
@export var lighthouse_position := Vector2(1400.0, -700.0)

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
## Octaves of ridge noise.
##
## Few, because this is the dominant source of steepness on the island rather than
## the falloff. The ridge scales to the full [member max_elevation], so its own
## gradient is multiplied by 650 m: three octaves have a finest wavelength of 595 m
## and a measured gradient of 0.0048 per m, which is 3.1 m of height per metre of
## ground on its own. Two octaves roughly halves that.
const RIDGE_OCTAVES := 2


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


## Peak derivative of a smoothstep, relative to its average slope.
##
## A blend of height `h` over width `w` has an average gradient of `h / w`, but a
## smoothstep's steepest point is 1.5 times that. Every blend width in this file is
## therefore divided by this factor, not by [constant MAX_GRADIENT] alone: without it
## the blend meets its gradient budget on average and exceeds it in the middle, which
## is where the measured steepest points always were.
const SMOOTHSTEP_PEAK_SLOPE := 1.5


## Width a blend needs to change height by `difference` without exceeding
## [constant MAX_GRADIENT], accounting for the smoothstep's peak slope.
func _blend_width(difference: float, cap: float) -> float:
	var required := absf(difference) * SMOOTHSTEP_PEAK_SLOPE / MAX_GRADIENT
	return clampf(required, AIRPORT_BLEND_MIN, cap)


## Height above sea level at a point.
##
## Composed in three steps: build the land, sink it into the sea across the shore,
## then flatten the airport into the result. The order matters — the plateau has to
## be able to raise ground the shoreline would otherwise have claimed, because the
## design's runway reaches 350 m from the plateau centre and that is close enough to
## the coast for the shore band to have taken it.
func _height(point: Vector2) -> float:
	return _apply_airport(point, _land_and_sea(point))


## Land relief at a point, before the shoreline is applied.
func _land_relief(point: Vector2) -> float:
	return _base_elevation(point) \
		+ _mountain_elevation(point) \
		+ _detail_elevation(point) \
		- _valley_depth(point)


## Land, sunk into the sea across the shoreline.
##
## ## Why the shoreline is a blend and not a multiplier
##
## The obvious composition multiplies every layer by a land mask:
##
## [codeblock]
##   height = (base + mountain + detail) * mask
## [/codeblock]
##
## That is wrong here, and wrong in a way that produced the steepest terrain on the
## island. The mask has a fixed width, so it has to swallow whatever relief happens to
## be at the shore — and a 650 m massif reaching the coast means the whole mountain
## is compressed into that fixed band. Measured 5.2 m per m, against a limit of 2.
##
## The band cannot simply be widened, because its width is also what sets how much of
## the island is land, and the design fixes a water coverage. So the width is derived
## from the relief it has to span, the same way the airport's blend is. Where the
## coast meets low ground the band is narrow and the beach is a beach; where it meets
## a massif the band opens out and the mountain runs into the sea as a slope.
func _land_and_sea(point: Vector2) -> float:
	var land := _land_relief(point)
	# Width needed to take the local relief down to sea level at a legal gradient.
	var width := _blend_width(maxf(land, 0.0), island_radius * SHORE_MAX_WIDTH)
	# Progress along that band, 0 at the waterline and 1 where the blend is complete.
	var t := clampf(_offshore(point) * island_radius * 0.2 / maxf(width, 1.0), 0.0, 1.0)
	# No early return at either end.
	#
	# Returning the seabed once the band is complete looks equivalent and is not: a
	# point can sit a hair inside the band and its neighbour a hair outside, and the
	# discontinuity between them is the full height difference. Measured as a 166 m
	# step, at a point where a 473 m landmass was at 99.94% of the band.
	return lerpf(land, _seabed_depth(point), smoothstep(0.0, 1.0, t))


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
	var width := _blend_width(natural - airport_elevation, AIRPORT_BLEND_MAX)
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


## How far past the shoreline a point is: 0 at the water's edge, 1 well offshore.
##
## Used by [method _land_and_sea] to blend the island into the sea, and by
## [method _seabed_depth] to deepen it.
##
## The domain warp is what coastline_complexity controls: the coastline noise
## displaces the radius the falloff uses, which breaks the island out of a circle
## without needing a different noise type.
func _offshore(point: Vector2) -> float:
	var offset := point - island_center
	var warp := _coast_noise.get_noise_2d(offset.x, offset.y) * coastline_complexity
	var warped := offset.length() - warp * COAST_WARP_SCALE
	return (warped - SHORE_LOW * island_radius) / maxf(island_radius * 0.2, 1.0)


## 1 well inland, 0 at the waterline. Also used to place props.
func _land_mask(point: Vector2) -> float:
	return 1.0 - smoothstep(0.0, 1.0, clampf(_offshore(point), 0.0, 1.0))


## Distance the coastline noise may displace the shoreline by, in metres.
const COAST_WARP_SCALE := 260.0

## Normalised distance at which the shoreline falls, as a fraction of the radius.
##
## Near the outer edge, because the interior has to be fully land for the mountains
## to survive in it. At 0.42 the land ended at 42% of the radius it claimed, so the
## real island was under half its intended size and every massif was attenuated to
## nothing.
const SHORE_LOW := 0.86

## Widest the shore blend may open, as a fraction of the island radius.
##
## A cap on how far a tall massif can push the coastline seaward. It has to be large
## enough to take the island's full relief down to the waterline at an acceptable
## gradient: a 650 m peak at [constant MAX_GRADIENT] needs 590 m of shore, which is
## 0.3 of a 2000 m radius on its own. At 0.35 the cap was binding on the tallest
## massifs and compressing the remainder into a 166 m step.
const SHORE_MAX_WIDTH := 0.45


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
## So the gradient constraint is satisfied by construction. [constant SUMMIT_CURVE]
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

		# The falloff curve, which decides the mountain's gradient.
		#
		# ## Why the shape, not a wider reach
		#
		# The island is one budget: four massifs of reach R need a ring of at least 2R,
		# so the reach cannot grow much without the foci colliding. Climbability has to
		# come from the curve.
		#
		# `sin(falloff * PI/2)` runs from 0 at the summit to 1 at the edge of the reach,
		# and has zero derivative at both. That matters twice: at the summit the
		# gradient passes through zero rather than reversing abruptly, and at the skirt
		# the mountain meets the ground flat rather than arriving at an angle. The
		# earlier piecewise linear-then-smoothstep shape had a corner at the plateau
		# edge, and its measured flank gradient was 2.3 m per m against the flight
		# model's 1.1 — a 600 m wall the aircraft could neither climb nor land on.
		#
		## Note the direction. `falloff` is 1 at the summit and 0 at the edge, so the
		## sine rises from 0 at the focus to 1 at the full reach. Using `cos` here
		## instead inverts the mountain into a crater, which an earlier version did and
		## which the cliff check caught as a 646 m step.
		var shaped := pow(sin(clampf(falloff, 0.0, 1.0) * PI * 0.5), SUMMIT_CURVE)

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
##   one mountain's worth of a reference four times larger. Measured 472 m.
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
	_saturation_ceiling = 1.0 + extra * SATURATION_OVERLAP_GAIN


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
## contract, because a single mountain only ever reaches 1.0 of the summed
## field and the exponential had already flattened that far out.
const SATURATION := 0.55


## Exponent applied to the sine falloff that shapes each massif.
##
## Below 1 flattens the summit and steepens the skirt; above 1 does the reverse. Kept
## at 1 so the shape is a quarter sine, whose steepest gradient is `PI/2` times the
## average — the gentlest a curve of this family can be while still rising from zero
## at the focus and reaching zero at the full reach.
const SUMMIT_CURVE := 1.0


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
## Two constraints, and the layout is whatever satisfies both:
##
## 1. Every focus must be at least [method required_airport_clearance] from the
##    airport, measured to the massif's edge rather than its focus.
## 2. Foci must be far enough apart that their massifs read as separate mountains.
##
## The second was missing at first, and the island was worse for it. Searching
## outward for the first angle that clears the airport ignores where the other foci
## already are, so four mountains ended up crowded into the same part of the ring,
## 728 m apart with a 450 m reach. Their contributions summed and saturated into a
## shared plateau, and two of the four stood only 39 m and 62 m above the
## surrounding ground — hills, not the 650 m peaks the design asks for.
##
## So the search now also requires separation from the foci already placed, and
## spreads the search over a wider arc rather than taking the first acceptable
## angle. Taking the *first* acceptable position is the mistake: it is locally
## valid and globally crowded.
func _mountain_focus(index: int, count: int) -> Vector2:
	var radius := mountain_ring_radius()
	var base_angle := TAU * float(index) / float(maxi(count, 1))

	# The ring grows as the search advances, so a focus that cannot clear the airport
	# at the inner radius can still find a position further out. A fixed ring cannot
	# satisfy the clearance at all when the airport is off-centre.
	var steps := int(ceil(TAU / FOCUS_ANGLE_STEP))
	for step in steps:
		# Alternate sides of the base angle so the mountains spread either way.
		var offset := FOCUS_ANGLE_STEP * float(step) * (1.0 if step % 2 == 0 else -1.0)
		var angle := base_angle + offset
		var grown := minf(radius + float(step) * FOCUS_RADIUS_STEP, island_radius * 0.9)
		var focus := island_center + Vector2(cos(angle), sin(angle)) * grown
		if not _focus_is_clear(focus, index, count):
			continue
		return focus

	# Nothing on the ring satisfies both constraints. Rather than collapse every focus
	# onto one point, place them evenly around the part of the ring that is furthest
	# from the airport, so the range stays four separate mountains.
	var away := (island_center - airport_position).normalized()
	var spread := TAU / float(maxi(count, 1))
	for step in count:
		var angle := away.angle() + spread * (float(step) - float(count - 1) * 0.5)
		var focus := island_center + Vector2(cos(angle), sin(angle)) * radius
		if _focus_is_clear(focus, index, count):
			return focus
	return island_center + away * radius


## Whether a candidate focus is usable: clear of the airport, and far enough from the
## foci already placed that its massif will read as its own mountain.
func _focus_is_clear(candidate: Vector2, index: int, count: int) -> bool:
	if candidate.distance_to(airport_position) < airport_clearance:
		return false
	for other in count:
		# Only consider foci placed before this one, so the search is deterministic
		# rather than order-dependent.
		if other >= index:
			break
		if candidate.distance_to(_mountain_focus(other, count)) < minimum_focus_separation():
			return false
	return true


## Minimum distance between two mountain foci, in metres.
##
## Set from the reach rather than chosen: two massifs closer than this overlap enough
## that their contributions merge into one broad rise instead of reading as separate
## mountains. A factor rather than an absolute distance, because the reach is what
## determines overlap and it is tunable.
## Minimum distance between two mountain foci, as a multiple of the reach.
##
## Below 2 so that four massifs fit on the ring with the airport's exclusion arc
## still available. Four foci need three gaps of this size, plus clearance on both
## sides of the arc the airport forbids, and at 2.1 that exceeded the circle
## entirely: foci 0 and 3 landed 773 m apart with a 920 m reach and the separation
## check failed.
##
## At 1.5 the massifs partially overlap, which is what real ranges do. The overlap is
## handled by the saturation in [method _saturate] rather than by separating them, so
## a merged pair forms one broader rise instead of two peaks on a shared base.
@export_range(1.0, 4.0, 0.05) var focus_separation_factor := 1.5


func minimum_focus_separation() -> float:
	return mountain_reach() * focus_separation_factor


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


## Seabed relief below the waterline, deepening away from the shore.
##
## Reaches exactly 0 where the shore blend starts, since the two meet at the
## waterline, and so does its derivative. That matters: an earlier version faded the
## depth in with a smoothstep alone, which has zero value but not zero slope at its
## start, and left a 2.5 m step across the waterline — the largest discontinuity on
## the island, because the shoreline is the longest boundary there is. Squaring the
## fade makes the value and the slope reach zero together.
func _seabed_depth(point: Vector2) -> float:
	# Squared as well as smoothstepped, so both value and slope are zero at the shore.
	var faded := smoothstep(0.0, 1.0, clampf(_offshore(point), 0.0, 1.0))
	faded *= faded
	var depth := lerpf(0.0, SEABED_MAX_DEPTH, faded)
	# Detail noise scaled by the same fade, so it cannot put height back at the join.
	depth += _detail_noise.get_noise_2d(point.x, point.y) * 9.0 * faded
	return -maxf(depth, 0.0)


## Depth of the seabed well offshore, in metres.
const SEABED_MAX_DEPTH := 85.0


## Distance past the shoreline, as a fraction of the island radius, over which the
## seabed reaches full depth.


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