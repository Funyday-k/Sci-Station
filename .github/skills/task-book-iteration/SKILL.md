---
name: task-book-iteration
description: "Use when: following a task book, 任务书, Proposal, Next-Step-Task-Book, iteration, 迭代, or Sci-Station task cycle. Enforces reading, reviewing, revising, completing all listed tasks, reviewing the work, writing the next task book, summarizing, and asking Questions for the next direction before ending."
argument-hint: "[task book path or iteration goal]"
---

# Task Book Iteration

## Outcome

Complete one full task-book-driven iteration. A complete iteration starts by reading the current task book, reviews and revises it, executes every task in it, reviews the finished work, writes the next task book, summarizes the round, and asks the user clear Questions to decide the next direction and details.

## When to Use

- The user asks to work from a task book, proposal, iteration plan, or next-step document.
- The workspace contains task documents such as `docs/development/Next-Step-Task-Book.md` or `docs/development/Proposal*.md`.
- The user asks to continue, complete, review, revise, or plan the next round of Sci-Station work.

## Required Workflow

1. Locate the task book.
   - Prefer an explicit path from the user.
   - If no path is provided, prefer the active editor document when it is a task/proposal document.
   - Otherwise inspect `docs/development/Next-Step-Task-Book.md`, then the latest relevant `docs/development/Proposal*.md`.

2. Read and understand the task book before doing implementation work.
   - Read the whole task book, not only the current visible section.
   - Follow references to adjacent design notes, proposals, or implementation notes when they define acceptance criteria.
   - Extract every concrete task, requirement, decision point, acceptance check, and unresolved Question.

3. Review and revise the task book.
   - Check whether the tasks are complete, actionable, ordered, and testable.
   - Add or revise missing acceptance criteria, risks, dependencies, or task sequencing when the document is too vague to execute reliably.
   - Keep revisions focused on making the current iteration executable.
   - If a required decision cannot be inferred, ask a concise Question instead of silently choosing a major product direction.

4. Build a visible execution checklist.
   - Track every task from the task book, including documentation, validation, and review tasks.
   - Keep statuses current while working.
   - Do not mark the iteration complete until every task is done, explicitly deferred by user decision, or blocked by a concrete external dependency.

5. Execute all tasks in the task book.
   - Continue working until the listed scope is complete.
   - Do not stop after partial implementation, analysis only, or a first successful test when remaining tasks still exist.
   - If implementation reveals necessary small follow-up fixes inside the same scope, include them in the current round.
   - If a blocker appears, document what was attempted, why it blocks completion, and what user decision or external action is needed.

6. Review the completed work.
   - Compare the result against every task and acceptance check from the task book.
   - Inspect changed files and make sure unrelated user changes were not reverted.
   - Run the validation commands appropriate for the repository and changed files when possible.
   - Record any skipped validation with the reason.

7. Write the next task book before ending the iteration.
   - Check if a next task book already exists in the repository (e.g. the next numbered `docs/development/Proposal*.md`).
   - If a next task book exists, update it with a summary of the completed round, verified state, remaining risks, and any adjustments needed based on what was learned during implementation.
   - If no next task book exists, ask the user whether to create one or defer.
   - Do NOT create a `docs/development/Next-Step-Task-Book.md` file. The canonical location for task books is `docs/development/Proposal<N>.md`.
   - Include a `Question` section with actionable choices or prompts for the user. These Questions must guide the next round's broad direction and important details.

8. Finalize the round.
   - Summarize what was completed, what was validated, what changed in the task book, and where the next task book lives.
   - Ask the same key `Question` items from the next task book in the final response.
   - Do not end the turn without either completing the full iteration or clearly reporting a genuine blocker.

## Decision Points

- If the task book conflicts with a newer user message, follow the newer user message and update the task book to match.
- If the task book is too large for one safe iteration, split it only after explaining the split and recording the deferred items in the next task book.
- If a task is discovered to be obsolete, verify it against the current code and document why it is no longer needed before treating it as complete.
- If validation is impossible in the current environment, perform the strongest available substitute and record the limitation.

## Completion Checks

- The current task book was read, reviewed, and revised when needed.
- Every listed task is complete, explicitly deferred by user direction, or blocked for a concrete reason.
- The implementation was reviewed against the task book.
- Repository validation was run or a reason was recorded.
- A next task book was written or updated.
- The next task book includes a `Question` section for user input on the next direction and details.
- The final response summarizes the round and repeats the key Questions for the user.