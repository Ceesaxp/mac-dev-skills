#!/usr/bin/env swift
//
// analyze-session.swift — Analyze a Claude Code agent session from its on-disk
// transcript and emit a structured markdown report for bug filing / review.
//
// Single-file hashbang Swift port of analyze-session.py. Foundation only.
// This is a fidelity port: the Python source is the spec; output is byte-identical.
//
// JSON layer: the transcript is modelled with Codable and decoded via
// JSONDecoder. Most shapes use synthesized Decodable (event envelope, Usage,
// Message); the genuinely-dynamic tool `input` / tool_result `content` payloads
// use a recursive `JSONValue` enum with a custom decoder. ContentBlock is
// decoded on its `type` discriminator with an `.other` catch-all so unknown
// block types never throw. Small wrapper types replicate Python's lenient
// truthiness (isMeta/isSidechain/is_error) and str()-stringification (cwd, ids).
//

import Foundation

// --------------------------------------------------------------------------- //
// JSONValue — recursive model for genuinely-dynamic payloads.
//
// Decode order is bool -> int -> double -> string -> array -> object. Unlike
// NSNumber (which conflates `true` with `1`), JSONDecoder cleanly distinguishes
// a JSON boolean from a JSON number, so trying Bool first is safe and exact.
// --------------------------------------------------------------------------- //

indirect enum JSONValue: Decodable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "Unsupported JSON value")
        }
    }

    // The genuine string value, or nil for any non-string.
    var asString: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    // Object/array member access; nil for non-containers or missing keys.
    subscript(_ key: String) -> JSONValue? {
        if case let .object(o) = self { return o[key] }
        return nil
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    var objectValue: [String: JSONValue]? {
        if case let .object(o) = self { return o }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case let .array(a) = self { return a }
        return nil
    }

    // Python str(x) over a JSON value reachable from a dict. None -> "None",
    // strings pass through, everything else uses a repr-ish form. Used for ids
    // and skill/agent names where Python applies str().
    var pyStr: String {
        switch self {
        case .null: return "None"
        case let .bool(b): return b ? "True" : "False"
        case let .int(i): return String(i)
        case let .double(d): return "\(d)"
        case let .string(s): return s
        case let .array(a): return "\(a)"
        case let .object(o): return "\(o)"
        }
    }
}

// --------------------------------------------------------------------------- //
// ContentBlock — decoded on the `type` discriminator, with an `.other`
// catch-all so unknown block types are tolerated (forward-compat).
// --------------------------------------------------------------------------- //

enum ContentBlock: Decodable {
    case text(String)
    case toolUse(id: JSONValue?, name: String?, input: JSONValue)
    case toolResult(toolUseId: JSONValue?, content: JSONValue?, isError: Truthy)
    case thinking
    case other(String)

    private enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? c.decode(String.self, forKey: .type)) ?? ""
        switch type {
        case "text":
            let t = (try? c.decode(String.self, forKey: .text)) ?? ""
            self = .text(t)
        case "tool_use":
            let id = try? c.decode(JSONValue.self, forKey: .id)
            let name = try? c.decode(String.self, forKey: .name)
            let input = (try? c.decode(JSONValue.self, forKey: .input)) ?? .object([:])
            self = .toolUse(id: id, name: name, input: input)
        case "tool_result":
            let tid = try? c.decode(JSONValue.self, forKey: .toolUseId)
            let content = try? c.decode(JSONValue.self, forKey: .content)
            let isErr = (try? c.decode(Truthy.self, forKey: .isError)) ?? Truthy(false)
            self = .toolResult(toolUseId: tid, content: content, isError: isErr)
        case "thinking":
            self = .thinking
        default:
            self = .other(type)
        }
    }
}

// --------------------------------------------------------------------------- //
// Truthy — lenient decode of a value that appears as bool | number | null.
// Mirrors Python's `if obj.get(x)` truthiness. JSONDecoder cleanly separates
// Bool from Int, so this is simpler than the NSNumber-or-Bool double-check.
// --------------------------------------------------------------------------- //

struct Truthy: Decodable {
    let value: Bool
    init(_ v: Bool) { self.value = v }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            value = false
        } else if let b = try? c.decode(Bool.self) {
            value = b
        } else if let i = try? c.decode(Int.self) {
            value = i != 0
        } else if let d = try? c.decode(Double.self) {
            value = d != 0
        } else {
            value = false
        }
    }
}

// --------------------------------------------------------------------------- //
// MessageContent — `content` is either a JSON string or an array of blocks.
// Custom decode tries the array form first, then the string form.
// --------------------------------------------------------------------------- //

enum MessageContent: Decodable {
    case string(String)
    case array([ContentBlock])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let arr = try? c.decode([ContentBlock].self) {
            self = .array(arr)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else {
            self = .string("")
        }
    }

    var stringValue: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    var arrayValue: [ContentBlock]? {
        if case let .array(a) = self { return a }
        return nil
    }
}

// --------------------------------------------------------------------------- //
// Usage / Message / Event — stable shapes, synthesized Decodable. The
// synthesized Decodable for Usage silently ignores the other ~7 usage keys;
// optional fields tolerate absence. CodingKeys map the snake_case JSON.
// --------------------------------------------------------------------------- //

struct Usage: Decodable {
    let output_tokens: Int?
    let cache_read_input_tokens: Int?
    let cache_creation_input_tokens: Int?
}

struct Message: Decodable {
    let model: String?
    let usage: Usage?
    let content: MessageContent?
}

struct Event: Decodable {
    let type: String?
    let sessionId: String?
    let timestamp: String?
    let cwd: CwdString?
    let isMeta: Truthy?
    let isSidechain: Truthy?
    let message: Message?
}

