---
name: init
description: Sets up greenlyt in the current project by creating .greenlyt/config.json (test command, GitHub or Azure DevOps forge, protected branches, attempt cap, docs folder). Run once per project, before /greenlyt:spec and /greenlyt:run. Trigger on /greenlyt:init, "set up greenlyt", "configure greenlyt for this project".
argument-hint: "(no arguments)"
---

# /greenlyt:init

Creates the greenlyt configuration for the current project. Nothing is written before the user approves the proposal.

## 1. Preconditions

- The current directory is inside a git repository (`git rev-parse --show-toplevel`). Otherwise, stop and say so.
- If `.greenlyt/config.json` already exists, show it and ask whether the user wants to change it or stop there.

## 2. Detection

From the repository root:

| Hint | Proposed `testCommand` |
|---|---|
| `composer.json` + `vendor/bin/phpunit` or `phpunit.xml(.dist)` | `vendor/bin/phpunit` |
| `package.json` with a `test` script | `npm test` (or `pnpm test` / `yarn test` depending on the lockfile) |
| Anything else | ask the user |

Forge, from `git remote get-url origin`:

- `github.com` → `{"type": "github"}`
- `dev.azure.com/<org>/<project>/_git/<repo>` or `<org>.visualstudio.com/<project>/_git/<repo>` → `{"type": "azure-devops", "organization": "https://dev.azure.com/<org>", "project": "<project>", "repository": "<repo>"}`
- Anything else, or no remote → ask the user.

`baseBranch`: the remote's default branch (`git symbolic-ref refs/remotes/origin/HEAD`), otherwise `main`.

## 3. Proposal

Show the full config, defaults included:

```json
{
  "docsDir": "docs/greenlyt",
  "testCommand": "<detected>",
  "maxAttempts": 5,
  "protectedBranches": ["main", "master", "develop"],
  "branchPrefix": "feat/",
  "deviations": "ask",
  "forge": { "type": "<detected>", "remote": "origin", "baseBranch": "<detected>" }
}
```

Explain in one line each value the user may want to change: `docsDir`, `maxAttempts`, `deviations` (`ask` = stop and let the user decide on deviations, `report` = only list them in the pull request). Ask for approval.

## 4. Writing

After explicit approval:

1. Write `.greenlyt/config.json`.
2. Add `.greenlyt/state/` and `.greenlyt/STOP` to the project's `.gitignore` if missing.
3. Check that the test command passes: `bash -c "<testCommand>"`. If it fails, or if it runs the tests on another clone (a container or pod that does not mount this directory), say that `/greenlyt:run` will propose a disposable test environment for this worktree before the loop, and refuse to start while the tests are red.
4. Remind the user to commit `.greenlyt/config.json` and `.gitignore` **on the base branch**: `/greenlyt:run` requires a clean working tree and creates its work branch from the base branch.
5. Point to the next step: `/greenlyt:spec "<need>"`.
