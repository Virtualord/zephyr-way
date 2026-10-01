---
name: ui-design
description: Design and implement Zephyr Way's minimal flight HUD, menus, mission panels and native Godot UI hierarchy.
---

Use Godot Control nodes only for in-game UI.

HUD goals:
- minimal
- readable
- unobtrusive
- aviation-inspired without becoming cluttered

Primary information:
- airspeed
- altitude
- heading
- throttle
- mission/objective information

Keep UI presentation separate from gameplay logic.

Use consistent spacing, hierarchy, opacity, typography and accent treatment based on `design/ui_design.json` when present.