// cwd: Python keeps a non-empty string as-is, else str()s a truthy non-null
// value. Models that exact behaviour. A JSON null decodes to .none here because
// the field itself is optional in Event; but a present JSON null still needs to
// be distinguishable from a string, so we decode through a wrapper that records
// whether the underlying value was a usable string or a stringified other.
struct CwdString: Decodable {
    let raw: JSONValue
    init(from decoder: Decoder) throws {
        raw = try JSONValue(from: decoder)
    }
    // The cwd resolved per Python firstCwd semantics: non-empty string, or the
    // str() of a truthy non-null value; nil otherwise.
    var resolved: String? {
        switch raw {
        case .null:
            return nil
        case let .string(s):
            return s.isEmpty ? nil : s
        default:
            return raw.pyStr
        }
    }
}

// --------------------------------------------------------------------------- //
// Number formatting — match Python f"{n:,}" and f"{round(x,1)}".
// --------------------------------------------------------------------------- //

func grouped(_ n: Int) -> String {
    let neg = n < 0
    var s = String(abs(n))
    var out = ""
    var count = 0
    for ch in s.reversed() {
        if count != 0 && count % 3 == 0 { out.append(",") }
        out.append(ch)
        count += 1
    }
    s = String(out.reversed())
    return neg ? "-" + s : s
}

// f"{round(x,1)}" is byte-identical to f"{x:.1f}" for these ranges (both
// correctly-rounded, round-half-to-even via the C library).
func dur(_ x: Double) -> String {
    return String(format: "%.1f", x)
}

// --------------------------------------------------------------------------- //
// JSON decoding helpers
// --------------------------------------------------------------------------- //

let jsonDecoder = JSONDecoder()

// Decode a single transcript line into an Event; nil if the line is not a JSON
// object that decodes (per-line robustness: a bad line is skipped, not fatal).
func decodeEvent(_ line: String) -> Event? {
    guard let d = line.data(using: .utf8) else { return nil }
    return try? jsonDecoder.decode(Event.self, from: d)
}

// --------------------------------------------------------------------------- //
// Locating the transcript
// --------------------------------------------------------------------------- //

func projectsRoot() -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".claude").appendingPathComponent("projects")
}

func readJsonl(_ path: URL) -> [Event] {
    var events: [Event] = []
    guard let data = try? String(contentsOf: path, encoding: .utf8) else { return events }
    for rawLine in data.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { continue }
        if let ev = decodeEvent(line) {
            events.append(ev)
        }
    }
    return events
}

func firstCwd(_ path: URL) -> String? {
    guard let content = try? String(contentsOf: path, encoding: .utf8) else { return nil }
    var i = 0
    for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
        if i > 50 { break }
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        i += 1
        if line.isEmpty { continue }
        guard let ev = decodeEvent(line) else { continue }
        if let resolved = ev.cwd?.resolved {
            return resolved
        }
    }
    return nil
}

func findSessionById(_ sid: String) -> URL? {
    let root = projectsRoot()
    let fm = FileManager.default
    if !fm.fileExists(atPath: root.path) { return nil }
    guard let en = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
    for case let url as URL in en {
        if url.lastPathComponent == "\(sid).jsonl" {
            if url.deletingLastPathComponent().lastPathComponent != "subagents" {
                return url
            }
        }
    }
    return nil
}

func findLatestSession(preferCwd: String?) -> URL? {
    let root = projectsRoot()
    let fm = FileManager.default
    if !fm.fileExists(atPath: root.path) { return nil }
    guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
    var candidates: [URL] = []
    for case let url as URL in en {
        guard url.pathExtension == "jsonl" else { continue }
        let parent = url.deletingLastPathComponent()
        if parent.lastPathComponent == "subagents" { continue }
        if parent.deletingLastPathComponent().lastPathComponent != "projects" { continue }
        candidates.append(url)
    }
    if candidates.isEmpty { return nil }
    func mtime(_ u: URL) -> TimeInterval {
        let v = try? u.resourceValues(forKeys: [.contentModificationDateKey])
        return v?.contentModificationDate?.timeIntervalSince1970 ?? 0
    }
    candidates.sort { mtime($0) > mtime($1) }
    if let prefer = preferCwd {
        let want = rstripSlash(prefer)
        for c in candidates {
            if let fc = firstCwd(c), rstripSlash(fc) == want {
                return c
            }
        }
    }
    return candidates[0]
}

func rstripSlash(_ s: String) -> String {
    var t = Substring(s)
    while t.hasSuffix("/") { t = t.dropLast() }
    return String(t)
}

// --------------------------------------------------------------------------- //
// Tool-name normalization
// --------------------------------------------------------------------------- //

let TOOL_NAME_MAP: [String: String] = [
    "Read": "view", "Edit": "edit", "Write": "create", "Glob": "glob",
    "Grep": "grep", "Bash": "shell", "Skill": "skill", "Agent": "agent",
    "Task": "agent", "WebFetch": "web_fetch", "WebSearch": "web_search",
    "NotebookEdit": "edit", "TodoWrite": "todo", "AskUserQuestion": "ask_user",
]

func normTool(_ name: String) -> String {
    return TOOL_NAME_MAP[name] ?? name.lowercased()
}

// --------------------------------------------------------------------------- //
// Error extraction
// --------------------------------------------------------------------------- //

let ERR_TRIGGER = try! NSRegularExpression(
    pattern: "error:|BUILD FAILED|fatal error|Command .* failed|"
        + "linker command failed|code object is not signed|"
        + "Undefined symbol|cannot find",
    options: [.caseInsensitive])

func regexSearch(_ re: NSRegularExpression, _ s: String) -> Bool {
    let range = NSRange(s.startIndex..., in: s)
    return re.firstMatch(in: s, range: range) != nil
}

