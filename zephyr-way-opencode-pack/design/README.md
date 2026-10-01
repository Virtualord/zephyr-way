# Zephyr Way Design Contract

These files are produced or refined in regular Claude chat and consumed by OpenCode.

They describe design intent; they are not the source of gameplay logic.

Recommended files:
- art_direction.json
- color_palette.json
- world_design.json
- aircraft_design.json
- environment_design.json
- ui_design.json
- atmosphere_design.json
- camera_design.json
- mission_design.json
- game_design.json

Keep values concrete and machine-readable. Avoid vague strings such as "make it beautiful" when a numeric or categorical value can express the intent.

OpenCode should preserve the intent of these files when implementing features.

## Git ownership

Design files are versioned source-of-truth documents. Review their diff just like code. Prefer focused commits such as `design(world): tune island composition` rather than mixing design edits into unrelated gameplay commits.
