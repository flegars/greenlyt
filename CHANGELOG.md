# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-11-10

### Added

- `/greenlyt:init` skill: creates `.greenlyt/config.json` (test command, forge, protected branches, attempt cap).
- `/greenlyt:spec` skill: writes, stores and gets approval for a spec with verifiable acceptance criteria; update mode after a failure.
- `/greenlyt:run` skill: developer ↔ reviewer loop until tests are green and the verdict is approved, draft pull request on GitHub or Azure DevOps, failure report with open questions, run resumption.
- `implementer` and `reviewer` agents.
- `Stop` hook (attempt cap, `stop_hook_active`, kill switch, session binding) and `PreToolUse` protected branch guard.
- `bin/greenlyt` CLI: run state, test execution, verdict, preflight, reports, pull requests.
- Plain bash unit tests, PHP/PHPUnit and JS fixtures, e2e scenarios, CI.