// Returns the first matched substring's group, mirroring Python re.search(...).group(n).
func regexFirstGroup(_ pattern: String, _ s: String, group: Int) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(s.startIndex..., in: s)
    guard let m = re.firstMatch(in: s, range: range) else { return nil }
    let gr = m.range(at: group)
    guard gr.location != NSNotFound, let r = Range(gr, in: s) else { return nil }
    return String(s[r])
}

// Python: s[:n] over Unicode code points; truncate at n characters.
func prefixChars(_ s: String, _ n: Int) -> String {
    if s.count <= n { return s }
    return String(s.prefix(n))
}

func errorSummary(_ text: String?) -> (Bool, [String]) {
    guard let text = text, !text.isEmpty else { return (false, []) }
    if !regexSearch(ERR_TRIGGER, text) { return (false, []) }
    var out: [String] = []
    // Python str.splitlines() splits on a broader set of boundaries.
    for line in splitLines(text) {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !regexSearch(ERR_TRIGGER, s) { continue }
        if let g = regexFirstGroup("error:\\s*(.+)", s, group: 1) {
            out.append(prefixChars(g.trimmingCharacters(in: .whitespacesAndNewlines), 140))
        } else if s.contains("BUILD FAILED") {
            out.append("** BUILD FAILED **")
        } else if let g0 = regexFirstGroup("Command (\\S+) failed", s, group: 0) {
            out.append(g0)
        } else if s.contains("linker command failed") {
            out.append("linker command failed")
        } else {
            out.append(prefixChars(s, 140))
        }
        if out.count >= 5 { break }
    }
    // de-dupe preserving order
    var seen = Set<String>()
    var uniq: [String] = []
    for e in out {
        if !seen.contains(e) { seen.insert(e); uniq.append(e) }
    }
    return (true, uniq)
}

// Python str.splitlines(): split on \n \r \r\n and several unicode line boundaries.
func splitLines(_ s: String) -> [String] {
    var result: [String] = []
    var current = ""
    let chars = Array(s.unicodeScalars)
    var i = 0
    let breaks: Set<UInt32> = [0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x85, 0x2028, 0x2029]
    while i < chars.count {
        let c = chars[i]
        if breaks.contains(c.value) {
            // Handle CRLF as a single break.
            if c.value == 0x0D && i + 1 < chars.count && chars[i + 1].value == 0x0A {
                i += 1
            }
            result.append(current)
            current = ""
        } else {
            current.unicodeScalars.append(c)
        }
        i += 1
    }
    if !current.isEmpty {
        result.append(current)
    }
    return result
}

// --------------------------------------------------------------------------- //
// Parsing
// --------------------------------------------------------------------------- //

func extractPrompt(_ events: [Event]) -> String {
    for ev in events {
        if ev.type != "user" { continue }
        if ev.isMeta?.value == true { continue }
        if ev.isSidechain?.value == true { continue }
        let content = ev.message?.content
        var cand: String? = nil
        if let s = content?.stringValue {
            cand = s
        } else if let arr = content?.arrayValue {
            let hasToolResult = arr.contains { if case .toolResult = $0 { return true } else { return false } }
            var texts: [String] = []
            for b in arr {
                if case let .text(t) = b {
                    texts.append(t)
                }
            }
            if !hasToolResult && !texts.isEmpty {
                cand = texts.joined(separator: "\n")
            }
        }
        guard let c = cand, !c.isEmpty else { continue }
        let s = c.trimmingCharacters(in: .whitespacesAndNewlines)
        if let re = try? NSRegularExpression(pattern: "^<(local-)?command-(name|message|args|stdout)>") {
            let range = NSRange(s.startIndex..., in: s)
            if re.firstMatch(in: s, range: range) != nil { continue }
        }
        if s.hasPrefix("<local-command-caveat>") { continue }
        return c
    }
    return "(no prompt found)"
}

struct Tool {
    var name: String
    var args: JSONValue   // the tool_use `input` object (or .object([:]))
    var error: Bool
    var errs: [String]
}

final class Turn {
    var n: Int
    var tools: [Tool] = []
    var outTokens: Int = 0
    var cacheRead: Int = 0
    var cacheCreate: Int = 0
    var skills: [String] = []
    var agents: [String] = []
    var category: String = "other"
    init(n: Int) { self.n = n }
}

struct Subagent {
    var id: String
    var type: String
    var desc: String
    var turns: [Turn]
    var duration: Double
}

struct Parsed {
    var sessionId: String
    var model: String
    var durationMin: Double
    var prompt: String
    var turns: [Turn]
    var subagents: [Subagent]
}

// Agent metadata sidecar (stable keys, synthesized Decodable). Both fields are
// optional so absence is tolerated; presence vs. absence drives the fallback.
struct AgentMeta: Decodable {
    let agentType: String?
    let description: String?
}

