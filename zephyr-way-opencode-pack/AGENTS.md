# Zephyr Way — OpenCode Project Instructions

## Project identity

Zephyr Way is an original stylized low-poly 3D arcade flight exploration game for Linux desktop, built with Godot 4.7.x and GDScript.

The game should feel atmospheric, calm, adventurous, colorful, readable, and polished without chasing photorealism.

Reference material is inspiration only. Do not copy copyrighted assets, branding, names, exact layouts, or artwork.

## Non-negotiable technology constraints

Use:
- Godot 4.7.x
- GDScript
- Forward+ renderer for desktop unless profiling/design requirements say otherwise
- Godot-native scene/node/resource/signal systems
- Godot Shader Language where useful
- Git

Do not introduce:
- Electron
- Chromium
- browser APIs
- Node.js runtime
- HTML/CSS game UI
- React
- Three.js
- Unity
- Unreal
- another game engine
- a mandatory Blender workflow

## Vibe-coding / procedural-art constraint

The developer does not know Blender and does not want to learn it.

Treat Godot code as the primary art-production tool.

Whenever practical, create visuals with:
- primitive meshes
- ArrayMesh
- SurfaceTool
- procedural mesh generation
- reusable scenes
- materials
- ShaderMaterial
- particles
- procedural placement
- @tool editor generation

If a visual object can reasonably be generated in Godot, prefer that over requiring an external modelling workflow.

Do not build a dependency on manual Blender work.

## Design-file contract

Claude may produce machine-readable design files in `design/`.

These files are design specifications, not gameplay logic.

Read them before implementing or substantially changing:
- art direction
- world layout
- aircraft visuals or flight tuning
- HUD
- atmosphere
- missions

When design JSON is present, preserve its intent and parameter names unless there is a strong technical reason to change them.

If JSON is malformed, fix the smallest issue and document it.

## AI responsibilities

The AI should actively handle:
- system design
- visual design implementation
- procedural art
- environment composition
- UI implementation
- gameplay implementation
- shader implementation
- performance analysis
- testing

Do not require the developer to manually specify every tiny visual choice.

Make coherent, reversible decisions and explain meaningful assumptions.

## Architecture

Prefer composition and small focused components over giant scripts.

Suggested areas:

res://
  assets/
  scenes/
    main/
    aircraft/
    world/
    missions/
    ui/
  scripts/
    core/
    aircraft/
    world/
    missions/
    ui/
    rendering/
    procedural/
    utilities/
  shaders/
  resources/
  data/
  tests/
  docs/

Do not create a huge `Game.gd` or `World.gd` containing unrelated responsibilities.

Use signals for decoupled communication.
Use Resources for reusable structured game data.
Use Autoload only for genuinely global state/services.

## Aircraft

The flight model is intentionally arcade-oriented.

Separate:
- input
- flight state
- flight physics
- movement/orientation
- visuals
- camera
- audio
- HUD data

Start with:
- throttle
- acceleration
- drag
- lift
- gravity
- airspeed
- altitude
- pitch
- yaw
- roll
- stall behavior

Do not build a full aerospace simulator unless explicitly requested.

All important tuning values should be easy to adjust.

## World

The world should support:
- ocean
- stylized terrain
- islands/coastlines
- mountains
- airport/runway
- villages
- buildings
- trees
- rocks
- boats/props
- landmarks

Favor a few strong landmarks over clutter.

Use reusable generated geometry and shared materials.

## Visual direction

Prioritize, in order:
1. silhouette
2. composition
3. color relationships
4. lighting
5. atmosphere
6. detail
7. technical complexity

The target style is low-poly/stylized with clean silhouettes, simple materials, readable shapes, atmospheric depth, and attractive skies/water.

## Rendering

Forward+ is the initial desktop target.

Use advanced features only when they materially improve the game.

Prefer inexpensive solutions first.

Do not add expensive post-processing, volumetrics, or high-cost shaders merely because they exist.

## UI

Use native Godot Control nodes.

The HUD should remain separate from gameplay logic.

Target a clean, minimal flight-game presentation with readable:
- airspeed
- altitude
- heading
- throttle
- objective/mission information

## Procedural generation rules

