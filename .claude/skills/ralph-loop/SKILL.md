---
name: ralph-loop
description: |
  Coding agent loop that implements user stories from a PRD one at a time. Reads prd.json, picks the highest-priority incomplete story, implements it, runs quality checks, commits, updates the PRD, and logs progress. Invoke with /ralph-loop to execute one iteration of the loop.
---

# Ralph Loop — Autonomous Story Implementation

You are an autonomous coding agent. Each invocation of this skill implements exactly **one** user story from a PRD, then hands control back so the next iteration can pick up where you left off.

The single-story-per-iteration design is intentional: it keeps commits atomic, makes rollbacks easy, and lets the orchestrator (or human) inspect progress between stories.

## The Loop

### 1. Orient yourself

Read these files from the current working directory:

- **`.docs/tasks/prd.json`** — the product requirements document with user stories
- **`.docs/tasks/progress.md`** — the running log of completed work (pay special attention to the `## Codebase Patterns` section at the top, if it exists — these are hard-won lessons from previous iterations)

### 2. Get on the right branch

The PRD has a `branchName` field. Make sure you're on that branch:

**If you are inside a git worktree** (check with `git rev-parse --git-common-dir` — if it differs from `git rev-parse --git-dir`, you're in a worktree):
- The worktree already has its branch checked out — do NOT run `git checkout -b`
- Run `git branch --show-current` to confirm the branch matches the PRD's `branchName`
- If it doesn't match, STOP and tell the user — worktrees are pinned to their branch

**If you are in the main repo:**
- If the branch exists locally, check it out
- If it doesn't exist, create it from `main`
- If you're already on it, carry on

### 3. Pick the next story

Find the **highest priority** user story where `passes: false`. Priority is determined by the order in the PRD — earlier stories are higher priority.

### 4. Implement the story

Write the code. Keep changes focused and minimal — implement what the story asks for, nothing more. Follow the existing code patterns and conventions you see in the codebase.

### 5. Run quality checks

Run whatever quality checks the project uses — typecheck, lint, test, build, etc. Look at the project's CLAUDE.md, package.json, Makefile, Cargo.toml, or similar config files to figure out what checks are appropriate.

If checks fail, fix the issues before proceeding. Do not commit code that doesn't pass.

### 6. Capture learnings in CLAUDE.md and MEMORY.md

Before committing, think about whether you learned something that would help future work in the directories you modified:

- Look for existing CLAUDE.md files in or near the directories you changed
- If you discovered a reusable pattern (API conventions, gotchas, dependencies between files, testing requirements), add it

Good additions: "When modifying X, also update Y", "This module uses pattern Z for API calls", "Tests require running the dev server first"

Skip this if you didn't learn anything genuinely new and reusable.

### 7. Log your progress

Append an entry to `.docs/tasks/progress.md` (never overwrite — always append):

```
## [Date/Time] - [Story ID]
- What was implemented
- Files changed
- **Learnings for future iterations:**
  - Patterns discovered
  - Gotchas encountered
  - Useful context
---
```

The learnings section matters — it's how future iterations avoid repeating your mistakes.

### 8. Consolidate patterns

If any of your learnings are general enough to be reusable across stories, add them to the `## Codebase Patterns` section at the **top** of `.docs/tasks/progress.md`. Create this section if it doesn't exist yet.

```
## Codebase Patterns
- Use `sql<number>` template for aggregations
- Always use `IF NOT EXISTS` for migrations
- Export types from actions.ts for UI components
```

Only add patterns that are general and reusable, not story-specific details.

### 9. Commit

- Set `passes: true` for the completed story in `.docs/tasks/prd.json`.
- Stage all changes and commit with this message format:

```
feat: [Story ID] - [Story Title]
```

**Just commit, never push the changes to the remote repository**

## Stop Condition

After completing the story, check if **all** stories in the PRD now have `passes: true`.

- If **all complete**: respond with `COMPLETE` — the project is done.
- If **stories remain**: end your response normally. 
- The next `/ralph-loop` invocation will pick up the next story.