// Parse ISO timestamp like "2026-06-05T04:44:27.709Z" -> seconds since epoch.
// Mirrors datetime.fromisoformat(ts.replace("Z","+00:00")); returns nil on failure.
func parseTimestamp(_ ts: String) -> Double? {
    let s = ts.replacingOccurrences(of: "Z", with: "+00:00")
    // Expect: YYYY-MM-DDTHH:MM:SS[.ffffff](+HH:MM | -HH:MM)
    // datetime.fromisoformat is strict but the inputs are well-formed; parse manually.
    guard let tIdx = s.firstIndex(of: "T") else { return nil }
    let datePart = String(s[s.startIndex..<tIdx])
    let rest = String(s[s.index(after: tIdx)...])
    // rest = HH:MM:SS[.frac][tz]
    // Find tz offset: look for '+' or '-' after the time (skip first char).
    var tzSign: Character? = nil
    var tzIndex: String.Index? = nil
    let restChars = Array(rest)
    var ci = 0
    while ci < restChars.count {
        let c = restChars[ci]
        if (c == "+" || c == "-") && ci > 0 {
            tzSign = c
            tzIndex = rest.index(rest.startIndex, offsetBy: ci)
            break
        }
        ci += 1
    }
    var timePart = rest
    var tzSeconds = 0.0
    if let tzIdx = tzIndex, let sign = tzSign {
        timePart = String(rest[rest.startIndex..<tzIdx])
        let tzStr = String(rest[rest.index(after: tzIdx)...]) // HH:MM
        let comps = tzStr.split(separator: ":")
        if comps.count == 2, let h = Double(comps[0]), let m = Double(comps[1]) {
            tzSeconds = (h * 3600 + m * 60) * (sign == "-" ? -1 : 1)
        }
    }
    // datePart = YYYY-MM-DD
    let dc = datePart.split(separator: "-")
    guard dc.count == 3, let year = Int(dc[0]), let month = Int(dc[1]), let day = Int(dc[2]) else { return nil }
    // timePart = HH:MM:SS[.frac]
    let tc = timePart.split(separator: ":")
    guard tc.count == 3, let hour = Int(tc[0]), let minute = Int(tc[1]) else { return nil }
    let secStr = String(tc[2])
    var second = 0
    var frac = 0.0
    if let dot = secStr.firstIndex(of: ".") {
        second = Int(secStr[secStr.startIndex..<dot]) ?? 0
        let fracStr = String(secStr[secStr.index(after: dot)...])
        if let f = Double("0." + fracStr) { frac = f }
    } else {
        second = Int(secStr) ?? 0
    }
    // Days from civil (proleptic Gregorian) -> days since 1970-01-01.
    let epochDay = daysFromCivil(year, month, day)
    let total = Double(epochDay) * 86400.0
        + Double(hour) * 3600.0 + Double(minute) * 60.0 + Double(second) + frac
        - tzSeconds
    return total
}

// Howard Hinnant's days_from_civil algorithm.
func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
    let y = m <= 2 ? y0 - 1 : y0
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146097 + doe - 719468
}

func parseSession(_ path: URL, isSubagent: Bool = false, includeSubagents: Bool = true) -> Parsed {
    let events = readJsonl(path)
    let prompt = extractPrompt(events)
    let stem = path.deletingPathExtension().lastPathComponent
    // Python: sid = (events[0].get("sessionId") if events else None) or path.stem
    // If sessionId is missing/empty/None, fall back to stem.
    var sid: String = stem
    if let first = events.first, let s = first.sessionId, !s.isEmpty {
        sid = s
    }

    // model
    var model = "(unknown)"
    if let firstAssistant = events.first(where: { $0.type == "assistant" }) {
        if let ms = firstAssistant.message?.model {
            model = ms
        } else {
            model = "(unknown)"
        }
    }

    // duration
    var times: [Double] = []
    for ev in events {
        if let ts = ev.timestamp, !ts.isEmpty {
            if let t = parseTimestamp(ts) {
                times.append(t)
            }
        }
    }
    let durationMin = times.count >= 2 ? (times[times.count - 1] - times[0]) / 60.0 : 0.0

    // tool_results keyed by tool_use_id
    var toolResults: [String: (text: String, isError: Bool)] = [:]
    for ev in events {
        if ev.type == "user", let arr = ev.message?.content?.arrayValue {
            for block in arr {
                if case let .toolResult(toolUseId, content, isError) = block {
                    var txt = ""
                    if let cs = content?.asString {
                        txt = cs
                    } else if let carr = content?.arrayValue {
                        var parts: [String] = []
                        for i in carr {
                            if let t = i["type"]?.asString, t == "text" {
                                parts.append(i["text"]?.asString ?? "")
                            }
                        }
                        txt = parts.joined(separator: "\n")
                    }
                    let key = stringifyId(toolUseId)
                    toolResults[key] = (txt, isError.value)
                }
            }
        }
    }

    var turns: [Turn] = []
    var turnNum = 0
    for ev in events {
        if ev.type != "assistant" { continue }
        if !isSubagent {
            if ev.isSidechain?.value == true { continue }
        }
        turnNum += 1
        let usage = ev.message?.usage
        let turn = Turn(n: turnNum)
        turn.outTokens = usage?.output_tokens ?? 0
        turn.cacheRead = usage?.cache_read_input_tokens ?? 0
        turn.cacheCreate = usage?.cache_creation_input_tokens ?? 0
        if let arr = ev.message?.content?.arrayValue {
            for block in arr {
                guard case let .toolUse(id, name, input) = block else { continue }
                let callId = stringifyId(id)
                let args = input
                let nname = normTool(name ?? "")
                var tool = Tool(name: nname, args: args, error: false, errs: [])
                if nname == "skill", let sk = args["skill"], !sk.isNull {
                    turn.skills.append(sk.pyStr)
                }
                if nname == "agent" {
                    if let st = args["subagent_type"], !st.isNull {
                        turn.agents.append(st.pyStr)
                    } else {
                        turn.agents.append("general-purpose")
                    }
                }
                if let tr = toolResults[callId] {
                    let (hasErr, errs) = errorSummary(tr.text)
                    if tr.isError || hasErr {
                        tool.error = true
                        tool.errs = errs
                    }
                }
                turn.tools.append(tool)
            }
        }
        turns.append(turn)
    }

    var subagents: [Subagent] = []
    if includeSubagents && !isSubagent {
        let subDir = path.deletingPathExtension()
            .deletingLastPathComponent()
            .appendingPathComponent(stem)
            .appendingPathComponent("subagents")
        let fm = FileManager.default
        if fm.fileExists(atPath: subDir.path) {
            // sorted(sub_dir.glob("agent-*.jsonl")) — non-recursive, lexical sort by full path.
            var agentFiles: [URL] = []
            if let entries = try? fm.contentsOfDirectory(at: subDir, includingPropertiesForKeys: nil) {
                for u in entries {
                    let name = u.lastPathComponent
                    if name.hasPrefix("agent-") && name.hasSuffix(".jsonl") {
                        agentFiles.append(u)
                    }
                }
            }
            // Python sorts Path objects by their string value (full path).
            agentFiles.sort { $0.path < $1.path }
            for af in agentFiles {
                let afStem = af.deletingPathExtension().lastPathComponent
                let agentId = afStem.hasPrefix("agent-")
                    ? String(afStem.dropFirst("agent-".count)) : afStem
                var meta: AgentMeta? = nil
                let metaPath = af.deletingLastPathComponent()
                    .appendingPathComponent("agent-\(agentId).meta.json")
                if fm.fileExists(atPath: metaPath.path) {
                    if let data = try? Data(contentsOf: metaPath),
                       let m = try? jsonDecoder.decode(AgentMeta.self, from: data) {
                        meta = m
                    }
                }
                let sub = parseSession(af, isSubagent: true, includeSubagents: false)
                // Python: meta.get("agentType", "(unknown)") / meta.get("description", "").
                // Missing key -> default; present (even if non-string) -> str(). Here a
                // present-but-non-string agentType would have failed String decode and
                // landed as nil; the real data is always a string, matching Python.
                let aType = meta?.agentType ?? "(unknown)"
                let aDesc = meta?.description ?? ""
                subagents.append(Subagent(
                    id: agentId,
                    type: aType,
                    desc: aDesc,
                    turns: sub.turns,
                    duration: sub.durationMin))
            }
        }
    }

    return Parsed(sessionId: sid, model: model, durationMin: durationMin,
                  prompt: prompt, turns: turns, subagents: subagents)
}

