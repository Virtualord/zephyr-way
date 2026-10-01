# Zephyr Way — Git & Development Workflow

The goal is to keep the repository looking like a professional software project while still being comfortable for a solo developer using AI.

## Golden rules

1. `main` is always playable.
2. One branch = one coherent change.
3. One commit = one logical change.
4. Never commit generated junk or secrets.
5. Verify before commit.
6. Review the diff before merge.
7. Tag meaningful playable milestones.
8. Never let an AI silently rewrite history.

## Recommended daily loop

```text
Pull / sync main
      ↓
Create feature branch
      ↓
Read AGENTS.md + design JSON
      ↓
Plan
      ↓
Implement one slice
      ↓
Run /playtest
      ↓
Review diff
      ↓
Commit atomically
      ↓
Repeat if needed
      ↓
Review whole branch
      ↓
Merge to main
      ↓
Verify main
      ↓
Tag milestone when appropriate
```

## Starting work

```bash
git switch main
git pull --ff-only
git switch -c feat/aircraft-controller
```

Use `pull --ff-only` so Git does not create an accidental merge commit while syncing.

## While working

Check frequently:

```bash
git status
git diff
git diff --stat
git log --oneline --decorate -12
```

A good branch should tell a story when read from `git log`.

## Staging

Do not blindly run:

```bash
git add .
```

Prefer reviewing what you stage:

```bash
git add path/to/file.gd path/to/scene.tscn
git status
git diff --cached
```

For a larger change, `git add -p` can stage only the intended hunks.

## Commit style

Use Conventional Commits:

```text
feat(aircraft): add arcade flight controller
fix(world): prevent vegetation from spawning on water
refactor(missions): separate checkpoint validation
perf(terrain): cache generated meshes
design(ui): refine mission panel hierarchy
chore(git): add lightweight pre-commit checks
```

Use imperative language and keep the subject concise.

## Good commit size

Bad:

```text
feat: build entire game
```

Good:

```text
feat(aircraft): add aircraft scene
feat(aircraft): implement throttle and acceleration
feat(aircraft): add pitch roll and yaw controls
feat(camera): add smooth chase camera
```

Do not make commits so tiny that the history becomes noise. A commit should be understandable and independently meaningful.

## AI-specific workflow

When OpenCode changes code:

```bash
git status
git diff
```

Read the diff yourself.

Then use the project command:

```text
/review <feature>
```

If the review is clean, stage the intended changes and inspect:

```bash
git diff --cached
```

Ask OpenCode to draft a commit message with:

```text
/commit-review <feature>
```

Then you make the actual commit yourself:

```bash
git commit -m "feat(aircraft): add arcade flight controller"
```

This keeps ownership of repository history with you.

## Branch completion

When a branch is done:

```bash
git status
git diff main...HEAD --stat
git log --oneline main..HEAD
```

Review the complete branch.

Then merge it:

```bash
git switch main
git merge --no-ff feat/aircraft-controller
```

If you prefer a completely linear history, you can fast-forward instead. The important rule is consistency.

For this project, `--no-ff` is useful because milestone/feature branches remain visible in history.

After the merge:

```bash
git branch -d feat/aircraft-controller
git status
```

## Milestone tags

Once a milestone is playable and verified:

```bash
git tag -a v0.1.0-prototype -m "Zephyr Way first playable prototype"
git tag
```

Push tags when you push the repository:

```bash
git push origin main --tags
```

## What should NOT be committed

The repository should not contain:

- `.godot/`
- exported builds
- temporary files
- IDE state
- secrets
- huge reference videos
- generated caches

Reference screenshots that are small and useful may be versioned. Put very large raw media outside Git or use Git LFS when there is a real need.

## Useful history commands

Readable graph:

```bash
git log --graph --oneline --decorate --all
```

See what a feature changed:

```bash
git diff main...HEAD
```

Find where a change was introduced:

```bash
git log -S"search_text" --oneline --all
```

See file history:

```bash
git log --follow -- path/to/file.gd
```

## Recovery mindset

Git is a safety net, not a reason to work recklessly.

Before risky refactors, create a checkpoint commit on the feature branch. Do not use destructive commands to "clean up" the repository unless you are certain what will be removed.
