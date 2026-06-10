---
name: appkit-session-report
description: Use when the user wants to analyze, summarize, or get a diagnostic of the current or a recent Claude Code session for this macOS project — session feedback, what happened during a build, where the agent got stuck, token/turn metrics, or a write-up to attach to a bug report. Runs the bundled analyze-session.py. User-invoked.
disable-model-invocation: true
---

# AppKit Session Report

## Overview

Generate a diagnostic report for a Claude Code session by running the **`analyze-session.py`** bundled with this skill — never by hand-parsing transcripts. It reads the session JSONL under `~/.claude/projects/…`, classifies turns, and emits a structured markdown report (metrics, skills, build analysis, stuck patterns, per-turn detail). User-invoked only (`disable-model-invocation: true`); the agent does not load it on its own.

> **Don't hand-write a session diagnostic.** The project ships a purpose-built analyzer. Re-deriving metrics by grepping the repo is slower, wrong, and — critically — skips the privacy guard below. Discover and run the script.

## Always pass `--output` (privacy + context safety)

```bash
python3 plugins/appkit/skills/appkit-session-report/analyze-session.py --output session-report.md
```

**Run it from the project directory** and **always pass `--output`.** Two reasons:
1. A bare run (no `--output`) prints the **entire unredacted report to stdout** — which dumps your verbatim prompts, paths, and any pasted secrets straight into the agent's context. `--output` writes it to a file instead.
2. `--output` is what fires the script's **stderr privacy banner**. Without it, the privacy notice never prints.

The analyzer also auto-selects the session by the current working directory (newest session whose recorded `cwd` matches). Run it elsewhere and it can silently analyze an unrelated session.

**Invocation forms:**

```bash
# Most-recent session for THIS project dir (the usual case) — always with --output
python3 .../analyze-session.py --output session-report.md
python3 .../analyze-session.py --session-id <uuid> --output session-report.md   # a specific session
python3 .../analyze-session.py --events-file <transcript.jsonl> --output report.md  # a transcript file directly
python3 .../analyze-session.py --skip-subagents --output session-report.md       # parent-only view
```

Requires **Python 3.10+** (stdlib only — no pip installs). **Claude Code only** — it does not support other harnesses and exits with a clear message if it can't find a session. Honors `$CLAUDE_SESSION_ID` when no `--session-id`/`--events-file` is given.

## Privacy — surface this to the user, every time

`analyze-session.py` embeds a **"Privacy and sensitivity"** section at the top of the report and prints a **PRIVACY NOTICE** banner to stderr (on `--output`). **Do not let that stay buried in script output the user may not have read.** When you report the findings, include a short privacy reminder in your own words — adapt this:

> ⚠️ **Before you share `session-report.md`** — it's your **unredacted** session transcript: file contents and paths the agent read/edited, your prompts verbatim (including any secrets you pasted), tool output, signing identities, and local `/Users/<you>/…` paths. Open it and read it end-to-end before attaching it to a public issue, posting it in chat, or sending it outside your org. Redact anything sensitive — or ask me to share just the high-level metrics instead of the file.

**Offer the summary, not the raw file.** If the user only needs the metrics (turns, tokens, skills, build success, stuck patterns), summarize the report and share *that* — and tell them that's what you're doing so they don't have to read the file to confirm it's safe. Only hand over the raw `session-report.md` after the user has acknowledged the privacy trade-off. This matters most for the "attach it to a GitHub issue" framing — that's exactly where an unredacted transcript leaks.

## Workflow

1. **Run the analyzer** with `--output session-report.md` (from the project dir).
2. **Read the report** and summarize the key findings for the user: turns / duration / tokens (incl. cache), which skills loaded and when, build success-vs-failure pattern, any stuck patterns or tooling issues.
3. **Surface the privacy reminder** (above) in your reply, and offer summary-over-raw.
4. **Add your own observations** — append a section: was the final app working? what's missing? code-quality notes? AppKit-specific suggestions (e.g. a `build-and-run.sh` rough edge, a skill gap) that would cut turns next time.

> **Filing a bug from the report? Base claims on what the report actually shows, and verify before filing.** The report describes what the agent *did*, not necessarily what's *broken* — a `--help` / research probe or a verification command (e.g. `xcrun altool --help`, `codesign --verify`) is **not** a build failure, and the per-turn tool summaries are truncated command text, not proof of a defect. Don't infer a tooling bug from a command string; confirm against the actual tool/skill/file first. The session's *subject* is the user's prompt and the work done, not whichever command happens to look alarming out of context.

## What the report covers

| Section | Details |
|---------|---------|
| Privacy and sensitivity | Unredacted-content warning, injected above Overview |
| Overview | Session ID, model, duration, parent turns, subagents, output + cache-read + cache-create tokens |
| Prompt | The first user request (truncated) |
| Turn Breakdown | Turns + output tokens by category (build-fix, code-edit, explore, subagent, …) |
| Skills | Which skills were invoked and on which turn (incl. inside subagents) |
| Subagents | Per-agent type / turns / duration / description |
| Build Analysis | Attempts (success/fail), whether `build-and-run.sh` was used, build errors per turn |
| Stuck Patterns | Repeated file reads (≥3×), build loops (≥3 consecutive fails), repeated DerivedData cleans |
| Turn Detail | Every turn with category, tokens, and tools — parent and each subagent shown separately |

Build detection is macOS-tuned (`xcodebuild`, `build-and-run.sh`, `tuist`, `swift build`); error extraction is Swift/Xcode-flavored (`error:`, `BUILD FAILED`, `linker command failed`, `code object is not signed`, …).

## When to use

- The user explicitly asks for a session report, session feedback, or "what happened" in this session.
- The user wants a diagnostic to attach to a bug report — **run the analyzer, then lead with the privacy reminder and offer the summary.**
