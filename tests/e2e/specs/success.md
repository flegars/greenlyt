# Multiplication in the calculator

Status: approved

## Context

The project's calculator only provides addition.

## Goal

Add the multiplication of two integers.

## Scope

### In scope

- A function (JS: `multiply(a, b)` exported by `src/calculator.js`) or a method (PHP: `Calculator::multiply(int $a, int $b): int`) that multiplies two integers.

### Out of scope

- Any other operation, any input validation, any change to addition.

## Acceptance criteria

- **AC-1**: Given 3 and 4, when they are multiplied, then the result is 12.
- **AC-2**: Given -2 and 5, when they are multiplied, then the result is -10.
- **AC-3**: The existing addition is unchanged and its test still passes.

## Constraints

- No additional dependency.

## Open questions

- None.