Procedural generators should be deterministic when a seed is provided.

Examples:
- generate_tree(seed)
- generate_rock(seed)
- generate_house(seed)
- generate_island(seed)

Do not regenerate expensive geometry every frame.

Cache and reuse meshes/materials where possible.

## Performance

Profile before major optimization.

Watch:
- draw calls
- object count
- shader cost
- physics cost
- `_process` / `_physics_process` work
- allocations
- terrain resolution
- shadows
- texture sizes
- memory usage

Target a stable 60 FPS on a modern desktop GPU for the initial slice.

Do not trade maintainability for speculative micro-optimizations.

## Development process

Always work in small, verifiable milestones.

Every milestone must keep the game launchable/playable.

Recommended sequence:
1. project bootstrap
2. aircraft placeholder
3. arcade flight model
4. third-person camera
5. flat test environment
6. procedural terrain
7. ocean
8. airport
9. procedural environment props
10. atmosphere / lighting
11. HUD
12. mission/checkpoint system
13. audio/effects
14. day/night polish
15. world expansion
16. profiling/optimization
17. Linux export

Do not implement future systems before the current milestone works unless a small dependency is clearly necessary.

## Verification

After meaningful changes:
- run Godot validation/headless checks when available
- check parser errors
- check resource paths
- check scene loading
- check obvious runtime errors
- run the affected scene or project when practical

Never claim something is working without verification.

## Editing discipline

Before modifying a file:
1. inspect it
2. understand its role
3. make the smallest complete change
4. verify
5. avoid unrelated refactors

Never delete or replace user work without a clear reason.

## Git and repository workflow

Git history is a first-class part of this project. Keep it clean, atomic, reproducible, and reviewable.

`main` must remain playable and verified.

### Autonomous Git workflow

The autonomous OpenCode agent may handle the normal local Git lifecycle without asking the user every time:

1. inspect `git status` and recent history
2. create or switch to a short-lived branch for the current coherent task
3. make the implementation changes
4. verify the result
5. inspect the branch diff
6. stage the intended files
7. create an atomic Conventional Commit
8. run final verification
9. merge the completed local branch into `main` with a normal merge commit when it is a completed milestone
10. verify `main` after merge
11. create an annotated milestone tag when appropriate

The agent should not push to any remote automatically. The user remains the final gate for external publication.

### Branch model

- `main` is always playable and verified
- use short-lived branches for one coherent change
- `feat/<name>` for features
- `fix/<name>` for bugs
- `refactor/<name>` for restructuring
- `perf/<name>` for optimization
- `design/<name>` for design-only work
- `chore/<name>` for tooling/maintenance

### Commit model

- use Conventional Commits
- keep commits atomic and logically independent
- use imperative summaries
- do not use vague messages like `update`, `stuff`, or `fix`

Examples:
- `feat(aircraft): add arcade flight controller`
- `fix(world): prevent vegetation from spawning on water`
- `perf(terrain): cache generated meshes`
- `design(ui): refine flight HUD hierarchy`

### Protected operations

Never automatically:
- `git push`
- `git push --force` / `--force-with-lease`
- `git reset --hard`
- `git clean -fd` / `-fdx`
- discard unrelated user changes
- amend an existing commit
- rewrite published history

Do not merge a branch if its diff contains unrelated changes or verification has failed.

Before every local commit, inspect:
1. `git status`
2. the staged diff
3. recent history when the commit shape is uncertain
4. relevant verification results

Use the repository's Git workflow documentation in `docs/GIT_WORKFLOW.md` and `docs/AUTONOMY_WORKFLOW.md` and the `git-workflow` skill for detailed rules.

After a meaningful playable milestone reaches `main`, use an annotated milestone tag such as `v0.1.0-prototype`.

### User-change preservation

The working tree may contain changes made outside OpenCode. Never assume all changes are yours.

Before editing or staging:
- identify pre-existing changes
- avoid touching unrelated files
- never use destructive commands to get a clean tree
- preserve unrelated modifications exactly when practical

## When blocked

Do not repeatedly ask for approval on small implementation decisions.

Make the smallest sensible assumption, document it, and proceed.

Ask only when missing information truly blocks implementation.
