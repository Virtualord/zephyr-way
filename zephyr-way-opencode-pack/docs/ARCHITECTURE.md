# Architecture

Zephyr Way is a Godot 4.7.x project. This document explains how the code is
organised and, more importantly, why the boundaries are where they are.

Read `AGENTS.md` first for the technology contract. This file covers structure.

## Layering

The rule is that data flows one way, downwards. A layer may read from layers
above it, never the reverse.

```
  scenes/         .tscn composition: which nodes exist, where they sit
    |
  scripts/ui/     presentation, reads state via signals
  scripts/world/
    |
  scripts/aircraft/aircraft_controller.gd    the seam
    |
  scripts/aircraft/flight_model.gd           pure maths, no nodes
    |
  scripts/utilities/                          no knowledge of the game
```

`FlightModel` sits at the bottom because it is the only part that must be
independently testable. It extends `RefCounted`, touches no nodes, and can be
stepped at a fixed delta inside a test with no scene tree. That property is what
makes 34 flight assertions cheap to run, and it is why the flight model never
reads `Input`, never touches a node, and never calls `queue_redraw`.

`AircraftController` is the seam. It owns the transform, owns the model, and is
the only place the two meet.

## Aircraft

Five scripts, one responsibility each. This split is not ceremony: each has a
different reason to change.

| Script | Owns | Changes when |
| --- | --- | --- |
| `flight_command.gd` | Pilot input for one tick | Input mapping changes |
| `flight_input.gd` | InputMap to `FlightCommand` | Controls are rebound |
| `flight_model.gd` | Forces and integration | Flight *feel* is tuned |
| `flight_state.gd` | Telemetry snapshot | New telemetry is added |
| `aircraft_visuals.gd` | Propeller, control surfaces | The airframe's look changes |
| `aircraft_builder.gd` | Geometry generation | The airframe's *shape* changes |
| `chase_camera.gd` | Camera placement | Camera feel is tuned |
| `aircraft_tuning.gd` | Numbers (Resource) | Flight *feel* is tuned |

The distinction that matters: `FlightModel` and `FlightTuning` are about feel and
change together, while `AircraftBuilder` is about silhouette and changes when the
design files say the aircraft is a different shape.

### Why tuning is a Resource

`FlightTuning` and `AircraftProfile` are Resources rather than constants so they
can be edited live in the inspector, shared between aircraft, and saved as
`.tres` files. They also document themselves: every field has a comment saying
what it does and what depends on it.

Derived values keep the numbers self-consistent, so editing one number cannot
silently contradict another:

```
lift_gain          = gravity / cruise_speed^2        -> 1 g lift in level cruise
drag_coefficient   = gravity / (L:D * cruise^2)      -> draggy but turnable
max_speed          = where remaining thrust = drag  -> actual top speed
```

### The flight model is anchored on physics, not on feel

The one rule that governs `flight_model.gd`: **every force is expressible against
gravity**, because the aircraft's mass is unknown and unnecessary. Lift, drag and
thrust are all in m/s², and the model compares them to gravity rather than to a
weight.

That makes two derivations possible, and both are load-bearing:

- **Lift** is calibrated so that at cruise speed, at the reference angle of
  attack, it produces exactly gravity. Lift then scales with `v²` *and* with angle
  of attack.
- **Drag** is derived from a lift-to-drag ratio (9:1, a plausible value for a
  light sport aircraft) rather than from the thrust budget.

The drag derivation matters more than it looks. Sizing drag so that it "consumes
all the thrust at max speed" is intuitive and wrong: it forces drag above lift at
cruise, and because drag opposes the velocity vector it then cancels the lateral
component of lift in a banked turn. The aircraft cannot turn at all.

Three properties depend on lift scaling with angle of attack rather than airspeed
alone:

1. A climb settles instead of running away. Lift that only depends on airspeed
   cannot be shed by the pilot, so above cruise speed the wing pulls more than
   weight continuously, and the only way to reduce lift is to descend — which
   raises airspeed and increases lift again.
2. Stall is an angle, not a speed. A wing stalls because of the angle it is
   flown at; an aircraft descending normally at low speed must not lose lift.
3. Level hands-off flight is achievable, because trim is referenced to cruise
   where lift and gravity balance.

### Deliberate simplifications

