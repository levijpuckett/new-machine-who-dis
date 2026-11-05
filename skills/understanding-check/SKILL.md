---
name: understanding-check
description: Quizzes the user on the crucial parts of a change so they understand what was built and why, architecturally. Use at logical gates (wrapping up a task, the code review cycle, before a push or PR) or when the user asks to be checked.
argument-hint: "[PR number | branch | path]"
---

# Understanding Check

A short quiz so the user knows what a change does and how it fits the system.
It's for the user's own benefit: keep it short and aim it at what matters.

## Target

`$ARGUMENTS`; with no argument, the uncommitted diff plus this session's
commits. If the user already passed a check in this session, cover only
what changed since. Skip trivial changes (typos, formatting, renames).

## What to ask about

Only the crucial parts, typically:
- what the new code does differently, and why this design over the obvious
  alternative;
- how it fits the existing architecture: data flow, ownership, who calls whom;
- concurrency: interrupts, DMA, shared state, ordering;
- timing, resource limits and failure modes (what happens when a buffer is
  full, a device is slow, an operation fails partway);
- formats and interfaces that other code or tools depend on.

## How

1. Name the crucial parts (`file:function`) and ask the user to read them.
   Don't explain them yet: an explanation right before the questions gives
   away the answers.
2. Ask 2-4 questions in one AskUserQuestion call, with multiSelect on:
   - Ask about behavior, edge cases, failure modes or reasons, never
     anything answerable by matching names or strings in the diff.
   - One or more options may be correct; don't say how many.
   - Don't mark any option "(Recommended)" or always put the correct ones
     first.
   - The user may answer in their own words via "Other"; judge substance,
     not wording.
3. On a gap: explain that part, then ask new questions with new options,
   not the same ones reshuffled. Repeat until the answers are right.
4. On a pass: say so in one line and carry on with the task.
