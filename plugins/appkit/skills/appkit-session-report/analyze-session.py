#!/usr/bin/env python3
"""
analyze-session.py — Analyze a Claude Code agent session from its on-disk
transcript and emit a structured markdown report for bug filing / review.

This is the AppKit analog of the WinUI `Analyze-Session.ps1`, narrowed to the
one harness Claude Code uses on macOS. It reads:

  ~/.claude/projects/<encoded-cwd>/<session-id>.jsonl

and, if present, the subagent transcripts under:

  ~/.claude/projects/<encoded-cwd>/<session-id>/subagents/agent-*.jsonl

Build detection is tuned for the macOS toolchain (xcodebuild / tuist /
BuildAndRun.sh), and Swift/xcodebuild error extraction replaces the WinUI
MSBuild/XAML patterns.

Usage:
  python3 analyze-session.py                               # most recent session for this cwd
  python3 analyze-session.py --session-id <uuid>
  python3 analyze-session.py --events-file transcript.jsonl
  python3 analyze-session.py --output session-report.md
  python3 analyze-session.py --skip-subagents
"""

from __future__ import annotations
import argparse, json, os, re, sys
from datetime import datetime
from pathlib import Path

# --------------------------------------------------------------------------- #
# Locating the transcript
# --------------------------------------------------------------------------- #

def projects_root() -> Path:
    return Path.home() / ".claude" / "projects"

def read_jsonl(path: Path) -> list[dict]:
    events = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return events

def first_cwd(path: Path) -> str | None:
    with open(path, "r", encoding="utf-8") as fh:
        for i, line in enumerate(fh):
            if i > 50:
                break
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if obj.get("cwd"):
                return str(obj["cwd"])
    return None

def find_session_by_id(sid: str) -> Path | None:
    root = projects_root()
    if not root.exists():
        return None
    for p in root.rglob(f"{sid}.jsonl"):
        if p.parent.name != "subagents":
            return p
    return None

def find_latest_session(prefer_cwd: str | None) -> Path | None:
    root = projects_root()
    if not root.exists():
        return None
    candidates = [
        p for p in root.rglob("*.jsonl")
        if p.parent.name != "subagents" and p.parent.parent.name == "projects"
    ]
    if not candidates:
        return None
    candidates.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    if prefer_cwd:
        want = prefer_cwd.rstrip("/")
        for c in candidates:
            fc = first_cwd(c)
            if fc and fc.rstrip("/") == want:
                return c
    return candidates[0]

# --------------------------------------------------------------------------- #
# Tool-name normalization (Claude Code raw names -> friendly verbs)
# --------------------------------------------------------------------------- #

TOOL_NAME_MAP = {
    "Read": "view", "Edit": "edit", "Write": "create", "Glob": "glob",
    "Grep": "grep", "Bash": "shell", "Skill": "skill", "Agent": "agent",
    "Task": "agent", "WebFetch": "web_fetch", "WebSearch": "web_search",
    "NotebookEdit": "edit", "TodoWrite": "todo", "AskUserQuestion": "ask_user",
}

def norm_tool(name: str) -> str:
    return TOOL_NAME_MAP.get(name, (name or "").lower())

# --------------------------------------------------------------------------- #
# Error extraction (Swift / xcodebuild / shell)
# --------------------------------------------------------------------------- #

_ERR_TRIGGER = re.compile(r"error:|BUILD FAILED|fatal error|Command .* failed|"
                          r"linker command failed|code object is not signed|"
                          r"Undefined symbol|cannot find", re.IGNORECASE)

def error_summary(text: str | None):
    if not text:
        return (False, [])
    if not _ERR_TRIGGER.search(text):
        return (False, [])
    out = []
    for line in text.splitlines():
        s = line.strip()
        if not _ERR_TRIGGER.search(s):
            continue
        m = re.search(r"error:\s*(.+)", s)
        if m:
            out.append(m.group(1).strip()[:140])
        elif "BUILD FAILED" in s:
            out.append("** BUILD FAILED **")
        elif re.search(r"Command (\S+) failed", s):
            out.append(re.search(r"Command (\S+) failed", s).group(0))
        elif "linker command failed" in s:
            out.append("linker command failed")
        else:
            out.append(s[:140])
        if len(out) >= 5:
            break
    # de-dupe preserving order
    seen, uniq = set(), []
    for e in out:
        if e not in seen:
            seen.add(e); uniq.append(e)
    return (True, uniq)

