---
name: shaders-atmosphere
description: Implement Zephyr Way's stylized sky, water, fog, lighting, color and lightweight shader effects in Godot 4.7.x.
---

Target an atmospheric low-poly look.

Use:
- WorldEnvironment
- procedural or gradient skies
- DirectionalLight3D
- fog
- StandardMaterial3D
- ShaderMaterial when it adds meaningful value

Water should be lightweight and stylized, not a physically accurate ocean simulator.

Shader rules:
- keep fragment cost reasonable
- avoid needless texture reads
- avoid unnecessary branches
- use clear uniforms and sensible defaults
- do not add expensive full-screen effects without measurement

Support the visual progression of day, golden hour, sunset, dusk and night when the project reaches those milestones.
