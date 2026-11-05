---
name: plan-studio
description: >
  Interactive browser-based plan review with click-to-comment. MUST be used at
  the end of EVERY plan-mode session: after the plan file is finalized and
  BEFORE calling ExitPlanMode, run this review loop so the user can comment on
  and approve the rendered plan in their browser. MUST also be used in place
  of the terminal AskUserQuestion tool for any clarifying question raised
  during plan mode, whether before drafting the plan or while refining it.
  Also invocable manually as /plan-studio <path-to-markdown-file> to review
  any markdown document.
argument-hint: "[path to a markdown file to review]"
allowed-tools: Bash(python3 ${CLAUDE_SKILL_DIR}/scripts/plan_studio_server.py:*), Read
---

# Plan Studio: interactive browser review loop

Serve the plan as an annotatable HTML page in the user's browser. The user
clicks blocks or selects text to leave numbered comments, then clicks **Send
comments** (you revise and re-serve) or **Approve plan** (you proceed). Loop
until approved.

## Setup

- `PLAN` = the plan file path. In plan mode this is the harness plan file
  (under `~/.claude/plans/`). When invoked manually as `/plan-studio <path>`,
  it is that path.
- `OUT_DIR` = the session scratchpad directory.
- Round counter `R` = 1. `PORT` = 7357 initially.

## Clarifying questions (pre-plan or mid-plan)

Any time in plan mode you would otherwise ask via AskUserQuestion — before
drafting the plan, or while refining it — ask them in the same browser
session instead, so the user never has to switch between terminal and
browser. Only do this when you have at least one real question — otherwise
skip straight to drafting (or back to the review loop) below; the server
refuses to start with zero questions, and there is no rendered state for "no
questions".

1. Write the questions as a JSON array to `$OUT_DIR/questions.json`, same
   shape as AskUserQuestion's `questions` parameter: `{question, header,
   options: [{label, description}], multiSelect}`.
2. Launch the server in questions mode with `run_in_background: true`:

   ```
   python3 ${CLAUDE_SKILL_DIR}/scripts/plan_studio_server.py \
       --questions "$OUT_DIR/questions.json" \
       --out "$OUT_DIR/questions-answers.json" --port $PORT
   ```

   Do not pass a plan positional or `--round`/`--summary` — they're
   review-mode-only.
3. Wait for it to exit (same non-polling behavior as the loop below), then
   read the out file and branch on `status`:
   - **`answered`** → For each entry in `answers`, `selected` holds the
     chosen option label(s) and `other` (if non-null) is free text the user
     typed in addition to any `selected` labels — fold both into the plan
     you draft or revise. Then proceed straight to **round 1 of the loop
     below** (or the next round, if this was a mid-plan question), reusing
     the same `$PORT` and passing `--no-open`: the user's browser tab is
     still open and will auto-reload into the plan review page once that
     server binds the port, with no need to reopen a browser.
   - **`abandoned`** → Tell the user, then fall back to the terminal
     AskUserQuestion tool for the same questions.

This step is a one-shot exchange, not a revision round — it does not count
against the review loop's 8-round safety valve below.

## The loop

1. **Launch the review server** with the Bash tool using `run_in_background: true`:

   ```
   python3 ${CLAUDE_SKILL_DIR}/scripts/plan_studio_server.py "$PLAN" \
       --out "$OUT_DIR/plan-comments-r$R.json" --port $PORT --round $R
   ```

   Add `--no-open` when `R > 1` (the user's existing browser tab auto-reloads
   for the new round; only round 1 opens a browser).

   When `R > 1`, also pass `--summary "$OUT_DIR/plan-changes-r$R.md"`, a
   markdown file you write BEFORE relaunching, with one bullet per previous
   comment number describing how you addressed it (or why you didn't). It is
   shown as a "What changed" banner above the plan, so the user doesn't have
   to re-scan for their changes.

   The server prints a `PLAN_STUDIO: starting ... port=NNNN` line; if the
   port differs from what you passed (another instance held it), use the
   printed port for ALL subsequent rounds; the tab auto-reload depends on the
   port staying the same.

   Tell the user in the terminal: the plan is open in their browser at the
   printed URL, and you are waiting for their comments or approval.

2. **Wait for the background task to exit** (it exits when the user acts, or
   after ~3 minutes if they close the tab). Do not poll; the harness notifies
   you when it exits.

3. **On exit**: if the exit code is nonzero or the `--out` file is missing,
   fall back to normal terminal plan review; do not loop. Otherwise Read the
   out file and branch on its `"status"`:

   - **`approved`** → Surface any parting `general_comments`/`comments` to the
     user as non-blocking notes. In plan mode: call ExitPlanMode. Manual mode:
     report that the document was approved.

   - **`comments`** → For EACH numbered comment, revise the plan file to
     address it, then briefly summarize in the terminal what you changed per
     comment number, and write the same per-comment summary to the
     `--summary` file for the next round. Locate each comment's target using its `quote` plus
     `heading_context`. IMPORTANT: `quote` is *rendered* text: markdown
     markers are stripped (`**bold**` appears as `bold`, code blocks lose
     their fences, list markers are gone). Match it semantically against the
     plan source, not with exact string search. `heading_context` (e.g.
     `## Steps > ### Step 2`) disambiguates duplicate quotes; for
     `type: "selection"` comments, `prefix`/`suffix` give surrounding text.
     Also apply `general_comments` holistically. Then `R += 1` and go to
     step 1 (with `--no-open`).

   - **`abandoned`** → The review tab appears closed (`reason` says why).
     Tell the user, present the plan in the terminal instead, and proceed
     with the normal terminal review flow.

4. **Safety valve**: after 8 rounds, stop looping and fall back to terminal
   review. Never overwrite a previous round's out file; the per-round `-rN`
   suffix keeps the history auditable.

## Notes

- The server binds 127.0.0.1 only and makes zero external requests.
- If the user says the browser never opened, give them the printed URL to
  open manually; the server waits up to 5 minutes for the first page load.
