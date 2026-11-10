# greenlyt

A Claude Code plugin that takes a need all the way to a **draft pull request ready for review**:

1. a spec is written, then approved by you;
2. a developer agent implements it, an independent reviewer agent challenges it;
3. the loop runs until **the tests are green and the reviewer approves**;
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

## What the loop does

On every round:

1. the `implementer` agent implements the spec and writes the tests, taking the previous round's objections into account;
2. the plugin's CLI **actually runs** the test command (`testCommand`): its exit code is the only one that counts;
3. the read-only `reviewer` agent returns a JSON verdict: `approved`, `objections`, `deviations` (liberties taken outside the spec), `specIssues` (ambiguities in the spec);
4. the round is committed on the work branch `greenlyt/<slug>`.

- **Success** (green tests + reviewer approval): any deviations are submitted to you (accept or fix), then the branch is pushed and a **draft pull request** is opened. Its description contains the spec, the AC → evidence table, the rounds and the accepted deviations.
- **Budget exhausted**: no push, no pull request. A failure report lists the red tests, the unresolved objections and **open questions** to refocus the spec. Update the spec with `/greenlyt:spec <slug>`, then run `/greenlyt:run <slug>` again: the run resumes on the same branch with a fresh budget.

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
