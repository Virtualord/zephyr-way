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

Two speeds are *derived* rather than typed in:

```
lift_gain         = gravity / cruise_speed^2     -> level flight at cruise
drag_coefficient  = acceleration / max_speed^2   -> max speed at full throttle
```

This keeps the numbers self-consistent. Editing `max_speed_knots` rebalances drag
automatically instead of leaving the aircraft unable to reach its stated top
speed. The override fields exist for the cases where a designer wants to break
that relationship deliberately.

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

`TestEnvironment` is the flat test bed milestone 1 asks for, and it is also the
terrain height authority. That role is why it exposes:

```gdscript
func ground_height_at(position: Vector3) -> float:
```

`AircraftController` samples this through a `Callable`. Replacing the flat world
with real terrain is a change to this one function; the flight model already
handles arbitrary ground heights and has a test asserting exactly that
(`terrain pushes the aircraft to gear height`).

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
| `recorder_test.gd` | 19 | Replay determinism, recording budget |
| `scene_test.gd` | 28 | Scenes load, wire together, and simulate without errors |

Suites run as separate Godot processes because each one quits the engine itself.

The flight assertions are deliberately loose. They guard against regressions like
inverted lift or a stall that never fires, not against specific handling numbers,
which are a design decision rather than a bug. A test that fails when the game
feels different is a test that will get deleted.

## Adding things

Practical notes on where new code tends to go.

**A new world feature** (ocean, terrain, airport, props) becomes a sibling scene
under `scenes/world/` with its own script, instanced into `Main.tscn` beside
`TestEnvironment`. It should not modify the flight model.

**A new aircraft** needs a new `AircraftProfile` `.tres` and nothing else. If it
needs different behaviour rather than different shape, add a field to the profile
before adding a subclass.

**A new telemetry value** is added to `FlightState`, set in
`FlightModel._step_in_air` or `_step_on_ground`, and refreshed in
`FlightState.refresh()`. The HUD milestone will read it from there; no gameplay
change is needed to display it.

**A new input action** goes in `scripts/core/generate_input_map.py`, then re-run
that script. Do not hand-edit `project.godot`.

**World terrain** replaces `TestEnvironment.ground_height_at()`. Keep the
signature stable; the flight model depends on it.

## What is deliberately absent

Milestone 1 is a vertical slice, not a game. These are absent on purpose, and
`PROMPT_FIRST.md` lists them as out of scope: terrain, ocean, missions, HUD,
menus, audio, save state, day/night.

There are also no autoloads. Every service so far is scene-local, and per
`AGENTS.md` autoloads are for genuinely global state — which does not exist yet.
`[autoload]` in `project.godot` is empty and should stay that way until something
genuinely needs to outlive a scene.

Nothing renders a HUD yet, which means flight data is currently only observable
by reading `FlightState` in the debugger. That is the main reason to expect the
milestone 7 prompt to be worth its cost: flying without instruments is hard to
judge, and `tests/flight_recorder.gd` exists partly to compensate.

## Known rough edges

- **No visual verification.** Everything here is verified headless: parse checks,
  numerical assertions, scene instantiation. Nothing has confirmed the aircraft
  *looks* right. Expect to iterate on the airframe proportions by eye, and expect
  `AircraftProfile` to be where those fixes land.
- **`MeshBuilder` normals carry float noise.** Face normals read back as
  `(0, 1, -0.000015)` rather than exact values. Harmless for rendering, but
  compare normals with a tolerance, as `procedural_test.gd` does.
- **Godot leak warnings on exit.** Every headless suite prints a few leaked RID
  warnings because the suites `quit()` mid-frame. `run_tests.sh` filters them.
  They are not memory leaks in the game.
- **No collision geometry.** The aircraft has no collider. That is correct for a
  flight model driven by terrain height, but it means flying through a mountain
  is possible until terrain milestone 3 lands.