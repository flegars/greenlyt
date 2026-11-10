---
name: spec
description: Writes and stores the spec of a change before any greenlyt implementation (numbered, verifiable acceptance criteria, in/out of scope, grounded in the codebase), then gets it approved by the user. Also updates a spec after a failed /greenlyt:run. Trigger on /greenlyt:spec, "write the greenlyt spec", "spec this need for greenlyt", "update the spec <slug>".
argument-hint: "\"<need in plain text>\" | <existing slug>"
---

# /greenlyt:spec

Produces the spec that will be the loop's **fixed reference**: the test writer derives the tests from it, the developer implements it, and the reviewers use it to judge and to spot deviations. A vague spec makes a loop that never converges: precision here is the priority.

## 1. Preconditions

- `.greenlyt/config.json` exists. Otherwise, point to `/greenlyt:init` and stop.
- Read `docsDir` from the config (`"${CLAUDE_PLUGIN_ROOT}/bin/greenlyt" config .docsDir`, default `docs/greenlyt`). Specs live in `<docsDir>/specs/<slug>.md`.

## 2. Mode

- **Argument = slug of an existing spec** → **update** mode. Read the spec and, if any, the latest failure report `<docsDir>/runs/*-<slug>.md`: its "Open questions" are the starting point.
- **Otherwise** → **create** mode. Propose a short kebab-case slug (e.g. `csv-export`) and check it does not exist yet.

## 3. Grounding in the code

Before writing, explore the codebase: where the feature fits, the current behavior, the conventions and existing tests. Read the repository's `CLAUDE.md` if there is one. Assume nothing you have not read.

## 4. Clarification

Ask the questions needed to remove ambiguity, **one at a time**, starting with the one that changes the outcome most. In update mode, start with the open questions from the failure report.

## 5. Writing

Fill in `templates/spec.md` (in this skill's folder). Requirements:

- Each criterion is numbered `AC-n` and phrased so that it **can be verified by an automated test** (input, action, observable result).
- The **out of scope** section is explicit: it is what lets the reviewers qualify a deviation or a regression.
- No blocking open question remains at approval.
- The `Status: draft` line stays as is until the user approves.

Write `<docsDir>/specs/<slug>.md` and show it to the user.

## 6. Approval

Ask explicitly: "Do you approve this spec?". Iterate on the feedback. **Only** after explicit approval, replace the line with `Status: approved`. Do not commit: `/greenlyt:run` commits the spec as the first commit of the work branch.

Point to the next step: `/greenlyt:run <slug>`.
