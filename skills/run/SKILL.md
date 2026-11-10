---
name: run
description: Runs the greenlyt loop on an approved spec. A test writer writes failing tests first, a developer makes them pass, and four independent reviewers (spec, architecture, security, non-regression) challenge the result round after round, until the tests are really green and no blocking objection is left. A refactoring agent then simplifies the code, which is reverted if it breaks anything, and a draft pull request is opened on GitHub or Azure DevOps. Reports deviations from the spec, and stops with a failure report and open questions when the attempt cap is reached. Resumes an interrupted, waiting or failed run. Trigger on /greenlyt:run, "run the greenlyt loop on <slug>", "implement the spec <slug> with greenlyt".
argument-hint: "<spec slug>"
---

# /greenlyt:run

Orchestrates the loop. **Every** operation on state, tests, git and the forge goes through the plugin's CLI. Never edit `.greenlyt/state/` by hand, and never claim a result the CLI has not observed.

```
GL="${CLAUDE_PLUGIN_ROOT}/bin/greenlyt"
S=".greenlyt/state"
```

## Agents

| Agent | Role | Writes |
|---|---|---|
| `greenlyt:test-writer` | Writes the failing tests that prove each acceptance criterion (TDD) | tests only |
| `greenlyt:implementer` | Makes the locked tests pass | production code |
| `greenlyt:spec-reviewer` | Spec conformance, AC coverage, deviations, spec issues | nothing |
| `greenlyt:architecture-reviewer` | Project architecture, patterns, placement, dependencies | nothing |
| `greenlyt:security-reviewer` | Injection, secrets, authz, validation, dependencies | nothing |
| `greenlyt:regression-reviewer` | Existing tests, public contracts, out-of-scope behavior | nothing |
| `greenlyt:refactorer` | Simplifies the change once it is approved | production code |

The reviewers to run are those listed in `"$GL" config .reviewers` (default: `spec`, `architecture`, `security`, `regression`). Reviewer `<name>` is the agent `greenlyt:<name>-reviewer`.

A `Stop` hook keeps you from stopping while the run is `running`. **Kill switch**: before every step below, run `"$GL" killed`. If it exits 0, run `"$GL" state set-status <run_id> aborted` and hand back immediately.

## 1. Start

The argument is the slug. The spec is `<docsDir>/specs/<slug>.md`, where `docsDir` comes from `"$GL" config .docsDir`.

1. `run_id=$("$GL" state find <slug>)` finds an existing run (`running`, `stalled`, `waiting` or `failed`). If found, `git checkout <branch of the run>` (`"$GL" state get <run_id> .branch`), then by status:
   - **`running` or `stalled`** (interrupted run): `"$GL" state set-status <run_id> running`, then read `"$GL" state get <run_id> .refactor.status`:
     - `running` → step 3.2 (refactoring was interrupted: revert it);
     - `applied`, `unchanged` or `reverted` → step 3.3 (refactoring is over);
     - empty, and `"$GL" decide <run_id>` prints `success` → step 3.1 (the last round was approved);
     - otherwise → section 2 (Loop).
   - **`waiting`**: go straight to step 3.3 (decision on deviations).
   - **`failed`**: check that the spec has `Status: approved`, otherwise point to `/greenlyt:spec <slug>` and stop. If the spec changed, commit it (`git add <spec> && git commit -m "docs(greenlyt): update spec <slug>"`). Then `"$GL" state rebudget <run_id>` and go to section 2 (Loop).
2. Otherwise, `run_id=$("$GL" preflight <docsDir>/specs/<slug>.md)`. On failure, explain the code to the user and stop:

| Code | Meaning |
|---|---|
| 10 | no config, or no `testCommand` → `/greenlyt:init` |
| 11 | kill switch is on |
| 12 | spec missing or not approved → `/greenlyt:spec` |
| 13 | the working tree is not clean → commit or stash |
| 14 | another run is already in progress → resume it with `/greenlyt:run <its slug>`, or abort it with `"$GL" state set-status <run_id> aborted` |
| 15 | the test suite already fails on the base branch |
| 16 | the work branch already exists |
| 17 | the config or the spec is missing from the base branch → commit `.greenlyt/config.json` on the base branch |

Announce the run: run-id, branch, cap, reviewers.

## 2. Loop

Repeat:

1. `attempt=$("$GL" state next-attempt <run_id>)`. **Exit code 3** (cap reached) → step 4.
2. **Tests first.** Run this step when no test is locked yet (`"$GL" state get <run_id> '.lockedTests | length'` is `0`, which also covers a round 1 interrupted before locking), and otherwise only if the previous verdict has blocking objections about missing or meaningless tests (refs `AC-n` from the spec reviewer):
   1. Start `greenlyt:test-writer` with the spec path, the round, the already locked files, and (after round 1) those coverage objections.
   2. `"$GL" tests lock <run_id> <file>...` with exactly the files listed under "Files to lock" in its summary. A file that is already locked keeps its original version: the test writer cannot rewrite a locked test either.
   3. `"$GL" test <run_id>`: the new tests must be **red**. If the suite is green, start the test writer once more and tell it its tests prove nothing, then repeat 2.2.2 and 2.2.3 once. If it is still green, `"$GL" state tdd-warning <run_id> "<which tests were already green>"` and go on.
