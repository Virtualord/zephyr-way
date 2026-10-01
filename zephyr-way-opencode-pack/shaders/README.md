# Shaders

Intentionally empty for milestone 1. `PROMPT_FIRST.md` lists advanced shaders as
out of scope, and the flat test environment reads correctly with plain
`StandardMaterial3D` and a `ProceduralSkyMaterial`.

The ocean in milestone 04 will be the first shader here, and per
`.opencode/skills/shaders-atmosphere/SKILL.md` it should stay lightweight and
stylized rather than physically accurate.

`MeshBuilder` already assigns explicit per-face normals, which is what a faceted
low-poly look needs from any future surface shader.
