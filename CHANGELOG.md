# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `env-scout` agent and `greenlyt env` CLI: before the loop, `/greenlyt:run` works out how to run the tests on the current worktree, on any stack. When `testCommand` tests another clone (for example a pod that mounts the main clone), it proposes a disposable environment (setup, test command, teardown), mounts it after your approval, remembers the recipe per repository for every worktree, and tears it down every time the run hands back to you. The `Stop` hook tears it down once no run is in progress.

### Changed

- `/greenlyt:run` works in the directory Claude runs in. On a branch that is not protected (typically a worktree's own branch), it runs in place on that branch instead of creating a new one; a `<branchPrefix><slug>` branch is only created when the run starts on a protected branch. The run skill no longer moves the run to another clone.
- Work branches no longer mention greenlyt: the default `branchPrefix` is now `feat/` (`feat/<slug>` instead of `greenlyt/<slug>`). Existing configs that set `branchPrefix` explicitly keep their value.

## [0.1.0] - 2026-11-10

### Added

- `/greenlyt:init` skill: creates `.greenlyt/config.json` (test command, forge, protected branches, attempt cap).
- `/greenlyt:spec` skill: writes, stores and gets approval for a spec with verifiable acceptance criteria; update mode after a failure.
- `/greenlyt:run` skill: test-first loop (test writer → implementer → four reviewers in parallel) until tests are green and no blocking objection is left, guarded refactoring, draft pull request on GitHub or Azure DevOps, failure report with open questions, run resumption.
- Agents: `test-writer`, `implementer`, `spec-reviewer`, `architecture-reviewer`, `security-reviewer`, `regression-reviewer`, `refactorer`.
- Severity-graded verdicts (`critical`, `major`, `minor`): only `critical` and `major` objections block; `minor` ones become non-blocking remarks in the pull request.
- Test locking: tests written by the test writer cannot be changed by the implementer.
- `Stop` hook (attempt cap, `stop_hook_active`, kill switch, session binding) and `PreToolUse` protected branch guard.
- `bin/greenlyt` CLI: run state, test execution, test locking, verdict merging, refactoring with revert, preflight, reports, pull requests.
- Plain bash unit tests, PHP/PHPUnit and JS fixtures, e2e scenarios, CI.