3. **Implementation.** Start `greenlyt:implementer` with:
   - the spec path, the round `attempt` / `maxAttempts`, the locked test files (`"$GL" state get <run_id> '.lockedTests | keys'`);
   - from round 2 on: the blocking objections of the previous verdict (`"$GL" state get <run_id> '[.verdict.objections[] | select(.severity != "minor")]'`) and the test output (`"$GL" state get <run_id> .tests.tail`);
   - the deviations the user asked to remove, if any.
4. **Checks.** `"$GL" tests check <run_id>`: a non-zero exit means a locked test or the greenlyt config was changed; it becomes a critical objection, which `greenlyt verdict` picks up by itself. Then `"$GL" test <run_id>`: the recorded exit code is the only one that counts.
5. **Review.** Start **all configured reviewers in parallel**, in a single message. Give each one the spec path, the `baseBranch`, the exit code and test output (read from the state), and the developer's summary. Extract the JSON block from each answer and write it to `$S/<run_id>.verdict.<name>`.
6. **Verdict.** `"$GL" verdict <run_id> $S/<run_id>.verdict.<name>...` with one file per reviewer that answered. The CLI deletes the files it merged, so a verdict can never be reused in a later round. If the CLI rejects a reviewer's verdict (invalid format), run that reviewer once more with the error; on a second rejection, write for it `{"reviewer": "<name>", "objections": [{"ref": "<name>", "severity": "major", "detail": "unreadable reviewer verdict"}], "deviations": [], "specIssues": []}`. A reviewer without a verdict file is reported as missing and the round is never approved.
7. `"$GL" commit-tour <run_id>`.
8. `"$GL" decide <run_id>`:
   - `retry` → summarize the round in one line (tests, blocking objections per reviewer) and start again at 2.1;
   - `exhausted` → step 4;
   - `success` → step 3.

## 3. Success

### 3.1 Refactoring

Refactoring runs at most once per run and does not consume an attempt. Skip to 3.3 if `"$GL" config .refactor` is not `true`, or if `"$GL" state get <run_id> .refactor.status` is already set.

1. `"$GL" refactor start <run_id>` records the green commit, its test result and its verdict.
2. Start `greenlyt:refactorer` with the spec path, the `baseBranch` and the non-blocking remarks (`"$GL" state get <run_id> '[.verdict.objections[] | select(.severity == "minor")]'`).
3. If `git status --porcelain -- . ':(exclude).greenlyt'` is empty (nothing changed), `"$GL" refactor done <run_id>` (recorded as `unchanged`) and go to 3.3.
4. Otherwise run steps 2.4, 2.5 and 2.6 again (checks, all reviewers, verdict), then `"$GL" decide <run_id>`:
   - `success` → `git add -A -- . ':(exclude).greenlyt/state' ":(exclude)<docsDir>/runs" && git commit -m "refactor(greenlyt): simplify <slug>"`, then `"$GL" refactor done <run_id>` (recorded as `applied`), then 3.3;
   - anything else → step 3.2.

### 3.2 Refactoring revert

`"$GL" refactor revert <run_id> "<why: red tests, or the blocking objections>"`. This stashes the refactoring leftovers, restores the green commit and restores its recorded test result and verdict, so no re-review is needed. Go to 3.3.

### 3.3 Deviations

Read `"$GL" state get <run_id> .verdict.deviations` and `"$GL" config .deviations`.

- **No deviation**, or `deviations` is `report` → 3.4.
- Otherwise (`ask`): `"$GL" state set-status <run_id> waiting`, then present each deviation (description, files, rationale) and ask the user with `AskUserQuestion`: **accept** all deviations, or **fix** (say which ones to remove).
  - **Accept** → `"$GL" state set-status <run_id> running`, then 3.4.
  - **Fix**: if `attempt < maxAttempts` → `"$GL" state set-status <run_id> running` and back to 2.1, passing these deviations to the developer as to be removed. Otherwise → step 4 (the run fails: never a pull request with a rejected deviation).

### 3.4 Report and pull request

0. **Gate**: `"$GL" decide <run_id>` must print `success`. Otherwise, never open a pull request: go back to section 2 (Loop) if it prints `retry`, or to step 4 if it prints `exhausted`.
1. `report=$("$GL" report <run_id> success)`, then `git add "$report" && git commit -m "docs(greenlyt): report <run_id>"`.
2. Write to `$S/<run_id>.acceptance.md` the Markdown **AC → evidence** table (one row per criterion of the spec: `| AC-n | test(s) | file(s) |`), built from the spec and the test writer's summaries, checked against the diff.
3. `body=$("$GL" report <run_id> pr $S/<run_id>.acceptance.md)`.
4. `url=$("$GL" pr <run_id> "$body")`.
5. `"$GL" state set-status <run_id> succeeded`.
6. Give the user: the draft pull request URL, the number of rounds, the accepted deviations, the non-blocking remarks, the refactoring outcome, the report path.

## 4. Failure

1. `report=$("$GL" report <run_id> failure)`. Do not commit it, push nothing.
2. `"$GL" state set-status <run_id> failed`.
3. Show the user: the report path, the tests still red, the unresolved blocking objections per reviewer and **the open questions** (`specIssues`). If there are none, write the questions yourself that would refocus the spec, based on the recurring objections.
4. Suggest the next step: `/greenlyt:spec <slug>` to update the spec with their answers, then `/greenlyt:run <slug>` to run the loop again with a fresh budget on the same branch.
