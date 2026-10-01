---
description: Review staged and unstaged changes and draft a clean Git commit plan
---

Review the current Git state for `$ARGUMENTS`.

Do NOT commit, amend, reset, rebase, merge, stash, or delete branches.

Inspect:
- `git status`
- the current diff
- the staged diff if present
- recent log history
- relevant project/design files

Determine:
1. whether the change is one logical unit
2. whether unrelated edits are mixed in
3. whether generated files or secrets appear staged
4. whether verification has been performed
5. whether the change should be split into multiple commits

Then propose:
- the exact files/hunks that belong in each commit
- a Conventional Commit message for each commit
- any verification that should happen before committing

Keep the plan concise and actionable.
