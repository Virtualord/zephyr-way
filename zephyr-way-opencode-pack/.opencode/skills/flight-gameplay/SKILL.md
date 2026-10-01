---
name: flight-gameplay
description: Implement Zephyr Way's arcade aircraft flight model, controls, camera feel, checkpoints and exploration gameplay.
---

The flight model should feel responsive and enjoyable rather than fully realistic.

Separate:
- player input
- flight state
- forces/tuning
- movement/orientation
- visuals
- camera
- audio
- HUD-facing data

Initial flight parameters:
- throttle
- acceleration
- drag
- lift
- gravity
- speed
- altitude
- pitch
- yaw
- roll
- stall behavior

Use delta time correctly.
Expose tuning parameters so they can be adjusted without rewriting logic.

Third-person camera requirements:
- smooth follow
- configurable distance/height
- look-ahead
- banking response
- limited jitter
- sensible clipping/collision behavior where practical

Do not implement aerospace-level simulation unless explicitly requested.
