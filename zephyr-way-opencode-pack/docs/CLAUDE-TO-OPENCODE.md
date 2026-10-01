# Claude → OpenCode workflow

1. Give Claude the reference screenshots and the design prompt in `docs/CLAUDE-DESIGN-PROMPT.md`.
2. Ask Claude to create/refine concrete JSON files in `design/`.
3. Put those JSON files into this repository.
4. Open the repository with OpenCode.
5. Tell OpenCode to read AGENTS.md and the design files before implementation.
6. Implement one milestone at a time with `/implement ...`.
7. Use `/design ...` when the game looks visually weak.
8. Use `/review ...` before accepting substantial code changes.
9. Use `/perf ...` after the first playable slice.

The design JSON is the contract. OpenCode implements it in Godot.

## Git handoff

Claude's design JSON is versioned source material. When design changes, keep them in focused commits such as `design(world): tune island composition`. OpenCode must preserve that separation and must not automatically commit or rewrite history.
