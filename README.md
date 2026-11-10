# greenlyt

A Claude Code plugin that takes a need all the way to a **draft pull request ready for review**:

1. a spec is written, then approved by you;
2. a test writer agent writes the failing tests, a developer agent makes them pass, and four independent reviewer agents (spec, architecture, security, non-regression) challenge the result;
3. the loop runs until **the tests are green and no reviewer has a blocking objection**, then a refactoring agent simplifies the code without changing its behavior;
4. any deviation from the spec is reported to you before the pull request is opened.

## Installation

```
/plugin marketplace add flegars/greenlyt
/plugin install greenlyt@greenlyt
```

## Usage

```
/greenlyt:init                 # once per project → .greenlyt/config.json
/greenlyt:spec "<need>"        # → docs/greenlyt/specs/<slug>.md, approved by you
/greenlyt:run <slug>           # loop → draft pull request, or failure report
```

Specs and reports are written to `docs/greenlyt/` (configurable with `docsDir`).

## Agents

| Agent | Role | Writes |
|---|---|---|
| `test-writer` | Writes the failing tests that prove each acceptance criterion, **before** any implementation (TDD) | tests only |
| `implementer` | Makes those tests pass; may not change them | production code |
| `spec-reviewer` | Spec conformance, acceptance criteria coverage, deviations, ambiguities in the spec | nothing |
| `architecture-reviewer` | The project's own architecture: layers, patterns, file placement, dependencies | nothing |
| `security-reviewer` | Injection, secrets, authentication and authorization, input validation, risky dependencies | nothing |
| `regression-reviewer` | Existing tests deleted or weakened, public contracts changed, behavior changed out of scope | nothing |
| `refactorer` | Simplifies the change once it is approved, with identical behavior | production code |

Reviewers grade each objection `critical`, `major` or `minor`. Only `critical` and `major` objections send the loop into another round; `minor` ones are listed in the pull request as non-blocking remarks.

## What the loop does

On every round:

1. the `test-writer` writes the tests for every acceptance criterion (round 1, then only when a reviewer asks for missing coverage); the CLI **locks** them and checks that they fail before any implementation;
2. the `implementer` makes them pass, taking the previous round's blocking objections into account;
3. the CLI checks that no locked test was changed (a change is a critical objection) and **actually runs** the test command (`testCommand`): its exit code is the only one that counts;
4. the four reviewers run **in parallel** and each returns a JSON verdict; the CLI merges them and approves the round only if the tests are green, every expected reviewer answered and no `critical` or `major` objection is left;
5. the round is committed on the work branch `greenlyt/<slug>`.

- **Success**: the `refactorer` simplifies the code once, then tests and reviewers run again. If anything breaks, the CLI reverts to the green commit and the green version is kept. Any deviations are then submitted to you (accept or fix), the branch is pushed and a **draft pull request** is opened. Its description contains the spec, the AC → evidence table, the rounds per reviewer, the accepted deviations, the non-blocking remarks and the refactoring outcome.
- **Budget exhausted**: no push, no pull request. A failure report lists the red tests, the unresolved objections per reviewer and **open questions** to refocus the spec. Update the spec with `/greenlyt:spec <slug>`, then run `/greenlyt:run <slug>` again: the run resumes on the same branch with a fresh budget.

`/greenlyt:run` refuses to start if the working tree is not clean, if the spec is not approved, or if the test suite is already red on the base branch. The work branch is created from the local base branch, which must contain the committed `.greenlyt/config.json`.

An interrupted run (crash, closed terminal) is resumed by running `/greenlyt:run <slug>` again. To drop it instead:

```bash
"<plugin>/bin/greenlyt" state set-status <run-id> aborted
```

## Configuration: `.greenlyt/config.json`

| Key | Default | Purpose |
|---|---|---|
| `docsDir` | `docs/greenlyt` | Folder for specs (`specs/`) and reports (`runs/`) |
| `testCommand` | (required) | Test command, run with `bash -c` at the repository root |
| `maxAttempts` | `5` | Cap on rounds per run (deviation fixes included) |
| `protectedBranches` | `["main","master","develop"]` | Branches on which commit, push, `reset --hard` and rebase are blocked |
| `branchPrefix` | `greenlyt/` | Prefix of the work branch |
| `deviations` | `ask` | `ask`: stop and let you decide on deviations; `report`: only list them in the pull request |
| `reviewers` | `["spec","architecture","security","regression"]` | Reviewers that must approve every round; remove one to skip it |
| `refactor` | `true` | Run the refactoring agent once the change is approved |
| `forge.type` | `github` | `github` (with `gh`) or `azure-devops` (with `az repos`) |
| `forge.remote` | `origin` | Git remote to push to |
| `forge.baseBranch` | `main` | Starting branch and pull request target |
| `forge.organization`, `forge.project`, `forge.repository` | | Azure DevOps only |

Examples per stack and per forge are in [`examples/config/`](examples/config/).

## Guardrails

- **Attempt cap**: past `maxAttempts`, the loop stops with a failure report and never disguises a failure as a success.
- **`Stop` hook**: keeps Claude from stopping in the middle of a run. It is bound to the session running the loop, so other sessions in the same repository are never blocked. It honors `stop_hook_active`: when woken twice without the round counter moving, it lets Claude stop and marks the run `stalled`.
- **Protected branch guard** (`PreToolUse` hook): refuses `git commit`, `git push`, `git reset --hard` and `git rebase` on a protected branch, and any push targeting one (`git push origin HEAD:main`, `--all`, `--mirror`). It is a best-effort safety net that parses shell commands, not a security boundary: also protect your branches on the forge. It is active in every project with a greenlyt config.
- **Kill switch**: create `.greenlyt/STOP` or export `GREENLYT_DISABLED=1`. The run is marked `aborted` and the loop stops.

## Requirements

`bash`, `git`, `jq`, plus `gh` (GitHub) or `az` with the `azure-devops` extension (Azure DevOps), authenticated.

## Development

```bash
bash tests/unit/run.sh          # unit tests for hooks and CLI (plain bash), run in CI on every push
claude plugin validate .        # plugin and marketplace validation
bash tests/e2e/run.sh js budget # e2e: fixtures js | php-phpunit, scenarios success | budget
```

The e2e tests make real model calls (`ANTHROPIC_API_KEY`): they run manually or nightly, never on every push. The forge is simulated (`GREENLYT_FORGE_DRY_RUN=1`) and the remote is a local bare git repository.

## Versioning

Semver with git tags `vX.Y.Z`. The version in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` must match the tag, and `CHANGELOG.md` must have a section for that version: CI checks this on every tag.

## License

MIT