# --------------------------------------------------------------------------- #
# Parsing
# --------------------------------------------------------------------------- #

def extract_prompt(events: list[dict]) -> str:
    for ev in events:
        if ev.get("type") != "user" or ev.get("isMeta") or ev.get("isSidechain"):
            continue
        content = ev.get("message", {}).get("content")
        cand = None
        if isinstance(content, str):
            cand = content
        elif isinstance(content, list):
            has_tool_result = any(b.get("type") == "tool_result" for b in content)
            texts = [b.get("text", "") for b in content if b.get("type") == "text"]
            if not has_tool_result and texts:
                cand = "\n".join(texts)
        if not cand:
            continue
        s = cand.strip()
        if re.match(r"^<(local-)?command-(name|message|args|stdout)>", s):
            continue
        if s.startswith("<local-command-caveat>"):
            continue
        return cand
    return "(no prompt found)"

def parse_session(path: Path, is_subagent: bool = False, include_subagents: bool = True) -> dict:
    events = read_jsonl(path)
    prompt = extract_prompt(events)
    sid = events[0].get("sessionId") if events else None
    sid = sid or path.stem

    first_assistant = next((e for e in events if e.get("type") == "assistant"), {})
    model = first_assistant.get("message", {}).get("model", "(unknown)")

    # duration
    times = []
    for ev in events:
        ts = ev.get("timestamp")
        if ts:
            try:
                times.append(datetime.fromisoformat(ts.replace("Z", "+00:00")))
            except ValueError:
                pass
    duration_min = round((times[-1] - times[0]).total_seconds() / 60, 1) if len(times) >= 2 else 0.0

    # tool_results keyed by tool_use_id
    tool_results: dict[str, dict] = {}
    for ev in events:
        if ev.get("type") == "user" and isinstance(ev.get("message", {}).get("content"), list):
            for block in ev["message"]["content"]:
                if block.get("type") == "tool_result":
                    c = block.get("content")
                    txt = ""
                    if isinstance(c, str):
                        txt = c
                    elif isinstance(c, list):
                        txt = "\n".join(i.get("text", "") for i in c if i.get("type") == "text")
                    tool_results[str(block.get("tool_use_id"))] = {
                        "text": txt, "is_error": block.get("is_error") is True
                    }

    turns = []
    turn_num = 0
    for ev in events:
        if ev.get("type") != "assistant":
            continue
        if not is_subagent and ev.get("isSidechain"):
            continue
        turn_num += 1
        usage = ev.get("message", {}).get("usage", {}) or {}
        turn = {
            "n": turn_num,
            "tools": [],
            "out_tokens": int(usage.get("output_tokens") or 0),
            "cache_read": int(usage.get("cache_read_input_tokens") or 0),
            "cache_create": int(usage.get("cache_creation_input_tokens") or 0),
            "skills": [],
            "agents": [],
            "category": "other",
        }
        content = ev.get("message", {}).get("content")
        if isinstance(content, list):
            for block in content:
                if block.get("type") != "tool_use":
                    continue
                call_id = str(block.get("id"))
                args = block.get("input", {}) or {}
                nname = norm_tool(block.get("name", ""))
                tool = {"name": nname, "args": args, "error": False, "errs": []}
                if nname == "skill" and args.get("skill"):
                    turn["skills"].append(str(args["skill"]))
                if nname == "agent":
                    turn["agents"].append(str(args.get("subagent_type", "general-purpose")))
                tr = tool_results.get(call_id)
                if tr:
                    has_err, errs = error_summary(tr["text"])
                    if tr["is_error"] or has_err:
                        tool["error"] = True
                        tool["errs"] = errs
                turn["tools"].append(tool)
        turns.append(turn)

    subagents = []
    if include_subagents and not is_subagent:
        sub_dir = path.parent / path.stem / "subagents"
        if sub_dir.exists():
            for af in sorted(sub_dir.glob("agent-*.jsonl")):
                agent_id = af.stem.replace("agent-", "")
                meta = {}
                meta_path = af.with_name(f"agent-{agent_id}.meta.json")
                if meta_path.exists():
                    try:
                        meta = json.loads(meta_path.read_text(encoding="utf-8"))
                    except Exception:
                        meta = {}
                sub = parse_session(af, is_subagent=True, include_subagents=False)
                subagents.append({
                    "id": agent_id,
                    "type": meta.get("agentType", "(unknown)"),
                    "desc": meta.get("description", ""),
                    "turns": sub["turns"],
                    "duration": sub["duration_min"],
                })

    return {
        "session_id": sid, "model": model, "duration_min": duration_min,
        "prompt": prompt, "turns": turns, "subagents": subagents,
    }

