<!-- managed-by: francesco-z/ai-agents (AGENTS.md) — edit in the repo, not in ~/.claude -->

# Agent conventions

Vendor-neutral instructions for any coding agent working in this repo (and, once
`make install` has run, in every repo). `CLAUDE.md` and `GEMINI.md` are symlinks
to this file.

## Response style

- No preamble, no postamble, no restating the request. Answer first.
- Prose max ~6 lines unless I ask for detail. Code blocks and diffs are exempt —
  never truncate code to hit a length target.
- Don't summarize changes I can already see in the diff or in tool output.
- Don't narrate tool use while working ("Now I'll read...", "Let me check...").
- Instead, close a turn that used tools with **one compact reference line** of
  what was actually touched — no commentary:

  ```text
  ↳ read: install.sh, Makefile · edited: AGENTS.md · ran: make install
  ```

  One line. Names only, comma-separated, grouped by verb (read / edited /
  created / ran / searched). Omit it for turns that used no tools.
- Do keep, always: assumptions I should check, caveats, failing tests with their
  actual output, and anything that needs my decision. Brevity never trims these.

## Code style

- Comments only for non-obvious *why*. Match the existing density of the file
  you are editing.
- No docstrings on self-evident functions. Keep them where the language
  convention requires: exported Go identifiers, public Python APIs.
- No defensive `try`/`except`, retries, or logging I didn't ask for.
- No "improvements" outside the requested scope — mention them in one line
  instead.

## Minimal diffs

- Touch only the lines the change requires. Never re-indent, re-wrap, reorder,
  or reformat code you are not otherwise modifying — a reviewer must be able to
  read the diff as the change itself.
- Preserve the file's existing conventions even where they differ from your
  preference: indent width, quote style, import order, trailing commas,
  alignment, line length. Match the file, not your defaults.
- Don't let a formatter loose on a whole file to fix a few lines. If a
  project-wide formatter must run, say so and do it as a separate commit.
- Exceptions, both narrow: the surrounding code is genuinely unreadable (mixed
  tabs/spaces, broken indentation) and the fix is inseparable from the change;
  or the change already rewrites the clear majority of the file, so a consistent
  reformat costs the reviewer nothing. Say which exception applies in one line.

## Scope

- Do the task asked, in full. If part of it is blocked, finish the rest and say
  in one line what you left out and why.
- Repo safety gates (draft PRs only, no real-environment mutations, local/
  ephemeral UAT) are defined in `.claude/settings.json` and are never bypassed.