// Python str(x) for an id-shaped value (tool_use_id / id). None -> "None".
func stringifyId(_ v: JSONValue?) -> String {
    guard let v = v else { return "None" }
    return v.pyStr
}

// --------------------------------------------------------------------------- //
// Categorization
// --------------------------------------------------------------------------- //

func isShell(_ t: Tool) -> Bool { t.name == "shell" }
func cmd(_ t: Tool) -> String {
    if isShell(t) {
        if let c = t.args["command"], !c.isNull {
            if let s = c.asString { return s }
            return c.pyStr
        }
        return ""
    }
    return ""
}

let RE_HELPER = try! NSRegularExpression(pattern: "build-and-run\\.sh|build-and-run\\b|BuildAndRun")
let RE_BUILD = try! NSRegularExpression(pattern: "\\bxcodebuild\\b|build-and-run|BuildAndRun|\\btuist\\b|\\bswift build\\b")
let RE_RUN = try! NSRegularExpression(pattern: "\\bopen\\s+.*\\.app|(?:build-and-run|BuildAndRun)(?!.*--skip-run)|Contents/MacOS/")
let RE_DIAG = try! NSRegularExpression(pattern: "xcresulttool|-showBuildSettings|DiagnosticReports|"
    + "log stream|grep .*error|DerivedData|rm -rf .*build|codesign --verify|spctl")
let RE_SCAFFOLD = try! NSRegularExpression(pattern: "tuist generate|tuist install|mkdir ")
let RE_GIT = try! NSRegularExpression(pattern: "\\bgit\\b")
let RE_XCODEBUILD = try! NSRegularExpression(pattern: "\\bxcodebuild\\b")
let RE_CLEAN = try! NSRegularExpression(pattern: "rm -rf .*build|DerivedData")

func categorize(_ turn: Turn) -> String {
    let names = turn.tools.map { $0.name }
    let hasSkill = !turn.skills.isEmpty
    let hasBuild = turn.tools.contains { isShell($0) && regexSearch(RE_BUILD, cmd($0)) }
    let hasBuildErr = turn.tools.contains { $0.error && isShell($0) && regexSearch(RE_BUILD, cmd($0)) }
    let hasRun = turn.tools.contains { isShell($0) && regexSearch(RE_RUN, cmd($0)) }
    let hasGit = turn.tools.contains { isShell($0) && regexSearch(RE_GIT, cmd($0)) }
    let isDiag = turn.tools.contains { isShell($0) && regexSearch(RE_DIAG, cmd($0)) }
    let hasScaffold = turn.tools.contains { regexSearch(RE_SCAFFOLD, cmd($0)) }
    let hasCreate = names.contains("create")
    let hasEdit = names.contains("edit")
    let hasView = names.contains("view")
    let hasAgent = names.contains("agent")

    if hasSkill && names.count <= 2 { return "skill-load" }
    if hasGit && !hasBuild { return "git" }
    if hasBuild && hasBuildErr { return "build-fix" }
    if hasBuild && !hasBuildErr { return "build-ok" }
    if hasRun { return "run" }
    if isDiag && !hasEdit { return "diagnosing" }
    if hasScaffold { return "scaffold" }
    if hasAgent { return "subagent" }
    if hasCreate && !hasEdit { return "code-create" }
    if hasEdit { return "code-edit" }
    if hasView && !hasEdit && !hasCreate { return "explore" }
    if names.isEmpty { return "thinking" }
    return "other"
}

// --------------------------------------------------------------------------- //
// Rendering
// --------------------------------------------------------------------------- //

let CATEGORY_LABELS: [String: String] = [
    "skill-load": "Skill loading", "explore": "Reading/exploring",
    "scaffold": "Scaffolding", "code-create": "Creating files",
    "code-edit": "Editing code", "build-ok": "Build (success)",
    "build-fix": "Build (failed)", "run": "Running app", "git": "Git operations",
    "thinking": "Thinking (no tools)", "diagnosing": "Diagnosing errors",
    "subagent": "Subagent dispatch", "other": "Other",
]