# --------------------------------------------------------------------------- #
# Categorization (macOS build tooling aware)
# --------------------------------------------------------------------------- #

def _is_shell(t): return t["name"] == "shell"
def _cmd(t): return (t["args"].get("command") or "") if _is_shell(t) else ""

RE_HELPER = re.compile(r"build-and-run\.sh|build-and-run\b|BuildAndRun")
RE_BUILD = re.compile(r"\bxcodebuild\b|build-and-run|BuildAndRun|\btuist\b|\bswift build\b")
RE_RUN   = re.compile(r"\bopen\s+.*\.app|(?:build-and-run|BuildAndRun)(?!.*--skip-run)|Contents/MacOS/")
RE_DIAG  = re.compile(r"xcresulttool|-showBuildSettings|DiagnosticReports|"
                      r"log stream|grep .*error|DerivedData|rm -rf .*build|codesign --verify|spctl")
RE_SCAFFOLD = re.compile(r"tuist generate|tuist install|mkdir ")
RE_GIT  = re.compile(r"\bgit\b")

def categorize(turn: dict) -> str:
    names = [t["name"] for t in turn["tools"]]
    has_skill = bool(turn["skills"])
    has_build = any(_is_shell(t) and RE_BUILD.search(_cmd(t)) for t in turn["tools"])
    has_build_err = any(t["error"] and _is_shell(t) and RE_BUILD.search(_cmd(t)) for t in turn["tools"])
    has_run = any(_is_shell(t) and RE_RUN.search(_cmd(t)) for t in turn["tools"])
    has_git = any(_is_shell(t) and RE_GIT.search(_cmd(t)) for t in turn["tools"])
    is_diag = any(_is_shell(t) and RE_DIAG.search(_cmd(t)) for t in turn["tools"])
    has_scaffold = any(RE_SCAFFOLD.search(_cmd(t)) for t in turn["tools"])
    has_create = "create" in names
    has_edit = "edit" in names
    has_view = "view" in names
    has_agent = "agent" in names

    if has_skill and len(names) <= 2:       return "skill-load"
    if has_git and not has_build:           return "git"
    if has_build and has_build_err:         return "build-fix"
    if has_build and not has_build_err:     return "build-ok"
    if has_run:                             return "run"
    if is_diag and not has_edit:            return "diagnosing"
    if has_scaffold:                        return "scaffold"
    if has_agent:                           return "subagent"
    if has_create and not has_edit:         return "code-create"
    if has_edit:                            return "code-edit"
    if has_view and not has_edit and not has_create: return "explore"
    if not names:                           return "thinking"
    return "other"

# --------------------------------------------------------------------------- #
# Rendering
# --------------------------------------------------------------------------- #