Notably absent, because `AGENTS.md` asks for arcade flight rather than a
simulator:

- **No lateral (sideforce) force.** The aircraft banks rather than sideslipping.
  This is why weathervane alignment has to be strong: it is doing the work a real
  fin and fuselage would.
- **No propeller torque, P-factor or slipstream.**
- **No sideslip drag.** Turning is free of the extra drag a real slipping wing
  produces.
- **Rate-commanded controls with a restoring term**, not a control surface model.
- **Thrust follows a simple falloff curve** rather than a propeller efficiency map.

The consequence worth knowing: turn rates land within about 10% of
`g·tan(bank)/V` rather than exactly on it, and the difference is the deliberate
auto-level assist.

### Scene tree

```
Aircraft                         Node3D, origin at the centre of gravity
  FlightController               Node3D, runs the simulation
    FlightInput                  Node, reads InputMap
    Visuals                      Node3D, builds and animates the airframe
      Airframe
        Body, Nose, WingLeft, WingRight, Tail, Propeller, GearLeft, ...
```

`FlightController` is a child of `Aircraft` rather than being `Aircraft`, so the
scene root stays a plain `Node3D` that other systems can point at. `ChaseCamera`
accepts either as its target.

## Procedural art

There is no modelling step. `MeshBuilder` provides the vocabulary — boxes,
tapers, cones, and a cross-section `loft` — and `AircraftBuilder` composes those
into an airframe from `AircraftProfile` values.

Two decisions in `MeshBuilder` are load-bearing:

**Normals are assigned per triangle, not generated.** `SurfaceTool.generate_normals()`
groups coincident vertices, so a box's three faces meeting at a corner average
into one wrong normal and the faceted look collapses into a smooth blob. Setting
the face normal on each vertex as it is added guarantees flat shading and costs
nothing.

**Faces are wound counter-clockwise seen from outside.** Getting this wrong makes
faces invisible under backface culling, which reads as missing geometry rather
than as a shading bug. This was found by the `procedural_test.gd` normals check.

`loft()` sweeps along either Z or X. Fuselages and fins sweep along Z (length);
wings and tail panels sweep along X (span). The `Axis` parameter is what lets one
function serve both.

## World

The world is a scene that exposes one function:

```gdscript
func ground_height_at(position: Vector3) -> float:
```

`AircraftController` samples this through a `Callable`, and that is the entire
contract between the world and the flight model. Milestone 1's `TestEnvironment`
implemented it as a flat plane at zero; milestone 3's `Island` implements it as
generated terrain. The flight model was not changed to accommodate the terrain,
which is the point of the boundary.

`Island` is three parts, split because they change for different reasons:

| Part | Role |
| --- | --- |
| `TerrainGenerator` | The height and biome function. Pure maths, no nodes. |
| `TerrainBuilder` | Turns the function into chunked, flat-shaded, vertex-coloured meshes. |
| `IslandAtmosphere` | Sun, sky and fog. Separate because it has nothing to do with terrain. |

### The terrain is a function, not mesh data

`TerrainGenerator.height_at()` is the single source of truth. The mesh is built from
it and the aircraft samples it, so the visible surface and the landing surface cannot
disagree. Sampling height at an arbitrary point is also what makes terrain
interactive — the aircraft needs it every physics tick — and it makes generation
deterministic, so neighbouring chunks agree on shared vertices with no seam handling.

### Two properties the terrain must have, and why

**No discontinuities.** The aircraft is clamped to the ground surface, so what it
cannot survive is the terrain height *jumping* between adjacent samples — a wall,
which it passes through. A steep slope is a different thing: the aircraft follows it,
it simply cannot climb it, and in an exploration game flying around a mountain is the
intended behaviour rather than a defect. `terrain_test.gd` allows 8 m of rise per
metre of ground, against a measured worst of 5.03. A wall is hundreds of metres over
a single sample; the defects that check was written for measured 42 m, 250 m, 316 m
and 646 m.

A relative version of this check was tried and rejected: dividing the second
difference by the local relief seems more robust, but a pure step and a rounded summit
both score 1.0 under it — the step because its relief is also one step, the summit
because the slope reverses. It would have accepted a 300 m wall.

Climbability is a separate and much stricter property, asserted only around the
airport, which the aircraft has to take off from and land on.

