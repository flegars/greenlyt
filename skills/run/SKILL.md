---
name: run
description: Runs the greenlyt loop on an approved spec (a developer agent implements, an independent reviewer agent challenges it, round after round, until the tests are really green and the verdict is approved), then opens a draft pull request on GitHub or Azure DevOps. Reports deviations from the spec, and stops with a failure report and open questions when the attempt cap is reached. Resumes an interrupted, waiting or failed run. Trigger on /greenlyt:run, "run the greenlyt loop on <slug>", "implement the spec <slug> with greenlyt".
argument-hint: "<spec slug>"
---

# /greenlyt:run

Orchestrates the loop. **Every** operation on state, tests, git and the forge goes through the plugin's CLI. Never edit `.greenlyt/state/` by hand, and never claim a result the CLI has not observed.

```
GL="${CLAUDE_PLUGIN_ROOT}/bin/greenlyt"
```

A `Stop` hook keeps you from stopping while the run is `running`. **Kill switch**: before every step of the loop, run `"$GL" killed`. If it exits 0, run `"$GL" state set-status <run_id> aborted` and hand back immediately.

## 1. Start

The argument is the slug. The spec is `<docsDir>/specs/<slug>.md`, where `docsDir` comes from `"$GL" config .docsDir`.

1. `run_id=$("$GL" state find <slug>)` finds an existing run (`running`, `stalled`, `waiting` or `failed`). If found, `git checkout <branch of the run>` (`"$GL" state get <run_id> .branch`), then by status:
   - **`running` or `stalled`** (interrupted run): `"$GL" state set-status <run_id> running`, then go to step 2.
   - **`waiting`**: go straight to step 3.1 (decision on deviations).
   - **`failed`**: check that the spec has `Status: approved`, otherwise point to `/greenlyt:spec <slug>` and stop. If the spec changed, commit it (`git add <spec> && git commit -m "docs(greenlyt): update spec <slug>"`). Then `"$GL" state rebudget <run_id>` and go to step 2.
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

Announce the run: run-id, branch, cap.

## 2. Loop

Repeat:

1. `attempt=$("$GL" state next-attempt <run_id>)`. **Exit code 3** (cap reached) → step 4.
2. **Developer**: start the `greenlyt:implementer` agent with:
   - the spec path, the round `attempt` / `maxAttempts`;
   - from round 2 on: the objections of the previous verdict (`"$GL" state get <run_id> .verdict.objections`) and the test output (`"$GL" state get <run_id> .tests.tail`);
   - the deviations the user asked to remove, if any.
3. **Tests**: `"$GL" test <run_id>`. The recorded exit code is the only one that counts.
4. **Reviewer**: start the `greenlyt:reviewer` agent with the spec path, the `baseBranch`, the exit code and test output (read from the state), and the developer's summary.
5. **Verdict**: extract the JSON block from the reviewer's answer, write it to `.greenlyt/state/<run_id>.verdict`, then `"$GL" verdict <run_id> .greenlyt/state/<run_id>.verdict`. If the CLI rejects it (invalid format), run the reviewer once more with the error; on a second rejection, record the verdict `{"approved": false, "objections": [{"ref": "quality", "detail": "unreadable reviewer verdict"}], "deviations": [], "specIssues": []}`.
6. `"$GL" commit-tour <run_id>`.
7. `"$GL" decide <run_id>`:
   - `retry` → summarize the round in one line (tests, objections) and start again at 2.1;
   - `exhausted` → step 4;
   - `success` → step 3.

## 3. Success

### 3.1 Deviations

Read `"$GL" state get <run_id> .verdict.deviations` and the `deviations` config value (`"$GL" config .deviations`).

- **No deviation**, or `deviations: "report"` → 3.2.
- Otherwise (`ask`): `"$GL" state set-status <run_id> waiting`, then present each deviation (description, files, rationale) and ask the user with `AskUserQuestion`: **accept** all deviations, or **fix** (say which ones to remove).
  - **Accept** → `"$GL" state set-status <run_id> running`, then 3.2.
  - **Fix**: if `attempt < maxAttempts` → `"$GL" state set-status <run_id> running` and back to 2.1, passing these deviations to the developer as to be removed. Otherwise → step 4 (the run fails: never a pull request with a rejected deviation).

### 3.2 Report and pull request

1. `report=$("$GL" report <run_id> success)`, then `git add "$report" && git commit -m "docs(greenlyt): report <run_id>"`.
2. Write to `.greenlyt/state/<run_id>.acceptance.md` the Markdown **AC → evidence** table (one row per criterion of the spec: `| AC-n | test(s) | file(s) |`), built from the spec and the developer's last summary, checked against the diff.
3. `body=$("$GL" report <run_id> pr .greenlyt/state/<run_id>.acceptance.md)`.
4. `url=$("$GL" pr <run_id> "$body")`.
5. `"$GL" state set-status <run_id> succeeded`.
6. Give the user: the draft pull request URL, the number of rounds, the accepted deviations, the report path.

## 4. Failure

1. `report=$("$GL" report <run_id> failure)`. Do not commit it, push nothing.
2. `"$GL" state set-status <run_id> failed`.
3. Show the user: the report path, the tests still red, the unresolved objections and **the open questions** (`specIssues`). If there are none, write the questions yourself that would refocus the spec, based on the recurring objections.
4. Suggest the next step: `/greenlyt:spec <slug>` to update the spec with their answers, then `/greenlyt:run <slug>` to run the loop again with a fresh budget on the same branch.
