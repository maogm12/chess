# Agent Instructions

Before editing or reviewing code, read `LESSONS.md` and the relevant sections of
`README.md`. Follow applicable instructions from parent directories as well.

## Maintenance

- Base cleanup on a concrete problem, such as duplicated rules, unclear ownership,
  stale code, or excessive coupling. Keep changes small and preserve behavior.
- Preserve existing user work. Use an isolated branch/worktree for scheduled
  maintenance, and check existing maintenance PRs before starting overlapping work.
- Do not edit vendored Arasan sources or the NNUE network as routine cleanup.
- Validate changes with the relevant build and existing tests. Add regression
  coverage when fixing a bug or changing behavior; report checks actually run.
- Record reusable, evidence-backed lessons in `LESSONS.md`, including the cause,
  prevention rule, code references, and verification. Update an existing lesson
  rather than duplicating it. Do not turn speculation into project rules.

## Project Boundaries

Keep the app native UIKit, offline, and compatible with existing saved libraries.
Preserve puzzle navigation, human/bot turn semantics, independent history branches,
and request invalidation across asynchronous engine work.