**Steepness is a shaping decision, not a filter.** Attempts to bound the gradient
after the fact all failed:

- Clamping each sample toward its neighbours does not converge. A sample with one
  neighbour far above and one far below has no value satisfying both constraints, so
  the rule degenerates and the error propagates. Worst steps stayed between 40 m and
  250 m no matter how the rule was refined.
- Averaging over a disc converges, but costs 17 terrain evaluations per sample. At
  0.33 ms each that made a single chunk take seconds.

So the terrain is shaped to be what it is, at one evaluation per sample. The falloff
is a quarter sine, chosen because its derivative is zero at both the summit and the
ground: the mountain meets the sea flat rather than arriving at an angle. Its
exponent is 1, the gentlest a curve of that family can be while still rising from
zero at the focus and returning to zero at the full reach.

### Island size, mountain reach and mountain count are one budget

Not three independent knobs. Two requirements meet:

- A peak of `max_elevation` needs a reach of about `max_elevation * PI / (2 *
  MAX_GRADIENT)`, because the sine's steepest slope is `PI/2` times its average.
- Four massifs of reach R need a ring of at least 2R, or they merge into one range.

Both bounds are derived in code rather than set by hand, so retuning the elevation or
the island size moves them together. The ring radius in particular is
`max(nominal, count_bound, reach_bound)`, and ignoring the count bound is what made
all four massifs collapse onto one point at an earlier radius.

The budget is what forces the island to 2000 m, and that is a deliberate departure
from `design/world_design.json`, which asks for 72% water coverage. A circular island
covering 28% of a 5000 m square has a radius near 1500 m; at that radius the massifs
collided and the peaks fell to 506 m. Water coverage is an aesthetic target, and four
distinct 650 m peaks the aircraft can fly around are what the island actually has to
be. Measured water is 56%. `terrain_test.gd` prints the departure on every run rather
than quietly accepting it.

### The airport had to shape the island, not the other way round

The design fixes the airport at (-850, 420) and the peaks at 650 m. Getting both onto
one island took several rounds, and the constraint that decided the layout is:

```
airport_clearance >= mountain_reach + airport_radius + blend + margin
```

That is a distance to a mountain's *focus*, but a massif extends a full reach beyond
its focus, so the clearance that matters is measured to the massif's *edge*. Confusing
the two put summits 806 m from the runway centre, well inside the 1130 m the approach
needs, and the plateau blend had to span a mountain flank. `required_airport_clearance()`
derives it, because the reach and the plateau radius are both tunable and the
relationship between them is the real invariant.

Four more failures are worth recording, because all four looked like reasonable ideas:

- **Suppressing mountains near the airport** does not work in any form. A hard cutoff
  is a step in the height field, measured as a 316 m cliff. A smooth fade has to span
  the mountain's whole reach, which at this island's scale is wider than the island,
  so it faded out every peak. The layout solves this by relocating the foci instead.
- **One shared world-space ridge field** lets ridge crests fall outside every focus's
  falloff, so the relief escapes its own mountain: the island reached 779 m against a
  650 m contract while the massifs at their own foci measured 9 m. Each massif now
  samples the ridge in its own rotated frame.
- **Multiplying every terrain layer by a land mask** compresses whatever relief is at
  the coast into a band of fixed width. A 650 m massif reaching the shore is squeezed
  into it, measured as 5.2 m per m. The band cannot simply be widened — its width is
  also what sets the water coverage — so the shoreline is now a blend whose width is
  derived from the relief it has to span, exactly like the airport's.
- **Taking the first acceptable position when placing a mountain** is locally valid
  and globally crowded. Searching outward for the first angle clear of the airport
  ignores where the other foci already are, so four massifs ended up 728 m apart with
  a 450 m reach, summing and saturating into a shared plateau. Two of the four stood
  39 m and 62 m above the surrounding ground: hills, not the 650 m peaks the design
  asks for. The search now also requires separation from the foci already placed.

`terrain_test.gd` checks each massif's **prominence** — its summit height above the
lowest saddle leading to open ground — because the obvious check missed this entirely.
"summit minus the ground 900 m away" reported two massifs as barely hills, but that
ring lands inside the *neighbouring* massif at this island's scale, so it measures a
peak against the next one's shoulder. Prominence is also what a pilot actually sees.

