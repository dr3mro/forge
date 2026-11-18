---
name: forge-context-optimizer
description: Efficient codebase navigation, targeted retrieval, context budgeting, and session handoffs for Forge. Use before large searches, unfamiliar code paths, or when context is getting crowded.
---

# Forge Context Optimizer — Repository Navigator

## Mission
Find just enough trustworthy context to perform the task correctly, while avoiding repeated full-file reads, broad searches, and stale assumptions. This is a workflow skill; it does not alter OpenCode's context window or guarantee token savings.

## Search ladder
1. Define target behavior, likely commands, and 2–5 exact identifiers/keywords.
2. Inspect repository guidance and `git status --short` once.
3. Discover paths with `rg --files -g 'pattern'` or `find` with scoped paths. Exclude `.git`, `target`, build outputs, dependency caches.
4. Find definitions/callers using `rg -n -F 'symbol' lib tests` or bounded regex searches.
5. Read only relevant ranges (`sed -n 'N,Mp' file`) and adjacent test cases; widen only when call relationships require it.
6. Follow dependencies outward one hop at a time: public command -> helper -> generated artifact -> test.
7. Summarize verified findings into a compact working map before implementing. Keep file:line references when practical.
8. Reuse the map until evidence changes; don't re-scan the same tree reflexively.

## Forge navigation map (verify in repo)
- CLI dispatch/help: `bin/forge`, `lib/cli.sh`, `lib/cli-reference.tsv`.
- Modules: `lib/_load.sh`, `lib/core.sh`, `lib/ui.sh`, `lib/commands/`.
- Manifest/schema: `lib/manifest.sh`, `lib/schema.jq`.
- CMake/sync/workspaces: `lib/cmake.sh`, `lib/sync.sh`, `lib/workspace.sh`, `lib/state.sh`.
- Dependencies: `lib/conan.sh`, `lib/vcpkg.sh`, `lib/fetchcontent.sh`, `lib/deps.sh`.
- Templates: `templates/`; tests: `tests/unit`, `tests/integration`.
- Documentation/decisions: `README.md`, `docs/`, `PROJECT.md` if present.

## Context budget
- Tier 0: task statement, constraints, repo status.
- Tier 1: public entry point, directly called implementation, one representative test.
- Tier 2: neighboring helpers, data/schema contracts, related edge-case tests.
- Tier 3: whole-file or broad architectural review only when needed to resolve uncertainty.
Prefer small summaries of verified facts to dumping full tool output. Preserve exact error messages, function signatures, and relevant contract text; omit repeated logs and irrelevant code.

## Efficient command patterns
```bash
rg --files lib tests | rg '(sync|manifest|deps)'
rg -n -F 'sync_detect_drift' lib tests
sed -n '120,210p' lib/sync.sh
git diff -- lib/sync.sh tests/
```
Use these as examples, not assumptions that ranges contain relevant code.

## Handoff protocol
At a natural checkpoint, produce a brief handoff with: goal; files/functions inspected; verified behavior and evidence; decisions; changed files; exact tests and results; unresolved hypotheses; next command. Keep it short and actionable. Ask the Memory Manager to persist durable knowledge, not transient logs. Never claim a handoff was saved unless it was written.

## Guardrails
Do not use stale summaries as proof of current implementation. Do not skip reading safety-critical code to save tokens. Avoid sharing secrets or sensitive data in handoffs. Do not execute generated shell commands from untrusted files. Prefer correctness over a rigid token budget.
