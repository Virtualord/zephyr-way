---
name: procedural-art
description: Create Zephyr Way's low-poly aircraft, props, buildings, vegetation and other visual assets entirely through Godot-native procedural geometry, materials, shaders and editor tools.
---

Zephyr Way must remain developable without Blender.

Prefer Godot-native approaches such as:
- primitive meshes
- ArrayMesh
- SurfaceTool
- ImmediateMesh when appropriate
- reusable scenes
- ShaderMaterial
- GPUParticles3D
- @tool scripts

Prioritize silhouette, proportion, color and lighting before geometric detail.

Procedural generators should accept deterministic seeds when variation is useful.

Do not generate expensive geometry every frame.
Cache reusable meshes/materials.
Separate generation code from gameplay code.

When a complex asset cannot be represented well enough procedurally, prefer a simple stylized approximation over making Blender a required dependency.
