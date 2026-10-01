# Zephyr Way — Autonomous OpenCode Workflow

This project is intentionally configured so OpenCode can own most of the routine development loop while the developer retains control over destructive or external actions.

## Recommended start

Run:

```bash
opencode --auto
```

OpenCode auto mode approves permission requests unless an explicit deny rule blocks them. The repository config keeps dangerous Git operations blocked.

## What the autonomous agent may do

The agent may:

- inspect the repository
- edit project files
- create scenes/scripts/resources
- run Godot validation and test commands
- launch the game for verification
- create/switch local feature branches
- stage files
- create commits
- merge completed local feature branches into `main`
- create annotated milestone tags
- run code/design/performance reviews

## What remains explicitly blocked

The agent must not:

- force-push
- push to a remote unless explicitly instructed
- `git reset --hard`
- `git clean -fd` or `git clean -fdx`
- discard unrelated user changes
- amend existing commits automatically
- rewrite published history
- silently change engines or core technology

## Daily workflow

Start in the project root:

```bash
cd ~/Projects/zephyr-way
opencode --auto
```

Then give a high-level request such as:

```text
Implement the next milestone for Zephyr Way according to the roadmap. Work autonomously: plan, implement, test, review, commit, and integrate the completed local milestone. Do not push anything.
```

For a focused request:

```text
Implement procedural island generation. Work autonomously until it is verified and committed. Preserve all unrelated changes. Do not push.
```

## Expected Git history

Prefer history such as:

```text
main
|
|   merge feat/aircraft-controller
|  /
| /  feat(aircraft): add arcade flight controller
|/
* chore(project): bootstrap Godot project
|
* chore(repo): initialize Zephyr Way repository
```

Within a branch, commits should be small and meaningful. If a task naturally results in multiple independently useful commits, keep them separate.

## Milestone tags

Use semantic-style milestone tags such as:

- `v0.1.0-prototype`
- `v0.2.0-flight`
- `v0.3.0-world`
- `v0.4.0-missions`

Only tag work that has been verified on `main`.

## When the agent should stop

Stop and report when:

- the task is blocked by missing credentials/external access
- the requested change would be destructive or irreversible
- the repository has conflicting unrelated modifications that cannot be safely preserved
- a core product decision is required and cannot be reasonably inferred
- verification remains genuinely unavailable after reasonable attempts

Do not stop merely because an ordinary implementation error occurs. Diagnose and fix it.