CATEGORY_LABELS = {
    "skill-load": "Skill loading", "explore": "Reading/exploring",
    "scaffold": "Scaffolding", "code-create": "Creating files",
    "code-edit": "Editing code", "build-ok": "Build (success)",
    "build-fix": "Build (failed)", "run": "Running app", "git": "Git operations",
    "thinking": "Thinking (no tools)", "diagnosing": "Diagnosing errors",
    "subagent": "Subagent dispatch", "other": "Other",
}

def tool_list(turn: dict) -> str:
    parts = []
    for t in turn["tools"]:
        err = " ❌" if t["error"] else ""
        summ = ""
        a = t["args"]
        if t["name"] == "shell":
            summ = (a.get("command") or "").splitlines()[0][:60]
        elif a.get("path") or a.get("file_path"):
            summ = os.path.basename(a.get("path") or a.get("file_path"))
        elif t["name"] == "skill":
            summ = str(a.get("skill", ""))
        elif t["name"] == "agent":
            summ = str(a.get("subagent_type", ""))
        elif a.get("pattern"):
            summ = str(a["pattern"])
        parts.append(f"{t['name']}({summ}){err}" if summ else f"{t['name']}{err}")
    skills = f" [skill: {','.join(turn['skills'])}]" if turn["skills"] else ""
    return ", ".join(parts) + skills

