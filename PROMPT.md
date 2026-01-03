# Task

Build a minimal bash framework for running AI coding agents in autonomous loops ("Ralphing").

## Context

Study `@specs/ralph.md` to understand the Ralph Wiggum technique. This is your specification.

## What to Build

A bash-based framework in `src/` with:

1. **ralph.sh** - The main loop script that:
   - Reads PROMPT.md and pipes it to a configurable agent CLI (claude, amp, aider, etc.)
   - Commits changes after each loop iteration
   - Handles graceful shutdown (Ctrl+C)
   - Logs each iteration with timestamps

2. **init.sh** - Project scaffolding that creates:
   - `PROMPT.md` template
   - `fix_plan.md` template
   - `specs/` directory
   - `AGENT.md` template (how to build/test)

3. **tune.sh** - Helper to add "signs" (prompt amendments) when Ralph misbehaves

## Constraints

- Pure bash, no external dependencies beyond git and the agent CLI
- Simple, hackable, under 200 lines per script
- Follow the patterns from the spec: one task per loop, deterministic stack allocation

## Process

1. Study the spec at `@specs/ralph.md`
2. Check `@fix_plan.md` for current status
3. Choose the single most important thing to implement
4. Implement it
5. Update `@fix_plan.md` with progress
6. Commit your changes

After implementing, run any tests and verify the scripts work.
