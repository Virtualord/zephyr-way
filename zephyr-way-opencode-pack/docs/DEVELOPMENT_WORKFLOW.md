# Zephyr Way — Overall Development Workflow

This is a solo game project with AI assistance. The workflow is intentionally close to a professional software workflow without adding process for its own sake.

## 1. Start from a clean main

```bash
git switch main
git pull --ff-only
git status
```

Do not start new work with an unexplained dirty working tree.

## 2. Define the smallest milestone

Use the existing design JSON and write one concrete goal.

Examples:

- Add arcade throttle and acceleration.
- Add a smooth chase camera.
- Generate one procedural island.
- Add a mission checkpoint.
- Refine the HUD.

Avoid milestones like "build the world".

## 3. Create a branch

```bash
git switch -c feat/chase-camera
```

One branch should represent one coherent goal.

## 4. Plan before asking AI to code

Inside OpenCode:

```text
/plan <goal>
```

Review the plan. Then implement only that goal:

```text
/implement <goal>
```

The AI can inspect and modify the repository, but it should not own Git history.

## 5. Play early

After a meaningful implementation:

```text
/playtest <what changed>
```

Run the game yourself too. For a game, human feel is part of verification.

Report concrete feedback back to the AI:

```text
The aircraft turns too slowly at low speed, the camera is too close, and the horizon feels empty.
Fix those issues without changing the flight architecture.
```

## 6. Review the implementation

```text
/review <goal>
```

Then inspect the actual diff:

```bash
git status
git diff --stat
git diff
```

The AI review is not a replacement for reading the diff yourself.

## 7. Verify before staging

Run:

```bash
./scripts/verify.sh
```

The script performs lightweight Git checks, Godot headless validation, and design JSON validation. Set `GODOT_BIN` if your executable is not on PATH.

Then:

```bash
git diff --check
```

## 8. Stage intentionally

Prefer explicit paths:

```bash
git add scripts/aircraft/aircraft_controller.gd scenes/aircraft/Aircraft.tscn
```

For mixed files:

```bash
git add -p
```

Inspect staged content:

```bash
git diff --cached
```

## 9. Commit atomically

Use a Conventional Commit:

```bash
git commit -m "feat(aircraft): add arcade flight controller"
```

The repository hook rejects vague/non-Conventional messages.

## 10. Continue or finish

If another logical change is needed, make another commit.

Do not create meaningless commits solely to record every AI response.

A good branch history should read like a development story.

## 11. Finish the branch

Review the branch as a whole:

```bash
git log --oneline --decorate main..HEAD
git diff main...HEAD --stat
git diff main...HEAD
```

Then run the full verification again.

## 12. Merge to main

When satisfied:

```bash
git switch main
git merge --no-ff feat/chase-camera
```

Verify main again:

```bash
./scripts/verify.sh
git status
```

Delete the finished branch:

```bash
git branch -d feat/chase-camera
```

## 13. Tag meaningful milestones

Only tag when the project reaches a meaningful playable state.

Examples:

```bash
git tag -a v0.1.0-prototype -m "First playable flight prototype"
git tag -a v0.2.0-flight -m "Arcade flight and camera milestone"
git tag -a v0.3.0-world -m "First playable island world"
```

Tags are checkpoints. They make it easy to return to a known-good state.

## 14. Push to GitHub

After creating the remote:

```bash
git push -u origin main
git push origin --tags
```

For a feature branch you may push it for backup or review:

```bash
git push -u origin feat/chase-camera
```

## AI-specific rule

Use AI heavily for planning, coding, design implementation, debugging, tests, and review.

Keep these actions human-controlled:

- commit
- amend
- merge
- rebase
- reset
- force-push
- branch deletion

This gives you the speed of vibe-coding without giving an AI uncontrolled ownership of your repository history.
