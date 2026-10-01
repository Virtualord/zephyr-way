---
name: git-workflow
description: Maintain clean, reviewable Git history for Zephyr Way with atomic commits, feature branches, verification, tags, and safe AI collaboration.
---

# Git Workflow Skill

Git history is part of the quality of Zephyr Way.

## Branch model

Use:
- `main` for stable, playable code
- short-lived branches for one coherent change

Branch naming:
- `feat/<name>` for new features
- `fix/<name>` for bug fixes
- `refactor/<name>` for internal restructuring
- `perf/<name>` for performance work
- `design/<name>` for design-only changes
- `chore/<name>` for tooling/project maintenance

a branch should normally address one user-visible goal or one technical goal.

## Main branch rule

`main` should remain:
- buildable
- runnable
- playable
- free of known broken intermediate work

Do not commit half-finished experiments to `main`.

## Commit rules

Use Conventional Commits:

`type(scope): imperative summary`

Examples:
- `feat(aircraft): add arcade flight controller`
- `feat(camera): add smooth chase camera`
- `fix(aircraft): prevent roll instability at low speed`
- `refactor(world): separate terrain generation from object placement`
- `perf(world): reuse procedural vegetation meshes`
- `design(ui): refine flight HUD hierarchy`
- `chore(project): add Linux verification script`

Keep commits atomic.
A commit should represent one logical change that could be reviewed independently.

Do not create commits such as:
- `update`
- `changes`
- `stuff`
- `fix`
- `final`
- `working`

If a change has unrelated edits, split them before committing.

## Commit sequencing

A good feature branch may look like:

1. `feat(aircraft): add aircraft scene and input mapping`
2. `feat(aircraft): add arcade flight physics`
3. `feat(camera): add smooth chase camera`
4. `test(playtest): verify basic flight milestone`

Do not create a commit for every tiny line edit. Combine tiny edits when they form one logical change.

## AI commit policy

The AI must NOT commit, amend, reset, rebase, merge, or delete branches unless the user explicitly asks it to do so.

The AI may:
- inspect Git status/history
- inspect diffs
- identify unrelated changes
- suggest a commit split
- draft commit messages
- review staged changes

Before a user commits, the AI should help verify:
- intended files are staged
- no secrets are staged
- no generated junk is staged
- no unrelated edits are staged
- verification has been performed

## Before implementation

1. start from an up-to-date `main`
2. create a short-lived branch
3. inspect existing code and design data
4. implement one coherent change

Example:

```bash
git switch main
git pull --ff-only
git switch -c feat/procedural-island
```

## During implementation

Inspect often:

```bash
git status
git diff
git diff --stat
git log --oneline --decorate -10
```

Do not let unrelated formatting or generated files enter the branch.

## Before commit

Run lightweight checks:

```bash
git diff --check
```

Validate relevant Godot scenes/scripts using the project's verification command.

Review:

```bash
git diff --cached
```

Only then commit.

## History hygiene

Prefer additive, reversible commits.

Avoid giant commits combining:
- gameplay
- UI
- art
- tooling
- unrelated refactors

Avoid rebasing shared branches. These are intended to be short-lived personal feature branches.

## Milestones

After a coherent milestone is verified, tag `main` with a semantic milestone tag.

Examples:
- `v0.1.0-prototype`
- `v0.2.0-flight`
- `v0.3.0-world`
- `v0.4.0-missions`

Use annotated tags for milestones.

## Merge strategy

For this solo AI-assisted project:

1. finish feature branch
2. run verification
3. review diff
4. make sure commits are atomic and meaningful
5. merge into `main`
6. verify `main`
7. tag a milestone when appropriate

Prefer preserving meaningful atomic commits. Do not squash merely to make the history shorter.

## Safety

Never:
- force-push without explicit instruction
- use `git reset --hard` to discard work
- clean untracked files destructively
- rewrite history on `main`
- delete a branch containing unmerged user work

If Git state is ambiguous, inspect before acting.
