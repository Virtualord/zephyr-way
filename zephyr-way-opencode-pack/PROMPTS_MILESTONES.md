# Zephyr Way milestone prompts

Use one prompt at a time. Do not ask the agent to build the entire game in one pass.

## 02 — Flight feel
`/implement Refine the aircraft flight model based on the current implementation. Improve responsiveness, acceleration, braking/drag, stall behavior, pitch/roll/yaw balance, and tuning. Do not change the world or UI. Verify takeoff, climb, descent, turns, stall, and landing behavior.`

## 03 — Procedural island
`/implement Create the first small procedural island according to design/world_design.json. Use Godot-native terrain/procedural mesh generation. Include coastline, a few mountains, a valley, and a flat area suitable for the future airport. Keep geometry low-poly and performant. Do not implement missions yet.`

## 04 — Ocean + atmosphere
`/implement Add the stylized ocean, sky, fog, sun lighting, and atmospheric depth described by the design files. Keep shaders lightweight. Preserve the aircraft and terrain.`

## 05 — Airport + landmark
`/implement Add the first airport/runway and coastal lighthouse landmark from design/world_design.json. Build them procedurally or from simple reusable Godot scenes. Prioritize readable silhouettes from the air.`

## 06 — Environment composition
`/implement Populate the island with procedural trees, rocks, houses, and small environmental props. Use deterministic seeds, reusable meshes, shared materials, and sensible visibility/instance behavior. Keep object count under control.`

## 07 — HUD
`/implement Build the flight HUD according to design/ui_design.json. Display airspeed, altitude, heading, throttle and a compact mission/objective panel. Keep all gameplay logic outside the UI.`

## 08 — Mission system
`/implement Implement the first data-driven mission from design/mission_design.json: takeoff, checkpoint 1, checkpoint 2, visit the lighthouse, then land at the airport. Keep mission state independent from UI.`

## 09 — Audio/effects
`/implement Add lightweight aircraft engine audio, simple environmental ambience, and restrained flight effects. Avoid bloated asset pipelines; use procedural/simple effects where practical.`

## 10 — Visual polish
`/design Review Zephyr Way's current visual state as an art director. Identify the 5 highest-impact visual improvements. Do not edit files. I will choose one and invoke `/implement`.`

## 11 — Profiling
`/perf Review current performance of the playable slice. Focus on the main scene, aircraft, terrain, world props, water shader, shadows, and per-frame scripts. Do not edit files. Identify what should actually be measured/fixed first.`

## Git checkpoint after every milestone

Before starting a new milestone:

```bash
git status
git log --oneline --decorate -10
git switch main
git pull --ff-only
git switch -c feat/<milestone-name>
```

After the milestone is verified, use `/review`, inspect `git diff`, make atomic commits, merge to `main`, verify `main`, and tag the milestone when it is meaningfully playable.

Do not let OpenCode commit or rewrite Git history automatically. You own the final repository history.

## Autonomous mode

For normal development, work autonomously through plan → implementation → verification → review → commit → local integration. Do not push to a remote. Preserve unrelated user changes and never use destructive Git commands.