## Conventions

- **Godot's -Z is forward.** Every heading calculation, camera offset and mesh
  builder assumes this. `Units.forward_of()` is the single accessor.
- **Headings are degrees, 0 = north (-Z), 90 = east (+X), clockwise from above.**
  `Units.heading_of()` and `Units.format_heading()` own this convention.
- **Metres and seconds internally.** Knots appear only at the display boundary,
  because the design files specify speeds in knots.
- **`.tres` files only carry data.** `AircraftProfile`, `FlightTuning` and their
  defaults carry no logic.
- **Scripts are `snake_case.gd`, classes are `PascalCase`.** Files with a
  `class_name` are referenced by that name, never by path.

## Input map

`project.godot`'s `[input]` section is generated by
`scripts/core/generate_input_map.py` rather than hand-written, because Godot's
serialized `InputEventKey` form is verbose and easy to get wrong, and an action
may only be defined once.

```bash
python3 scripts/core/generate_input_map.py
```

`FlightInput` skips unknown actions silently so a stripped export still runs,
which means a typo would otherwise be invisible. `tests/input_map_test.gd` exists
specifically to catch that.

## Testing

```bash
./scripts/run_tests.sh     # suites only
./scripts/verify.sh        # whitespace, JSON, project validation, suites
```

| Suite | Checks | Covers |
| --- | --- | --- |
| `procedural_test.gd` | 118 | Palette contract, mesh geometry, flat shading, airframe proportions |
| `input_map_test.gd` | 30 | Every action FlightInput reads exists and is wired |
| `flight_model_test.gd` | 34 | Forces, stall, ground contact, heading convention |
| `flight_regression_test.gd` | 43 | Specific flight-feel defects that were found and fixed |
| `terrain_test.gd` | 69 | Design contract, massif prominence, continuity, airport, chunk/function agreement |
| `recorder_test.gd` | 19 | Replay determinism, recording budget |
| `scene_test.gd` | 40 | Scenes load, wire to the island, and simulate without errors |

Suites run as separate Godot processes because each one quits the engine itself.

The flight assertions are deliberately loose. They guard against regressions like
inverted lift or a stall that never fires, not against specific handling numbers,
which are a design decision rather than a bug. A test that fails when the game
feels different is a test that will get deleted.

The terrain assertions are not loose, because the design contract states numbers:
5000 m world, 650 m peaks, 72% water, 4 mountains, an airport at a fixed coordinate.
Those are checked by measuring the generated island rather than by reading back the
fields that were configured, since a field can hold the right value while the
generator ignores it — which is exactly what happened several times here. The one
contract value not met is the water coverage, and the test reports the gap on every
run instead of quietly relaxing to accept it.

`scene_test.gd` asserts the world wiring directly, including that the aircraft's
ground sampler really reads the island. That check exists because when the island was
first added, `Main` never resolved the world: the aircraft spawned at the origin,
assumed flat ground, and flew over nothing. Nothing errored. Wiring bugs in a scene
file are invisible to every other suite, so they are asserted where the scene is.

`flight_analysis.gd` is deliberately outside this list: it asserts almost nothing
and simply measures. Run it before and after a tuning change to compare envelopes.

### Why `flight_regression_test.gd` exists

Milestone 1's tests all passed while the aircraft could not take off. The tests
were correct and the code was wrong: they asserted the aircraft *stayed put* on
the ground, and it did — because the ground branch updated velocity without ever
integrating position, so it built speed without travelling.

`flight_regression_test.gd` is the answer to that class of gap. Each test names a
defect that actually occurred, and asserts against **physics** rather than
remembered numbers:

- A 45° bank must turn at `g·tan(bank)/V` within 20%.
- Hands-off flight must hold altitude for 30 s at three throttle settings.
- The brakes must stop the aircraft from 30 m/s.
- Stall must begin near the configured angle of attack.
- Reported turn rate must match the actual heading change.

Physics-derived assertions survive retuning. Asserting "turn rate is 9.9 deg/s"
would not.

## Adding things

Practical notes on where new code tends to go.

**A new world feature** (ocean, airport, props) becomes a sibling scene under
`scenes/world/` with its own script, instanced into `Main.tscn` beside `Island`. It
should not modify the flight model. Anything that adds height to the world goes into
`TerrainGenerator`, not into a mesh, or the aircraft will land somewhere other than
where the ground appears.

