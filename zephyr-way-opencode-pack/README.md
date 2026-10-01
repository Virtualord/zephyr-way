# Milestone 1 — Playable flight slice

A working vertical slice: a procedurally generated aircraft you can fly around a
flat test environment with a chase camera, built in Godot 4.7.x with no external
assets and no modelling step.

Status: implemented and verified headless. Not yet verified by eye.

## Run it

```bash
godot --path . # or open project.godot in the Godot editor and press F5
```

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Pitch | `W` / `S` or `↑` / `↓` | Left stick Y |
| Roll | `A` / `D` or `←` / `→` | Left stick X |
| Yaw (rudder) | `Q` / `E` | Bumpers |
| Throttle | `Shift` / `Ctrl` | Right trigger |
| Airbrake | `Space` | Left trigger |
| Reset to start | `R` | Y |

The aircraft starts parked on the ground at the origin facing north. Hold
`Shift` to spool up, and it will lift off on its own once it is fast enough —
there is no manual gear retraction in this milestone.

## What is here

- **Arcade flight model** — throttle, thrust, quadratic drag, lift, gravity,
  airspeed, altitude, pitch/roll/yaw, stall, airbrake, ground roll and taxi
  steering. `FlightModel` is pure maths with no node dependencies.
- **Procedural aircraft** — a low-poly light sport aircraft built entirely in
  code from `AircraftProfile` values, with animated propeller, control surfaces
  and nose-wheel steering. Dimensions and colours come from
  `design/aircraft_design.json`.
- **Chase camera** — smoothed follow with partial roll inheritance, velocity
  look-ahead, and speed-driven FOV.
- **Flat test environment** — ground plane, reference grid for judging speed,
  distant procedural ridges for a horizon, and dusk lighting from
  `design/color_palette.json`.
- **Input map** — keyboard and gamepad, generated from a single table.

There is **no HUD yet**. Flight data is available on `FlightState` in the
debugger. That is the main limitation to be aware of while flying.

## Verify

```bash
./scripts/verify.sh
```

Runs whitespace checks, design JSON validation, Godot project validation, and
229 assertions across five headless suites. Individual suites:

```bash
godot --headless --path . --script res://tests/flight_model_test.gd
```

Rebind a key by editing the table in `scripts/core/generate_input_map.py` and
re-running it. Do not hand-edit the `[input]` section of `project.godot`.

## Tuning

Two Resources hold every number:

- `resources/aircraft/default_flight_tuning.tres` — feel. Speeds, forces,
  control rates, stall behaviour, ground handling.
- `resources/aircraft/default_aircraft_profile.tres` — shape. Dimensions,
  silhouette, colours, control surface travel.

Both are plain data with no logic, and both can be edited live in the inspector.
Aircraft lift and drag are *derived* from cruise and max speed rather than typed
in, so changing a speed rebalances the forces consistently; see
`docs/ARCHITECTURE.md`.

## Layout

```
project.godot
design/            design contract (source of truth for intent)
scenes/            main, aircraft, world
scripts/
  aircraft/        flight model, input, state, tuning, visuals, camera
  world/           test environment and terrain sampling
  main/            scene assembly and entry point
  utilities/       mesh building, palette access, unit conversions
  core/            input map generator
shaders/
resources/         .tres data
tests/             headless suites and the flight recorder
docs/              architecture and workflow
```

`docs/ARCHITECTURE.md` explains why the boundaries are where they are.

## Known limitations

- **Unverified visually.** Everything is checked headless: parse checks,
  numerical assertions, scene instantiation. The airframe proportions have never
  been seen, and are the most likely thing to need adjustment.
- **No HUD.** Reading flight data requires the debugger.
- **No collision.** Flying through terrain is possible; there is no collider.
- **No audio.**
- **Lateral acceleration is not modelled.** The aircraft banks rather than
  sideslipping, which is the arcade simplification `AGENTS.md` asks for.

## Suggested next milestone

Per `PROMPTS_MILESTONES.md`, **02 — flight feel**. Tune responsiveness, drag,
stall behaviour and pitch/roll/yaw balance against how it actually flies. The
model and its tuning are already separated, so this should not require
structural change.