// os.path.basename equivalent (POSIX): text after the last "/".
func basename(_ p: String) -> String {
    if let idx = p.lastIndex(of: "/") {
        return String(p[p.index(after: idx)...])
    }
    return p
}

func argStr(_ args: JSONValue, _ key: String) -> String? {
    guard let v = args[key], !v.isNull else { return nil }
    if let s = v.asString { return s }
    return v.pyStr
}

// Python truthiness for a.get("path") or a.get("file_path").
func truthyStr(_ args: JSONValue, _ key: String) -> String? {
    guard let v = args[key], !v.isNull else { return nil }
    switch v {
    case let .string(s):
        return s.isEmpty ? nil : s
    case let .bool(b):
        return b ? "True" : nil
    case let .int(i):
        return i == 0 ? nil : String(i)
    case let .double(d):
        return d == 0 ? nil : v.pyStr
    case let .array(a):
        return a.isEmpty ? nil : v.pyStr
    case let .object(o):
        return o.isEmpty ? nil : v.pyStr
    case .null:
        return nil
    }
}

func toolList(_ turn: Turn) -> String {
    var parts: [String] = []
    for t in turn.tools {
        let err = t.error ? " ❌" : ""
        var summ = ""
        let a = t.args
        if t.name == "shell" {
            let c = argStr(a, "command") ?? ""
            let firstLine = splitLines(c).first ?? ""
            summ = prefixChars(firstLine, 60)
        } else if let p = truthyStr(a, "path") ?? truthyStr(a, "file_path") {
            summ = basename(p)
        } else if t.name == "skill" {
            summ = stringifyMaybe(a["skill"])
        } else if t.name == "agent" {
            summ = stringifyMaybe(a["subagent_type"])
        } else if let pat = truthyPattern(a) {
            summ = pat
        }
        if !summ.isEmpty {
            parts.append("\(t.name)(\(summ))\(err)")
        } else {
            parts.append("\(t.name)\(err)")
        }
    }
    let skills = turn.skills.isEmpty ? "" : " [skill: \(turn.skills.joined(separator: ","))]"
    return parts.joined(separator: ", ") + skills
}

// Python str(x) for a value used as a summary; None/missing -> "".
func stringifyMaybe(_ v: JSONValue?) -> String {
    guard let v = v, !v.isNull else { return "" }
    if let s = v.asString { return s }
    return v.pyStr
}

// Python: elif a.get("pattern"): summ = str(a["pattern"])
func truthyPattern(_ args: JSONValue) -> String? {
    guard let v = args["pattern"], !v.isNull else { return nil }
    switch v {
    case let .string(s):
        return s.isEmpty ? nil : s
    case let .bool(b):
        return b ? "True" : nil
    case let .int(i):
        return i == 0 ? nil : String(i)
    case let .double(d):
        return d == 0 ? nil : v.pyStr
    case let .array(a):
        return a.isEmpty ? nil : v.pyStr
    case let .object(o):
        return o.isEmpty ? nil : v.pyStr
    case .null:
        return nil
    }
}