**A new aircraft** needs a new `AircraftProfile` `.tres` and nothing else. If it
needs different behaviour rather than different shape, add a field to the profile
before adding a subclass.

**A new telemetry value** is added to `FlightState`, set in
`FlightModel._step_in_air` or `_step_on_ground`, and refreshed in
`FlightState.refresh()`. The HUD milestone will read it from there; no gameplay
change is needed to display it.

**Retuning flight feel** means editing `FlightTuning`, then running
`flight_analysis.gd` before and after to see what moved. Change one thing at a
time; several parameters interact (pitch stability and trim interact, as do
velocity alignment and roll rate). If a change breaks a physics-derived assertion
in `flight_regression_test.gd`, the change is wrong, not the test.

**A new input action** goes in `scripts/core/generate_input_map.py`, then re-run
that script. Do not hand-edit `project.godot`.

**World terrain** lives in `TerrainGenerator`. Keep `ground_height_at()`'s signature
stable; the flight model depends on it.

**Retuning terrain** means editing the exported fields on `TerrainGenerator` and
running `terrain_test.gd`. The design-contract assertions there are the measure, and
they are the reason several of those fields exist at their current values: a comment
on a number is a claim, a test is evidence.

## What is deliberately absent

Milestone 3 is a playable island, not a game. These are absent on purpose, per the
milestone prompts: ocean shading, airport, runway, props, villages, missions, HUD,
menus, audio, save state, day/night.

There are also no autoloads. Every service so far is scene-local, and per
`AGENTS.md` autoloads are for genuinely global state — which does not exist yet.
`[autoload]` in `project.godot` is empty and should stay that way until something
genuinely needs to outlive a scene.

The sea is a flat translucent plane rather than a stylized ocean, and
`IslandAtmosphere`'s fog is a depth fog tuned by eye. Both are milestone 4's work;
they are here so the coastline reads as a coastline rather than the edge of a
plateau.

Nothing renders a HUD yet, which means flight data is currently only observable
by reading `FlightState` in the debugger. That is the main reason to expect the
milestone 7 prompt to be worth its cost: flying without instruments is hard to
judge, and `tests/flight_recorder.gd` exists partly to compensate.

## Milestone 04 — ocean and atmosphere

### The ocean reads the seabed it is drawn on

`shaders/ocean.gdshader` takes its depth from a height field that `Island._height_field`
rasterises once at startup from the same `TerrainGenerator` the terrain mesh is built
from. So the shallows and the foam line follow the real seabed, and they cannot drift
out of step with it the way a hand-tuned depth curve would.

The field is deliberately sized to the island (`height_field_extent = 6000 m`) rather
than to the sea plane. At the sea's full width a 256-texel field is coarser than the
shoreline the foam is drawn along, and the shallows arrive as blocky rectangles instead
of a coastline. Past the field the shader clamps rather than special-casing the water
as abyss-deep: the height field is an analytic function and returns a uniform ~85 m of
water offshore, so a branch there painted deep water just outside the field and
ordinary deep water just inside it, drawing a hard square seam across the ocean at
exactly the field's extent.

Cost is a handful of `sin()` calls and one texture read per fragment on a single quad.
No refraction, no screen-space reflection, no normal map.

### The water is partly emissive, and that is the point

`self_light` keeps a fraction of the water's colour independent of the sun. Dimming the
sun to stop the rock washing out (below) dims the water by the same factor, and a sea
that darkens with the sun stops reading as sea. The sun sheen on top still carries the
lighting, so the water is not flat — it just has a floor under its value.

### Lighting was set by measurement, because the mesh was not at fault

The mountains rendered near-white while the palette calls for a mid grey-blue
(`rock.dark` lerped toward `rock.cool_grey` = `#575a6e`). Reading the chunk vertex
colours straight out of the mesh buffers (`tests/diagnose_terrain_colours.gd`) showed
the mesh was carrying exactly that colour, so no amount of fog or tonemap tuning would
have fixed it. An A/B of one viewpoint with each lighting factor isolated
(`tests/ab_lighting.gd`) then settled the cause: fog off changed nothing, ambient off
changed nothing, sun off dropped the mountains to their correct dark purple. Sun energy
went 1.25 → 0.32 and ambient 0.45 → 0.25.

