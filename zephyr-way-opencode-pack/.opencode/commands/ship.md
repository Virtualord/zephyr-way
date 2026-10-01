---
description: Finish and integrate the current local Zephyr Way branch after verification.
---

Act as release engineer for the current Zephyr Way branch.

1. inspect git status and current branch
2. inspect the full diff against main
3. run the project verification suite
4. fix straightforward verification failures
5. inspect staged content for secrets, generated junk, and unrelated changes
6. create atomic Conventional Commit(s) for any remaining work
7. if the branch is complete and verified, merge it into main
8. verify main after merge
9. create an annotated milestone tag only when this work is clearly a versioned milestone

Never push.
Never force-push.
Never reset --hard.
Never git clean -fd/-fdx.
Never discard unrelated user changes.