def render(parsed: dict, include_subagents: bool) -> str:
    all_turns = list(parsed["turns"])
    if include_subagents:
        for sa in parsed["subagents"]:
            all_turns += sa["turns"]

    build_ok = sum(1 for t in all_turns if t["category"] == "build-ok")
    build_fix = sum(1 for t in all_turns if t["category"] == "build-fix")
    attempts = build_ok + build_fix

    # build-and-run.sh helper vs raw xcodebuild (tolerates the legacy BuildAndRun casing)
    used_bar = any(_is_shell(t) and RE_HELPER.search(_cmd(t)) for tn in all_turns for t in tn["tools"])
    raw_xcb = any(_is_shell(t) and re.search(r"\bxcodebuild\b", _cmd(t)) and not RE_HELPER.search(_cmd(t))
                  for tn in all_turns for t in tn["tools"])
    if used_bar and not raw_xcb:
        build_status = "Used build-and-run.sh for all builds"
    elif used_bar and raw_xcb:
        build_status = "Mixed: raw xcodebuild and build-and-run.sh"
    elif raw_xcb:
        build_status = "NOT USED: raw xcodebuild only, never used build-and-run.sh"
    else:
        build_status = "No build commands detected"

    # build errors
    build_errors = []
    for t in all_turns:
        for tool in t["tools"]:
            if tool["error"] and _is_shell(tool) and RE_BUILD.search(_cmd(tool)) and tool["errs"]:
                build_errors.append((t["n"], tool["errs"]))

    # skills
    skill_timeline = []
    for t in parsed["turns"]:
        for s in t["skills"]:
            skill_timeline.append((t["n"], s, "parent"))
    for sa in parsed["subagents"]:
        for t in sa["turns"]:
            for s in t["skills"]:
                skill_timeline.append((t["n"], s, f"subagent:{sa['type']}"))

    # token totals
    out_tok = sum(t["out_tokens"] for t in all_turns)
    cr_tok = sum(t["cache_read"] for t in all_turns)
    cc_tok = sum(t["cache_create"] for t in all_turns)

    # category table
    cat_counts = {}
    for t in all_turns:
        c = t["category"]
        e = cat_counts.setdefault(c, {"turns": 0, "tokens": 0})
        e["turns"] += 1; e["tokens"] += t["out_tokens"]
    cat_rows = sorted(cat_counts.items(), key=lambda kv: kv[1]["turns"], reverse=True)

    # stuck patterns
    stuck = []
    reads = {}
    for t in all_turns:
        for tool in t["tools"]:
            if tool["name"] == "view":
                p = tool["args"].get("path") or tool["args"].get("file_path")
                if p:
                    f = os.path.basename(p)
                    reads[f] = reads.get(f, 0) + 1
    excessive = [(f, n) for f, n in reads.items() if n >= 3]
    if excessive:
        stuck.append("Repeated file reads: " + ", ".join(f"{f} ({n}x)" for f, n in excessive))
    consec = mx = 0
    for t in all_turns:
        if t["category"] == "build-fix":
            consec += 1; mx = max(mx, consec)
        elif t["category"] == "build-ok":
            consec = 0
    if mx >= 3:
        stuck.append(f"Build loop: {mx} consecutive build failures before success")
    cleans = sum(1 for t in all_turns
                 for tool in t["tools"] if re.search(r"rm -rf .*build|DerivedData", _cmd(tool)))
    if cleans >= 2:
        stuck.append(f"Cleaned build/DerivedData {cleans}x (suggests stale build state)")

    # ----- markdown -----
    md = []
    md.append("# Session Analysis Report\n")
    md.append("## Overview\n")
    md.append("| Field | Value |")
    md.append("|-------|-------|")
    md.append("| Harness | Claude Code |")
    md.append(f"| Session ID | `{parsed['session_id']}` |")
    md.append(f"| Model | {parsed['model']} |")
    md.append(f"| Duration | {parsed['duration_min']} min |")
    md.append(f"| Turns (parent) | {len(parsed['turns'])} |")
    if include_subagents and parsed["subagents"]:
        sub_turns = sum(len(sa["turns"]) for sa in parsed["subagents"])
        md.append(f"| Subagents | {len(parsed['subagents'])} ({sub_turns} turns) |")
    md.append(f"| Output tokens (combined) | {out_tok:,} |")
    md.append(f"| Cache read tokens | {cr_tok:,} |")
    md.append(f"| Cache create tokens | {cc_tok:,} |")
    md.append("")

    md.append("## Prompt\n")
    p = parsed["prompt"]
    p = p[:500] + "..." if len(p) > 500 else p
    md.append("```"); md.append(p); md.append("```"); md.append("")

    md.append("## Turn Breakdown\n")
    if include_subagents and parsed["subagents"]:
        md.append(f"_Combined parent + {len(parsed['subagents'])} subagent transcript(s)._\n")
    md.append("| Category | Turns | Output Tokens |")
    md.append("|----------|------:|--------------:|")
    for cat, e in cat_rows:
        md.append(f"| {CATEGORY_LABELS.get(cat, cat)} | {e['turns']} | {e['tokens']:,} |")
    md.append("")

    md.append("## Skills\n")
    if skill_timeline:
        md.append("**Invoked:**")
        for n, s, origin in skill_timeline:
            tag = "" if origin == "parent" else f" _(in {origin})_"
            md.append(f"- Turn {n}: `{s}`{tag}")
    else:
        md.append("_No skills were invoked during this session._")
    md.append("")

    if include_subagents and parsed["subagents"]:
        md.append("## Subagents\n")
        md.append("| Agent ID | Type | Turns | Duration | Description |")
        md.append("|---|---|---:|---:|---|")
        for sa in parsed["subagents"]:
            d = sa["desc"][:60] + "..." if len(sa["desc"]) > 60 else sa["desc"]
            md.append(f"| `{sa['id']}` | {sa['type']} | {len(sa['turns'])} | {sa['duration']} min | {d} |")
        md.append("")

    md.append("## Build Analysis\n")
    md.append(f"- **Attempts:** {attempts} ({build_ok} success, {build_fix} failed)")
    md.append(f"- **build-and-run.sh:** {build_status}")
    md.append("")
    if build_errors:
        md.append("**Build errors encountered:**\n")
        for n, errs in build_errors:
            md.append(f"Turn {n}:")
            for e in errs:
                md.append(f"- `{e}`")
        md.append("")

    if stuck:
        md.append("## Stuck Patterns\n")
        for s in stuck:
            md.append(f"- {s}")
        md.append("")

    md.append("## Turn Detail\n")
    md.append("_Parent session._\n")
    md.append("| # | Category | Tokens | Tools |")
    md.append("|--:|----------|-------:|-------|")
    for t in parsed["turns"]:
        md.append(f"| {t['n']} | {t['category']} | {t['out_tokens']:,} | {tool_list(t)} |")
    md.append("")
    if include_subagents:
        for sa in parsed["subagents"]:
            md.append(f"_Subagent `{sa['type']}` (id `{sa['id']}`)._\n")
            md.append("| # | Category | Tokens | Tools |")
            md.append("|--:|----------|-------:|-------|")
            for t in sa["turns"]:
                md.append(f"| {t['n']} | {t['category']} | {t['out_tokens']:,} | {tool_list(t)} |")
            md.append("")

    return "\n".join(md)

