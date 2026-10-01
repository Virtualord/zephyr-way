---
description: Run a complete autonomous Zephyr Way development cycle for the requested milestone.
---

Work autonomously on the requested Zephyr Way milestone.

Process:
1. inspect repository, design files, current git status, and recent history
2. choose an appropriate short-lived branch
3. plan the smallest coherent implementation
4. implement it
5. run Godot validation/tests
6. run or inspect the affected gameplay when practical
7. invoke reviewer and performance-reviewer subagents when useful
8. fix issues found
9. inspect the final diff and staged content
10. create an atomic Conventional Commit
11. merge the completed branch into main if verification passes
12. verify main after merge
13. tag the milestone when it clearly represents a versioned checkpoint

Do not push to a remote.
Do not reset, force-push, clean, or discard unrelated work.
Do not stop merely to ask for approval for routine steps.

Requested milestone:
$ARGUMENTS