func render(_ parsed: Parsed, includeSubagents: Bool) -> String {
    var allTurns: [Turn] = parsed.turns
    if includeSubagents {
        for sa in parsed.subagents {
            allTurns += sa.turns
        }
    }

    let buildOk = allTurns.filter { $0.category == "build-ok" }.count
    let buildFix = allTurns.filter { $0.category == "build-fix" }.count
    let attempts = buildOk + buildFix

    let usedBar = allTurns.contains { tn in tn.tools.contains { isShell($0) && regexSearch(RE_HELPER, cmd($0)) } }
    let rawXcb = allTurns.contains { tn in tn.tools.contains {
        isShell($0) && regexSearch(RE_XCODEBUILD, cmd($0)) && !regexSearch(RE_HELPER, cmd($0))
    } }
    let buildStatus: String
    if usedBar && !rawXcb {
        buildStatus = "Used build-and-run.sh for all builds"
    } else if usedBar && rawXcb {
        buildStatus = "Mixed: raw xcodebuild and build-and-run.sh"
    } else if rawXcb {
        buildStatus = "NOT USED: raw xcodebuild only, never used build-and-run.sh"
    } else {
        buildStatus = "No build commands detected"
    }

    // build errors
    var buildErrors: [(Int, [String])] = []
    for t in allTurns {
        for tool in t.tools {
            if tool.error && isShell(tool) && regexSearch(RE_BUILD, cmd(tool)) && !tool.errs.isEmpty {
                buildErrors.append((t.n, tool.errs))
            }
        }
    }

    // skills timeline
    var skillTimeline: [(Int, String, String)] = []
    for t in parsed.turns {
        for s in t.skills {
            skillTimeline.append((t.n, s, "parent"))
        }
    }
    for sa in parsed.subagents {
        for t in sa.turns {
            for s in t.skills {
                skillTimeline.append((t.n, s, "subagent:\(sa.type)"))
            }
        }
    }

    // token totals
    let outTok = allTurns.reduce(0) { $0 + $1.outTokens }
    let crTok = allTurns.reduce(0) { $0 + $1.cacheRead }
    let ccTok = allTurns.reduce(0) { $0 + $1.cacheCreate }

    // category table — preserve dict-insertion order then stable sort by turns desc.
    var catOrder: [String] = []
    var catCounts: [String: (turns: Int, tokens: Int)] = [:]
    for t in allTurns {
        let c = t.category
        if catCounts[c] == nil {
            catCounts[c] = (0, 0)
            catOrder.append(c)
        }
        catCounts[c]!.turns += 1
        catCounts[c]!.tokens += t.outTokens
    }
    // Python sorted(..., key=turns, reverse=True) is stable: ties keep insertion order.
    let catRows = stableSortByTurnsDesc(order: catOrder, counts: catCounts)

    // stuck patterns
    var stuck: [String] = []
    var readsOrder: [String] = []
    var reads: [String: Int] = [:]
    for t in allTurns {
        for tool in t.tools {
            if tool.name == "view" {
                if let p = truthyStr(tool.args, "path") ?? truthyStr(tool.args, "file_path") {
                    let f = basename(p)
                    if reads[f] == nil { reads[f] = 0; readsOrder.append(f) }
                    reads[f]! += 1
                }
            }
        }
    }
    var excessive: [(String, Int)] = []
    for f in readsOrder {
        let n = reads[f]!
        if n >= 3 { excessive.append((f, n)) }
    }
    if !excessive.isEmpty {
        let joined = excessive.map { "\($0.0) (\($0.1)x)" }.joined(separator: ", ")
        stuck.append("Repeated file reads: " + joined)
    }
    var consec = 0
    var mx = 0
    for t in allTurns {
        if t.category == "build-fix" {
            consec += 1; mx = max(mx, consec)
        } else if t.category == "build-ok" {
            consec = 0
        }
    }
    if mx >= 3 {
        stuck.append("Build loop: \(mx) consecutive build failures before success")
    }
    var cleans = 0
    for t in allTurns {
        for tool in t.tools {
            if regexSearch(RE_CLEAN, cmd(tool)) { cleans += 1 }
        }
    }
    if cleans >= 2 {
        stuck.append("Cleaned build/DerivedData \(cleans)x (suggests stale build state)")
    }

    // ----- markdown -----
    var md: [String] = []
    md.append("# Session Analysis Report\n")
    md.append("## Overview\n")
    md.append("| Field | Value |")
    md.append("|-------|-------|")
    md.append("| Harness | Claude Code |")
    md.append("| Session ID | `\(parsed.sessionId)` |")
    md.append("| Model | \(parsed.model) |")
    md.append("| Duration | \(dur(parsed.durationMin)) min |")
    md.append("| Turns (parent) | \(parsed.turns.count) |")
    if includeSubagents && !parsed.subagents.isEmpty {
        let subTurns = parsed.subagents.reduce(0) { $0 + $1.turns.count }
        md.append("| Subagents | \(parsed.subagents.count) (\(subTurns) turns) |")
    }
    md.append("| Output tokens (combined) | \(grouped(outTok)) |")
    md.append("| Cache read tokens | \(grouped(crTok)) |")
    md.append("| Cache create tokens | \(grouped(ccTok)) |")
    md.append("")

    md.append("## Prompt\n")
    var p = parsed.prompt
    if p.count > 500 {
        p = String(p.prefix(500)) + "..."
    }
    md.append("```"); md.append(p); md.append("```"); md.append("")

    md.append("## Turn Breakdown\n")
    if includeSubagents && !parsed.subagents.isEmpty {
        md.append("_Combined parent + \(parsed.subagents.count) subagent transcript(s)._\n")
    }
    md.append("| Category | Turns | Output Tokens |")
    md.append("|----------|------:|--------------:|")
    for (cat, e) in catRows {
        let label = CATEGORY_LABELS[cat] ?? cat
        md.append("| \(label) | \(e.turns) | \(grouped(e.tokens)) |")
    }
    md.append("")

    md.append("## Skills\n")
    if !skillTimeline.isEmpty {
        md.append("**Invoked:**")
        for (n, s, origin) in skillTimeline {
            let tag = origin == "parent" ? "" : " _(in \(origin))_"
            md.append("- Turn \(n): `\(s)`\(tag)")
        }
    } else {
        md.append("_No skills were invoked during this session._")
    }
    md.append("")

    if includeSubagents && !parsed.subagents.isEmpty {
        md.append("## Subagents\n")
        md.append("| Agent ID | Type | Turns | Duration | Description |")
        md.append("|---|---|---:|---:|---|")
        for sa in parsed.subagents {
            var d = sa.desc
            if d.count > 60 {
                d = String(d.prefix(60)) + "..."
            }
            md.append("| `\(sa.id)` | \(sa.type) | \(sa.turns.count) | \(dur(sa.duration)) min | \(d) |")
        }
        md.append("")
    }

    md.append("## Build Analysis\n")
    md.append("- **Attempts:** \(attempts) (\(buildOk) success, \(buildFix) failed)")
    md.append("- **build-and-run.sh:** \(buildStatus)")
    md.append("")
    if !buildErrors.isEmpty {
        md.append("**Build errors encountered:**\n")
        for (n, errs) in buildErrors {
            md.append("Turn \(n):")
            for e in errs {
                md.append("- `\(e)`")
            }
        }
        md.append("")
    }

    if !stuck.isEmpty {
        md.append("## Stuck Patterns\n")
        for s in stuck {
            md.append("- \(s)")
        }
        md.append("")
    }

    md.append("## Turn Detail\n")
    md.append("_Parent session._\n")
    md.append("| # | Category | Tokens | Tools |")
    md.append("|--:|----------|-------:|-------|")
    for t in parsed.turns {
        md.append("| \(t.n) | \(t.category) | \(grouped(t.outTokens)) | \(toolList(t)) |")
    }
    md.append("")
    if includeSubagents {
        for sa in parsed.subagents {
            md.append("_Subagent `\(sa.type)` (id `\(sa.id)`)._\n")
            md.append("| # | Category | Tokens | Tools |")
            md.append("|--:|----------|-------:|-------|")
            for t in sa.turns {
                md.append("| \(t.n) | \(t.category) | \(grouped(t.outTokens)) | \(toolList(t)) |")
            }
            md.append("")
        }
    }

    return md.joined(separator: "\n")
}