# --------------------------------------------------------------------------- #
# Privacy notice (kept in sync with SKILL.md)
# --------------------------------------------------------------------------- #

PRIVACY = """## Privacy and sensitivity — read before sharing this file

**This report was generated from your live agent session and was NOT redacted.** Depending on what your session involved, it can include:

- File contents and paths the agent read or edited (source, configuration, secrets accidentally pasted into prompts, internal URLs, customer data).
- Your prompts verbatim — including any credentials, tokens, identifiers, or proprietary information you typed.
- Tool output — `git` history, environment values echoed by failing commands, build logs containing machine names and `/Users/<you>/…` paths, signing identities, and crash traces.
- Error messages quoting source code or stack traces from third-party libraries.

**You are responsible for the contents of this file.** Open it in your editor and read it end-to-end before attaching it to a public issue, posting it in chat, or sending it outside your organization. Redact anything sensitive (paths, names, secrets, signing identities, business logic). When in doubt, share excerpts rather than the whole file, or ask the agent to summarize the metrics instead.
"""

def insert_privacy(report: str) -> str:
    lines = report.split("\n")
    idx = next((i for i, l in enumerate(lines) if l.startswith("## Overview")), 1)
    return "\n".join(lines[:idx] + [PRIVACY, ""] + lines[idx:])

# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #

def main() -> int:
    ap = argparse.ArgumentParser(description="Analyze a Claude Code session transcript.")
    ap.add_argument("--session-id")
    ap.add_argument("--events-file")
    ap.add_argument("--output")
    ap.add_argument("--skip-subagents", action="store_true")
    args = ap.parse_args()

    if args.events_file:
        path = Path(args.events_file)
        if not path.exists():
            print(f"Events file not found: {path}", file=sys.stderr); return 1
    elif args.session_id:
        path = find_session_by_id(args.session_id)
        if not path:
            print(f"Session id '{args.session_id}' not found under {projects_root()}", file=sys.stderr)
            return 1
    else:
        env_sid = os.environ.get("CLAUDE_SESSION_ID")
        path = (find_session_by_id(env_sid) if env_sid else None) or find_latest_session(os.getcwd())
        if not path:
            print(f"No Claude Code sessions found under {projects_root()}", file=sys.stderr)
            print("If you use a different agent harness, this analyzer doesn't support it yet.", file=sys.stderr)
            return 1

    include_subagents = not args.skip_subagents
    parsed = parse_session(path, include_subagents=include_subagents)
    for t in parsed["turns"]:
        t["category"] = categorize(t)
    for sa in parsed["subagents"]:
        for t in sa["turns"]:
            t["category"] = categorize(t)

    report = insert_privacy(render(parsed, include_subagents and bool(parsed["subagents"])))

    if args.output:
        Path(args.output).write_text(report, encoding="utf-8")
        print(f"\nReport saved to: {args.output}")
        banner = "=" * 64
        for line in (banner,
                     f" PRIVACY NOTICE — READ BEFORE SHARING {args.output}",
                     banner,
                     " This report contains your unredacted session transcript:",
                     "   * file contents and paths the agent read or edited",
                     "   * your prompts verbatim (including any secrets you pasted)",
                     "   * tool output, error messages, local paths, signing identities",
                     "",
                     " You are responsible for what you share. Open the file and read",
                     " it end-to-end before posting it publicly. Redact anything sensitive.",
                     banner):
            print(line, file=sys.stderr)
    else:
        print(report)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
