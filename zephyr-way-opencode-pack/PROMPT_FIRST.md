You are the primary implementation agent for Zephyr Way.

Read `AGENTS.md`, inspect the repository, inspect `design/`, and discover the available project-local skills before making changes.

Zephyr Way is a native Linux desktop 3D game built with Godot 4.7.x and GDScript. It is a stylized low-poly arcade flight exploration game.

Important constraints:
- no Electron
- no Chromium
- no Node.js runtime
- no browser technologies
- no React/Three.js
- no Unity/Unreal
- no mandatory Blender workflow
- use Godot-native/procedural art wherever practical

The developer wants to vibe-code the project and does not know Blender. You therefore own as much implementation and visual construction as reasonably possible.

Use the design files in `design/` as the design contract. Do not blindly invent a different aesthetic.

Before implementation:
1. inspect the repository
2. inspect the Godot version/project file if present
3. inspect all relevant design JSON
4. inspect the available skills
5. decide the smallest playable milestone

FIRST MILESTONE ONLY:

Build a working vertical-slice foundation containing:

1. a valid Godot project
2. a main scene
3. a simple procedurally assembled low-poly aircraft placeholder
4. arcade flight controls
5. throttle
6. pitch
7. roll
8. yaw
9. acceleration/drag/gravity/basic lift
10. airspeed and altitude state
11. a smooth third-person chase camera
12. a simple flat test environment
13. basic lighting and sky
14. basic input actions

Do NOT yet build:
- final terrain
- villages
- airport detail
- full mission system
- large asset library
- day/night system
- advanced shaders
- menus
- multiplayer
- save system

The purpose of this milestone is to prove that Zephyr Way feels good to fly.

Architecture requirements:
- typed GDScript where practical
- separate aircraft input, flight physics, visuals, and camera responsibilities
- no giant script
- configurable tuning values
- reusable scenes/components

Procedural-art requirement:
The aircraft must be created in Godot without Blender. Use primitive or procedural mesh construction and simple materials. Prioritize silhouette over detail.

Verification:
- validate scripts/scenes
- launch/run the game when practical
- fix actual parser/runtime errors
- do not claim success without verification

When complete:
1. summarize what you created
2. list important files
3. state what was actually tested
4. state any limitations
5. recommend exactly one next milestone

STOP after this milestone. Do not continue building the rest of the game automatically.

## Git workflow requirement

Before implementation, inspect the current Git state.

Do not make Git history changes automatically.

Do not commit, amend, merge, rebase, reset, force-push, or delete branches unless explicitly instructed.

Treat the current milestone as one coherent feature branch change.

Before declaring the milestone complete:
- show changed files
- verify the project
- summarize any unrelated changes that were already present
- suggest one Conventional Commit message

The human developer will perform the actual commit after reviewing the diff.

## Autonomous mode

For normal development, work autonomously through plan → implementation → verification → review → commit → local integration. Do not push to a remote. Preserve unrelated user changes and never use destructive Git commands.
