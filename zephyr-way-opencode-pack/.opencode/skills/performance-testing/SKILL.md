---
name: performance-testing
description: Profile, test and optimize Zephyr Way's CPU, GPU, memory, physics, loading and rendering performance using evidence rather than guesswork.
---

Profile before making substantial performance claims.

Check:
- frame time
- CPU vs GPU bound behavior
- draw calls
- object count
- shader complexity
- shadows
- physics steps
- per-frame script work
- memory usage
- resource duplication
- loading time

Prefer:
- shared meshes/materials
- instancing
- visibility ranges
- LOD
- chunking when justified
- cached resources
- simplified collision

After changes, rerun the relevant test and state what was actually verified.