A numeric sweep had reached a wrong conclusion on the way there and is worth recording.
It measured from 900 m, where `fog_depth_begin` is 2600 m — so "fog off changes nothing"
was true and meaningless, because there was no fog to find. The problem only appears at
the 2–3 km the wide shots are taken from. The first version of that sweep also averaged
whole frames that were two thirds sky, so every configuration came back within a percent
of the same number.

### Visual verification is now a workflow step

`tests/render_shot.gd` needs a GPU and a display, so it stays out of `run_tests.sh`.
Every rendering milestone now renders, and the images are inspected. That is not
ceremony. Three defects in this milestone passed every numeric assertion and were
obvious in the first screenshot:

- **The ocean shader never compiled.** `ALBEDO` is a `vec3` in a Godot 4 spatial
  shader, not a `vec4` as in Godot 3, so `ALBEDO = vec4(water, alpha)` was rejected.
  The sea plane drew nothing at all — and because the sky's lower hemisphere is a
  similar colour from above, it read as *flat purple water* rather than as missing
  water. Godot reports the error against the whole shader with no line of context, so
  it looked like the water expression was wrong. `scene_test.gd` now asserts the shader
  compiled, and that assertion was confirmed to fail when `vec4` is put back.
- **The camera's far plane clipped the sea.** Godot's default is 4000 m; the fog runs
  to 11000 m. The water was cut off in a hard straight line well short of the horizon,
  and because the cut also removed the water *under* a distant massif, that massif
  appeared to float in the sky as a detached shard. `ChaseCamera.visibility_range` now
  sets the far plane past the fog.
- **The seabed field's edge drew a seam across the ocean.** See above.

Two checks were added for the first two, and both were verified to fail when the defect
is reintroduced — a regression test that cannot fail is not a regression test.

### A diagnostic that was wrong is worth keeping

`tests/diagnose_floating_terrain.gd` reported 30 chunks floating up to 750 m above the
terrain. None of them were. Two mistakes, both documented in the file: chunk meshes keep
their world offset in the node *name*, with every transform left at the identity, so
reading `global_position` compared each chunk against the terrain at the world origin;
and the footprint was sampled one 25 m step from the corner of each 500 m chunk rather
than across it. With both fixed it reports zero, and a direct comparison of mesh
vertices against `height_at` at the same coordinates agrees to 0.0 m.

## Milestone 05 — airport and landmark (in progress)

### Built structures are merged, coloured in the vertex stream

`StructureBuilder` accumulates coloured primitives into one flat-shaded `ArrayMesh`.
Colour goes into the vertices rather than onto a material, which is the whole reason
merging is worth it: a banded lighthouse tower and a marked runway are the same draw
call. The airport is four meshes and the lighthouse two.

One deliberate exception: the lighthouse's lantern is a separate mesh with its own
emissive material, because it has to glow at dusk and everything else does not. That is
the only place a second draw call is spent on purpose.

### The runway renders torn, and I do not know why

**Open. Not fixed. Do not call this milestone done on the strength of the tests.**

From above, the runway renders as torn fragments rather than a strip. What has been
established, and what has been ruled out:

- *Not the mesh.* With the terrain hidden the runway renders solid and continuous, and
  its bounding box is the full 46 x 850 m. Every triangle is present.
- *Not the terrain.* All 507 chunk-mesh vertices inside the runway footprint sit at
  exactly 14.000 m, matching `height_at`, and the runway is above them.
- *Not depth precision.* Raising the pavement from 0.35 m to 3.0 m and then to 12.0 m
  produced a **pixel-identical** image each time. An occlusion or depth problem cannot
  behave that way.
- *Not the triangle size.* Subdividing the slab from two triangles to 24 segments
  changed nothing.
- *Not the winding, as far as the suite can tell.* `structure_test.gd` measures 330
  upward faces on the runway and every one points up.
- *It is culling.* Setting the runway material to `CULL_DISABLED` renders it complete
  and correct: centreline, threshold bars, aim points, edge lines, apron, buildings and
  approach lights all present.