// Stable sort by turns descending, preserving insertion order for ties.
func stableSortByTurnsDesc(order: [String], counts: [String: (turns: Int, tokens: Int)])
    -> [(String, (turns: Int, tokens: Int))] {
    let indexed = order.enumerated().map { (idx, key) in (idx, key, counts[key]!) }
    let sorted = indexed.sorted { a, b in
        if a.2.turns != b.2.turns { return a.2.turns > b.2.turns }
        return a.0 < b.0
    }
    return sorted.map { ($0.1, $0.2) }
}

// --------------------------------------------------------------------------- //
// Privacy notice
// --------------------------------------------------------------------------- //

let PRIVACY = """
## Privacy and sensitivity — read before sharing this file

**This report was generated from your live agent session and was NOT redacted.** Depending on what your session involved, it can include:

- File contents and paths the agent read or edited (source, configuration, secrets accidentally pasted into prompts, internal URLs, customer data).
- Your prompts verbatim — including any credentials, tokens, identifiers, or proprietary information you typed.
- Tool output — `git` history, environment values echoed by failing commands, build logs containing machine names and `/Users/<you>/…` paths, signing identities, and crash traces.
- Error messages quoting source code or stack traces from third-party libraries.

**You are responsible for the contents of this file.** Open it in your editor and read it end-to-end before attaching it to a public issue, posting it in chat, or sending it outside your organization. Redact anything sensitive (paths, names, secrets, signing identities, business logic). When in doubt, share excerpts rather than the whole file, or ask the agent to summarize the metrics instead.

"""

func insertPrivacy(_ report: String) -> String {
    let lines = report.components(separatedBy: "\n")
    var idx = 1
    for (i, l) in lines.enumerated() {
        if l.hasPrefix("## Overview") { idx = i; break }
    }
    var result: [String] = []
    result.append(contentsOf: lines[0..<idx])
    result.append(PRIVACY)
    result.append("")
    result.append(contentsOf: lines[idx...])
    return result.joined(separator: "\n")
}

// --------------------------------------------------------------------------- //
// Main
// --------------------------------------------------------------------------- //

func parseArgs(_ argv: [String]) -> (sessionId: String?, eventsFile: String?, output: String?, skipSubagents: Bool) {
    var sessionId: String? = nil
    var eventsFile: String? = nil
    var output: String? = nil
    var skip = false
    var i = 1
    while i < argv.count {
        let a = argv[i]
        switch a {
        case "--session-id":
            i += 1; if i < argv.count { sessionId = argv[i] }
        case "--events-file":
            i += 1; if i < argv.count { eventsFile = argv[i] }
        case "--output":
            i += 1; if i < argv.count { output = argv[i] }
        case "--skip-subagents":
            skip = true
        default:
            if a.hasPrefix("--session-id=") { sessionId = String(a.dropFirst("--session-id=".count)) }
            else if a.hasPrefix("--events-file=") { eventsFile = String(a.dropFirst("--events-file=".count)) }
            else if a.hasPrefix("--output=") { output = String(a.dropFirst("--output=".count)) }
        }
        i += 1
    }
    return (sessionId, eventsFile, output, skip)
}

func runMain() -> Int32 {
    let argv = CommandLine.arguments
    let args = parseArgs(argv)
    let fm = FileManager.default

    var path: URL
    if let ef = args.eventsFile {
        path = URL(fileURLWithPath: ef)
        if !fm.fileExists(atPath: path.path) {
            FileHandle.standardError.write("Events file not found: \(ef)\n".data(using: .utf8)!)
            return 1
        }
    } else if let sid = args.sessionId {
        guard let found = findSessionById(sid) else {
            FileHandle.standardError.write(
                "Session id '\(sid)' not found under \(projectsRoot().path)\n".data(using: .utf8)!)
            return 1
        }
        path = found
    } else {
        let envSid = ProcessInfo.processInfo.environment["CLAUDE_SESSION_ID"]
        var found: URL? = nil
        if let es = envSid {
            found = findSessionById(es)
        }
        if found == nil {
            found = findLatestSession(preferCwd: fm.currentDirectoryPath)
        }
        guard let f = found else {
            FileHandle.standardError.write(
                "No Claude Code sessions found under \(projectsRoot().path)\n".data(using: .utf8)!)
            FileHandle.standardError.write(
                "If you use a different agent harness, this analyzer doesn't support it yet.\n".data(using: .utf8)!)
            return 1
        }
        path = f
    }

    let includeSubagents = !args.skipSubagents
    let parsed = parseSession(path, isSubagent: false, includeSubagents: includeSubagents)
    for t in parsed.turns {
        t.category = categorize(t)
    }
    for si in 0..<parsed.subagents.count {
        for t in parsed.subagents[si].turns {
            t.category = categorize(t)
        }
    }

    let report = insertPrivacy(render(parsed, includeSubagents: includeSubagents && !parsed.subagents.isEmpty))

    if let out = args.output {
        do {
            try report.write(toFile: out, atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write("Failed to write \(out): \(error)\n".data(using: .utf8)!)
            return 1
        }
        print("\nReport saved to: \(out)")
        let banner = String(repeating: "=", count: 64)
        let lines = [
            banner,
            " PRIVACY NOTICE — READ BEFORE SHARING \(out)",
            banner,
            " This report contains your unredacted session transcript:",
            "   * file contents and paths the agent read or edited",
            "   * your prompts verbatim (including any secrets you pasted)",
            "   * tool output, error messages, local paths, signing identities",
            "",
            " You are responsible for what you share. Open the file and read",
            " it end-to-end before posting it publicly. Redact anything sensitive.",
            banner,
        ]
        for line in lines {
            FileHandle.standardError.write((line + "\n").data(using: .utf8)!)
        }
    } else {
        print(report)
    }
    return 0
}

exit(runMain())
