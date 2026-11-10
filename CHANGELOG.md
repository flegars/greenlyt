# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