So the geometry is right, the normals are right, and back-face culling still removes
part of it. `CULL_DISABLED` masks the symptom and doubles the fill cost, and shipping it
as a "fix" would be exactly the unverified workaround this project does not accept. The
camera's near plane was raised from Godot's 0.05 m default as a genuine, separately
measured improvement, but it is not the cause: the tearing survived that change too.

What would settle it: rendering the runway mesh alone from this viewpoint with a
wireframe or single-sided override and comparing triangle by triangle against the
culled render.

## Known rough edges

- **The aircraft has still never been flown by hand.** Everything below about the flight
  model is numeric.
- **The ocean has no shoreline at the airport's flat side**, and the swell is two crossed
  sines, which is enough for a calm stylised sea and not enough to survive a close pass
  at low altitude with the camera near the water. Foam bands are depth thresholds, so on
  a very shallow gradient they spread out rather than staying a crisp line.
- **Water coverage is still 56%, not the contract's 72%.** Carried over from milestone
  03 and unchanged here; the ocean shader made the discrepancy more visible rather than
  less, since the water is now worth looking at.
- **The mountains are steep — up to 5 m per metre.** Continuous rather than walls, so
  the aircraft can fly along them, but it cannot climb them. That suits an exploration
  game, where going around is the point, and it is a deliberate choice rather than an
  oversight. If it turns out to feel bad, the levers are `max_elevation` and
  `mountain_reach_fraction`, which are derived from each other and from the island
  size.
- **The flight model is verified against physics, not against feel.** It turns at the
  right rate for the right reason, and a headless autopilot climbs away from the
  airport and crosses the island, but nobody has flown it with a keyboard. Numbers in
  `FlightTuning` are reasoned estimates, not playtested values.
- **Airspeed input has no lag measurement in CI.** `axis_smoothing_time` is
  asserted to be configured, but response timing is only visible in
  `flight_analysis.gd`.
- **`MeshBuilder` normals carry float noise.** Face normals read back as
  `(0, 1, -0.000015)` rather than exact values. Harmless for rendering, but
  compare normals with a tolerance, as `procedural_test.gd` does.
- **`project.godot` is rewritten destructively by something in the verification run,
  and it has still not been reproduced in isolation.**
  Godot replaced the file with its own generated version, which dropped the `[physics]`
  section, `renderer/rendering_method="forward_plus"`, vsync, the screen-space AA
  setting and the `[debug]` warning suppressions, and reformatted every input event.
  Restored from git. It has now happened twice, both times after a `./scripts/verify.sh`
  run, and neither time could be reproduced on its own: `--editor --quit` twice from a
  cold `.godot` and again warm, a test suite run, a plain `--quit`, a display-mode
  render, and a script run from outside the project all left the file byte-identical.
  Deleting `.godot` and re-running the editor, which is the state most likely to differ
  from a normal run, also left it alone.

  An earlier backup/restore guard was removed for exactly this reason: the premise could
  not be reproduced, and a restore silently discards any real edit made in between,
  which is worse than the problem it solves. So there is still no guard. The practical
  consequence is to check `git status` after a verify run and `git checkout --
  project.godot` if it moved; the correct content is in the history.
- **Godot leak warnings on exit.** Every headless suite prints a few leaked RID
  warnings because the suites `quit()` mid-frame. `run_tests.sh` filters them.
  They are not memory leaks in the game.
- **The aircraft has no collider.** It is clamped to the terrain surface instead,
  which stops it sinking but does not stop it flying *into* a mountainside: it will
  follow the slope down and stop rather than bouncing off. That reads acceptably for
  an arcade flight model and is a reasonable thing to leave, but it is not collision.
  A collider or a slope-repulsion force would be the fix if it turns out to feel wrong.
- **Chunk generation is spread over frames, so the island fades in.** 4 chunks per
  frame at 60 fps. Deliberate: building the whole grid at once freezes on entry, and
  the grid grew with the island — it is sized from `island_radius`, so a larger island
  means more chunks and a longer fade. A loading screen would be better and is still
  outstanding. The seabed field is not spread this way: it is 65k `height_at` calls
  built synchronously at startup, which is a visible hitch on entry.
- **`turn_rate_degrees` is per-tick.** It is derived from one frame's heading
  change, so it is noisy frame to frame. Averaging it over several seconds gives
  the true rate; `flight_analysis.gd` shows the difference.