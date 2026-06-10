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

/// A recursively-typed JSON value for genuinely-dynamic transcript payloads.
indirect enum JSONValue: Decodable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }

    /// The wrapped string, or `nil` for any non-string value.
    var stringValue: String? {
        if case let .string(string) = self { return string }
        return nil
    }

    /// The member value for `key`; `nil` for non-objects or missing keys.
    subscript(_ key: String) -> JSONValue? {
        if case let .object(object) = self { return object[key] }
        return nil
    }

    /// A Boolean value indicating whether this is the JSON null.
    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// The wrapped object, or `nil` for non-objects.
    var objectValue: [String: JSONValue]? {
        if case let .object(object) = self { return object }
        return nil
    }

    /// The wrapped array, or `nil` for non-arrays.
    var arrayValue: [JSONValue]? {
        if case let .array(array) = self { return array }
        return nil
    }

    /// The Python `str(x)` rendering of this value reachable from a dict.
    ///
    /// Null renders as `"None"`, strings pass through, and everything else uses
    /// a repr-ish form. Used for ids and skill/agent names where Python applies
    /// `str()`.
    var pythonString: String {
        switch self {
        case .null: return "None"
        case let .bool(bool): return bool ? "True" : "False"
        case let .int(int): return String(int)
        case let .double(double): return "\(double)"
        case let .string(string): return string
        case let .array(array): return "\(array)"
        case let .object(object): return "\(object)"
        }
    }
}

// --------------------------------------------------------------------------- //
// ContentBlock — decoded on the `type` discriminator, with an `.other`
// catch-all so unknown block types are tolerated (forward-compat).
// --------------------------------------------------------------------------- //

/// A single message content block, decoded on its `type` discriminator.
enum ContentBlock: Decodable {
    case text(String)
    case toolUse(id: JSONValue?, name: String?, input: JSONValue)
    case toolResult(toolUseID: JSONValue?, content: JSONValue?, isError: Truthy)
    case thinking
    case other(String)

    private enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
        case toolUseID = "tool_use_id"
        case content
        case isError = "is_error"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? ""
        switch type {
        case "text":
            let text = (try? container.decode(String.self, forKey: .text)) ?? ""
            self = .text(text)
        case "tool_use":
            let id = try? container.decode(JSONValue.self, forKey: .id)
            let name = try? container.decode(String.self, forKey: .name)
            let input = (try? container.decode(JSONValue.self, forKey: .input)) ?? .object([:])
            self = .toolUse(id: id, name: name, input: input)
        case "tool_result":
            let toolUseID = try? container.decode(JSONValue.self, forKey: .toolUseID)
            let content = try? container.decode(JSONValue.self, forKey: .content)
            let isError = (try? container.decode(Truthy.self, forKey: .isError)) ?? Truthy(false)
            self = .toolResult(toolUseID: toolUseID, content: content, isError: isError)
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

/// A lenient Boolean mirroring Python's `if obj.get(x)` truthiness over bool, number, or null.
struct Truthy: Decodable {
    let value: Bool
    init(_ value: Bool) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = false
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int != 0
        } else if let double = try? container.decode(Double.self) {
            value = double != 0
        } else {
            value = false
        }
    }
}

// --------------------------------------------------------------------------- //
// MessageContent — `content` is either a JSON string or an array of blocks.
// Custom decode tries the array form first, then the string form.
// --------------------------------------------------------------------------- //

/// A message's `content`, which is either a JSON string or an array of blocks.
enum MessageContent: Decodable {
    case string(String)
    case array([ContentBlock])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let blocks = try? container.decode([ContentBlock].self) {
            self = .array(blocks)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            self = .string("")
        }
    }

    /// The wrapped string, or `nil` for the array form.
    var stringValue: String? {
        if case let .string(string) = self { return string }
        return nil
    }

    /// The wrapped block array, or `nil` for the string form.
    var arrayValue: [ContentBlock]? {
        if case let .array(blocks) = self { return blocks }
        return nil
    }
}

// --------------------------------------------------------------------------- //
// Usage / Message / Event — stable shapes, synthesized Decodable. The
// synthesized Decodable for Usage silently ignores the other ~7 usage keys;
// optional fields tolerate absence. CodingKeys map the snake_case JSON.
// --------------------------------------------------------------------------- //

/// Token-usage counters attached to an assistant message.
struct Usage: Decodable {
    let outputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreationInputTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
    }
}

/// A single message envelope: model, usage, and content.
struct Message: Decodable {
    let model: String?
    let usage: Usage?
    let content: MessageContent?
}

/// One transcript line: an event envelope with its message and metadata.
struct Event: Decodable {
    let type: String?
    let sessionID: String?
    let timestamp: String?
    let cwd: WorkingDirectory?
    let isMeta: Truthy?
    let isSidechain: Truthy?
    let message: Message?

    private enum CodingKeys: String, CodingKey {
        case type
        case sessionID = "sessionId"
        case timestamp, cwd
        case isMeta, isSidechain, message
    }
}

// cwd: Python keeps a non-empty string as-is, else str()s a truthy non-null
// value. Models that exact behaviour. A JSON null decodes to .none here because
// the field itself is optional in Event; but a present JSON null still needs to
// be distinguishable from a string, so we decode through a wrapper that records
// whether the underlying value was a usable string or a stringified other.

/// An event's `cwd`, resolved per Python's lenient working-directory semantics.
struct WorkingDirectory: Decodable {
    let raw: JSONValue
    init(from decoder: Decoder) throws {
        raw = try JSONValue(from: decoder)
    }

    /// The working directory per Python `firstCwd` semantics: a non-empty
    /// string, or the `str()` of a truthy non-null value; `nil` otherwise.
    var resolved: String? {
        switch raw {
        case .null:
            return nil
        case let .string(string):
            return string.isEmpty ? nil : string
        default:
            return raw.pythonString
        }
    }
}

// --------------------------------------------------------------------------- //
// Number formatting — match Python f"{n:,}" and f"{round(x,1)}".
// --------------------------------------------------------------------------- //

extension Int {
    /// This integer formatted with thousands separators, like Python `f"{n:,}"`.
    var groupedDigits: String {
        let isNegative = self < 0
        var digits = ""
        var count = 0
        for character in String(abs(self)).reversed() {
            if count != 0 && count % 3 == 0 { digits.append(",") }
            digits.append(character)
            count += 1
        }
        digits = String(digits.reversed())
        return isNegative ? "-" + digits : digits
    }
}

extension Double {
    // f"{round(x,1)}" is byte-identical to f"{x:.1f}" for these ranges (both
    // correctly-rounded, round-half-to-even via the C library).

    /// This value formatted to one decimal place, like Python `f"{round(x,1)}"`.
    var minutesString: String {
        String(format: "%.1f", self)
    }
}

// --------------------------------------------------------------------------- //
// JSON decoding helpers
// --------------------------------------------------------------------------- //

let jsonDecoder = JSONDecoder()

extension String {
    /// The event decoded from this transcript line, or `nil` if it is not a
    /// JSON object that decodes.
    ///
    /// Per-line robustness: a bad line is skipped, not fatal.
    var decodedEvent: Event? {
        guard let data = data(using: .utf8) else { return nil }
        return try? jsonDecoder.decode(Event.self, from: data)
    }
}

// --------------------------------------------------------------------------- //
// Locating the transcript
// --------------------------------------------------------------------------- //

/// The `~/.claude/projects` root that holds every session transcript.
func projectsRoot() -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".claude").appendingPathComponent("projects")
}

/// Reads the transcript at `path` into its decoded events, skipping bad lines.
func readJSONL(_ path: URL) -> [Event] {
    var events: [Event] = []
    guard let contents = try? String(contentsOf: path, encoding: .utf8) else { return events }
    for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { continue }
        if let event = line.decodedEvent {
            events.append(event)
        }
    }
    return events
}

/// Returns the working directory recorded in the transcript's first 50 lines.
func firstCwd(_ path: URL) -> String? {
    guard let contents = try? String(contentsOf: path, encoding: .utf8) else { return nil }
    var lineIndex = 0
    for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
        if lineIndex > 50 { break }
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        lineIndex += 1
        if line.isEmpty { continue }
        guard let event = line.decodedEvent else { continue }
        if let resolved = event.cwd?.resolved {
            return resolved
        }
    }
    return nil
}

/// Finds the transcript file for `sessionID`, excluding subagent transcripts.
func findSession(byID sessionID: String) -> URL? {
    let root = projectsRoot()
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: root.path) { return nil }
    guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
    for case let url as URL in enumerator {
        if url.lastPathComponent == "\(sessionID).jsonl" {
            if url.deletingLastPathComponent().lastPathComponent != "subagents" {
                return url
            }
        }
    }
    return nil
}

/// Finds the most-recently-modified session transcript, preferring one whose
/// working directory matches `preferredCwd`.
func findLatestSession(preferredCwd: String?) -> URL? {
    let root = projectsRoot()
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: root.path) { return nil }
    guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
    var candidates: [URL] = []
    for case let url as URL in enumerator {
        guard url.pathExtension == "jsonl" else { continue }
        let parent = url.deletingLastPathComponent()
        if parent.lastPathComponent == "subagents" { continue }
        if parent.deletingLastPathComponent().lastPathComponent != "projects" { continue }
        candidates.append(url)
    }
    if candidates.isEmpty { return nil }
    func modificationTime(_ url: URL) -> TimeInterval {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate?.timeIntervalSince1970 ?? 0
    }
    candidates.sort { modificationTime($0) > modificationTime($1) }
    if let preferredCwd = preferredCwd {
        let wanted = preferredCwd.trimmingTrailingSlashes
        for candidate in candidates {
            if let cwd = firstCwd(candidate), cwd.trimmingTrailingSlashes == wanted {
                return candidate
            }
        }
    }
    return candidates[0]
}

extension String {
    /// This string with any trailing `/` characters removed.
    var trimmingTrailingSlashes: String {
        var slice = Substring(self)
        while slice.hasSuffix("/") { slice = slice.dropLast() }
        return String(slice)
    }
}

// --------------------------------------------------------------------------- //
// Tool-name normalization
// --------------------------------------------------------------------------- //

let toolNameMap: [String: String] = [
    "Read": "view", "Edit": "edit", "Write": "create", "Glob": "glob",
    "Grep": "grep", "Bash": "shell", "Skill": "skill", "Agent": "agent",
    "Task": "agent", "WebFetch": "web_fetch", "WebSearch": "web_search",
    "NotebookEdit": "edit", "TodoWrite": "todo", "AskUserQuestion": "ask_user",
]

extension String {
    /// This tool name mapped to its canonical short form, lowercased otherwise.
    var normalizedToolName: String {
        toolNameMap[self] ?? lowercased()
    }
}

// --------------------------------------------------------------------------- //
// Error extraction
// --------------------------------------------------------------------------- //

// The case-insensitive error-trigger pattern (`Patterns.errorTrigger`) and the
// categorization regexes are namespaced together in `enum Patterns`, defined
// below near the categorization logic.

extension String {
    /// This string truncated to its first `limit` Unicode code points, like
    /// Python `s[:limit]`.
    func truncated(to limit: Int) -> String {
        if count <= limit { return self }
        return String(prefix(limit))
    }

    /// This string split on Python `str.splitlines()` boundaries.
    ///
    /// Splits on `\n`, `\r`, `\r\n`, and several Unicode line boundaries.
    var pythonLines: [String] {
        var result: [String] = []
        var current = ""
        let scalars = Array(unicodeScalars)
        var index = 0
        let breaks: Set<UInt32> = [0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x85, 0x2028, 0x2029]
        while index < scalars.count {
            let scalar = scalars[index]
            if breaks.contains(scalar.value) {
                // Handle CRLF as a single break.
                if scalar.value == 0x0D && index + 1 < scalars.count && scalars[index + 1].value == 0x0A {
                    index += 1
                }
                result.append(current)
                current = ""
            } else {
                current.unicodeScalars.append(scalar)
            }
            index += 1
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}


/// A non-empty error flag paired with up to five de-duplicated error lines
/// extracted from tool output `text`.
func errorSummary(_ text: String?) -> (isError: Bool, lines: [String]) {
    guard let text = text, !text.isEmpty else { return (false, []) }
    if !text.contains(Patterns.errorTrigger) { return (false, []) }
    var summaries: [String] = []
    // Python str.splitlines() splits on a broader set of boundaries.
    for rawLine in text.pythonLines {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.contains(Patterns.errorTrigger) { continue }
        if let match = line.firstMatch(of: #/error:\s*(.+)/#) {
            let captured = String(match.1)   // capture group 1, mirrors re.search(...).group(1)
            summaries.append(captured.trimmingCharacters(in: .whitespacesAndNewlines).truncated(to: 140))
        } else if line.contains("BUILD FAILED") {
            summaries.append("** BUILD FAILED **")
        } else if let match = line.firstMatch(of: #/Command (\S+) failed/#) {
            summaries.append(String(match.0))   // whole match, mirrors re.search(...).group(0)
        } else if line.contains("linker command failed") {
            summaries.append("linker command failed")
        } else {
            summaries.append(line.truncated(to: 140))
        }
        if summaries.count >= 5 { break }
    }
    // de-dupe preserving order
    var seen = Set<String>()
    var unique: [String] = []
    for summary in summaries {
        if !seen.contains(summary) { seen.insert(summary); unique.append(summary) }
    }
    return (true, unique)
}

// --------------------------------------------------------------------------- //
// Parsing
// --------------------------------------------------------------------------- //

/// Returns the first genuine user prompt from `events`, or a placeholder.
func extractPrompt(_ events: [Event]) -> String {
    for event in events {
        if event.type != "user" { continue }
        if event.isMeta?.value == true { continue }
        if event.isSidechain?.value == true { continue }
        let content = event.message?.content
        var candidate: String? = nil
        if let string = content?.stringValue {
            candidate = string
        } else if let blocks = content?.arrayValue {
            let hasToolResult = blocks.contains { if case .toolResult = $0 { return true } else { return false } }
            var texts: [String] = []
            for block in blocks {
                if case let .text(text) = block {
                    texts.append(text)
                }
            }
            if !hasToolResult && !texts.isEmpty {
                candidate = texts.joined(separator: "\n")
            }
        }
        guard let candidate = candidate, !candidate.isEmpty else { continue }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        // Anchored at ^, so a "match anywhere" via .contains is still start-anchored.
        if trimmed.contains(#/^<(local-)?command-(name|message|args|stdout)>/#) { continue }
        if trimmed.hasPrefix("<local-command-caveat>") { continue }
        return candidate
    }
    return "(no prompt found)"
}

/// A single tool invocation within a turn.
struct Tool {
    var name: String
    var args: JSONValue   // the tool_use `input` object (or .object([:]))
    var isError: Bool
    var errors: [String]
}

/// One assistant turn: its tool calls, token usage, and classification.
final class Turn {
    var number: Int
    var tools: [Tool] = []
    var outputTokens: Int = 0
    var cacheRead: Int = 0
    var cacheCreate: Int = 0
    var skills: [String] = []
    var agents: [String] = []
    var category: String = "other"
    init(number: Int) { self.number = number }
}

/// A dispatched subagent: its identity, turns, and duration.
struct Subagent {
    var id: String
    var type: String
    var description: String
    var turns: [Turn]
    var duration: Double
}

/// A fully-parsed session: metadata, prompt, turns, and subagents.
struct Parsed {
    var sessionID: String
    var model: String
    var durationMin: Double
    var prompt: String
    var turns: [Turn]
    var subagents: [Subagent]
}

// Agent metadata sidecar (stable keys, synthesized Decodable). Both fields are
// optional so absence is tolerated; presence vs. absence drives the fallback.

/// The `agent-*.meta.json` sidecar describing a dispatched subagent.
struct AgentMeta: Decodable {
    let agentType: String?
    let description: String?
}

/// Parses an ISO timestamp like `"2026-06-05T04:44:27.709Z"` into seconds since
/// the epoch, or `nil` on failure.
///
/// Mirrors `datetime.fromisoformat(ts.replace("Z","+00:00"))`.
func parseTimestamp(_ timestamp: String) -> Double? {
    let normalized = timestamp.replacingOccurrences(of: "Z", with: "+00:00")
    // Expect: YYYY-MM-DDTHH:MM:SS[.ffffff](+HH:MM | -HH:MM)
    // datetime.fromisoformat is strict but the inputs are well-formed; parse manually.
    guard let timeMarker = normalized.firstIndex(of: "T") else { return nil }
    let datePart = String(normalized[normalized.startIndex..<timeMarker])
    let rest = String(normalized[normalized.index(after: timeMarker)...])
    // rest = HH:MM:SS[.frac][tz]
    // Find tz offset: look for '+' or '-' after the time (skip first char).
    var timeZoneSign: Character? = nil
    var timeZoneIndex: String.Index? = nil
    let restCharacters = Array(rest)
    var characterIndex = 0
    while characterIndex < restCharacters.count {
        let character = restCharacters[characterIndex]
        if (character == "+" || character == "-") && characterIndex > 0 {
            timeZoneSign = character
            timeZoneIndex = rest.index(rest.startIndex, offsetBy: characterIndex)
            break
        }
        characterIndex += 1
    }
    var timePart = rest
    var timeZoneSeconds = 0.0
    if let timeZoneIndex = timeZoneIndex, let sign = timeZoneSign {
        timePart = String(rest[rest.startIndex..<timeZoneIndex])
        let offset = String(rest[rest.index(after: timeZoneIndex)...]) // HH:MM
        let components = offset.split(separator: ":")
        if components.count == 2, let hours = Double(components[0]), let minutes = Double(components[1]) {
            timeZoneSeconds = (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1)
        }
    }
    // datePart = YYYY-MM-DD
    let dateComponents = datePart.split(separator: "-")
    guard dateComponents.count == 3,
          let year = Int(dateComponents[0]),
          let month = Int(dateComponents[1]),
          let day = Int(dateComponents[2]) else { return nil }
    // timePart = HH:MM:SS[.frac]
    let timeComponents = timePart.split(separator: ":")
    guard timeComponents.count == 3,
          let hour = Int(timeComponents[0]),
          let minute = Int(timeComponents[1]) else { return nil }
    let secondString = String(timeComponents[2])
    var second = 0
    var fraction = 0.0
    if let dot = secondString.firstIndex(of: ".") {
        second = Int(secondString[secondString.startIndex..<dot]) ?? 0
        let fractionString = String(secondString[secondString.index(after: dot)...])
        if let parsed = Double("0." + fractionString) { fraction = parsed }
    } else {
        second = Int(secondString) ?? 0
    }
    // Days from civil (proleptic Gregorian) -> days since 1970-01-01.
    let epochDay = daysFromCivil(year, month, day)
    let total = Double(epochDay) * 86400.0
        + Double(hour) * 3600.0 + Double(minute) * 60.0 + Double(second) + fraction
        - timeZoneSeconds
    return total
}

/// Returns the day count since 1970-01-01 via Howard Hinnant's days_from_civil.
func daysFromCivil(_ year0: Int, _ month: Int, _ day: Int) -> Int {
    let year = month <= 2 ? year0 - 1 : year0
    let era = (year >= 0 ? year : year - 399) / 400
    let yearOfEra = year - era * 400
    let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146097 + dayOfEra - 719468
}

/// Parses the session transcript at `path` into a `Parsed`, recursing into
/// subagent transcripts unless suppressed.
func parseSession(_ path: URL, isSubagent: Bool = false, includeSubagents: Bool = true) -> Parsed {
    let events = readJSONL(path)
    let prompt = extractPrompt(events)
    let stem = path.deletingPathExtension().lastPathComponent
    // Python: sid = (events[0].get("sessionId") if events else None) or path.stem
    // If sessionId is missing/empty/None, fall back to stem.
    var sessionID: String = stem
    if let first = events.first, let id = first.sessionID, !id.isEmpty {
        sessionID = id
    }

    // model
    var model = "(unknown)"
    if let firstAssistant = events.first(where: { $0.type == "assistant" }) {
        if let assistantModel = firstAssistant.message?.model {
            model = assistantModel
        } else {
            model = "(unknown)"
        }
    }

    // duration
    var times: [Double] = []
    for event in events {
        if let timestamp = event.timestamp, !timestamp.isEmpty {
            if let time = parseTimestamp(timestamp) {
                times.append(time)
            }
        }
    }
    let durationMin = times.count >= 2 ? (times[times.count - 1] - times[0]) / 60.0 : 0.0

    // tool_results keyed by tool_use_id
    var toolResults: [String: (text: String, isError: Bool)] = [:]
    for event in events {
        if event.type == "user", let blocks = event.message?.content?.arrayValue {
            for block in blocks {
                if case let .toolResult(toolUseID, content, isError) = block {
                    var text = ""
                    if let string = content?.stringValue {
                        text = string
                    } else if let contentBlocks = content?.arrayValue {
                        var parts: [String] = []
                        for item in contentBlocks {
                            if let type = item["type"]?.stringValue, type == "text" {
                                parts.append(item["text"]?.stringValue ?? "")
                            }
                        }
                        text = parts.joined(separator: "\n")
                    }
                    let key = stringifyID(toolUseID)
                    toolResults[key] = (text, isError.value)
                }
            }
        }
    }

    var turns: [Turn] = []
    var turnNumber = 0
    for event in events {
        if event.type != "assistant" { continue }
        if !isSubagent {
            if event.isSidechain?.value == true { continue }
        }
        turnNumber += 1
        let usage = event.message?.usage
        let turn = Turn(number: turnNumber)
        turn.outputTokens = usage?.outputTokens ?? 0
        turn.cacheRead = usage?.cacheReadInputTokens ?? 0
        turn.cacheCreate = usage?.cacheCreationInputTokens ?? 0
        if let blocks = event.message?.content?.arrayValue {
            for block in blocks {
                guard case let .toolUse(id, name, input) = block else { continue }
                let callID = stringifyID(id)
                let args = input
                let normalizedName = (name ?? "").normalizedToolName
                var tool = Tool(name: normalizedName, args: args, isError: false, errors: [])
                if normalizedName == "skill", let skill = args["skill"], !skill.isNull {
                    turn.skills.append(skill.pythonString)
                }
                if normalizedName == "agent" {
                    if let subagentType = args["subagent_type"], !subagentType.isNull {
                        turn.agents.append(subagentType.pythonString)
                    } else {
                        turn.agents.append("general-purpose")
                    }
                }
                if let result = toolResults[callID] {
                    let (hasError, errors) = errorSummary(result.text)
                    if result.isError || hasError {
                        tool.isError = true
                        tool.errors = errors
                    }
                }
                turn.tools.append(tool)
            }
        }
        turns.append(turn)
    }

    var subagents: [Subagent] = []
    if includeSubagents && !isSubagent {
        let subagentsDir = path.deletingPathExtension()
            .deletingLastPathComponent()
            .appendingPathComponent(stem)
            .appendingPathComponent("subagents")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: subagentsDir.path) {
            // sorted(sub_dir.glob("agent-*.jsonl")) — non-recursive, lexical sort by full path.
            var agentFiles: [URL] = []
            if let entries = try? fileManager.contentsOfDirectory(at: subagentsDir, includingPropertiesForKeys: nil) {
                for url in entries {
                    let name = url.lastPathComponent
                    if name.hasPrefix("agent-") && name.hasSuffix(".jsonl") {
                        agentFiles.append(url)
                    }
                }
            }
            // Python sorts Path objects by their string value (full path).
            agentFiles.sort { $0.path < $1.path }
            for agentFile in agentFiles {
                let agentStem = agentFile.deletingPathExtension().lastPathComponent
                let agentID = agentStem.hasPrefix("agent-")
                    ? String(agentStem.dropFirst("agent-".count)) : agentStem
                var meta: AgentMeta? = nil
                let metaPath = agentFile.deletingLastPathComponent()
                    .appendingPathComponent("agent-\(agentID).meta.json")
                if fileManager.fileExists(atPath: metaPath.path) {
                    if let data = try? Data(contentsOf: metaPath),
                       let decoded = try? jsonDecoder.decode(AgentMeta.self, from: data) {
                        meta = decoded
                    }
                }
                let sub = parseSession(agentFile, isSubagent: true, includeSubagents: false)
                // Python: meta.get("agentType", "(unknown)") / meta.get("description", "").
                // Missing key -> default; present (even if non-string) -> str(). Here a
                // present-but-non-string agentType would have failed String decode and
                // landed as nil; the real data is always a string, matching Python.
                let agentType = meta?.agentType ?? "(unknown)"
                let agentDescription = meta?.description ?? ""
                subagents.append(Subagent(
                    id: agentID,
                    type: agentType,
                    description: agentDescription,
                    turns: sub.turns,
                    duration: sub.durationMin))
            }
        }
    }

    return Parsed(sessionID: sessionID, model: model, durationMin: durationMin,
                  prompt: prompt, turns: turns, subagents: subagents)
}

/// The Python `str(x)` rendering of an id-shaped value; `nil` becomes `"None"`.
func stringifyID(_ value: JSONValue?) -> String {
    guard let value = value else { return "None" }
    return value.pythonString
}

// --------------------------------------------------------------------------- //
// Categorization
// --------------------------------------------------------------------------- //

extension Tool {
    /// A Boolean value indicating whether this is a shell (Bash) tool call.
    var isShell: Bool { name == "shell" }

    /// The shell command string for a shell tool, or the empty string otherwise.
    var command: String {
        if isShell {
            if let value = args["command"], !value.isNull {
                if let string = value.stringValue { return string }
                return value.pythonString
            }
            return ""
        }
        return ""
    }
}

// Native Swift Regex literals. Extended `#/.../#` form throughout: it needs no
// escaping for the `/` in `Contents/MacOS/`, and (unlike bare `/.../`) it parses
// under the plain `swift` interpreter without -enable-bare-slash-regex. All
// case-sensitive, matching the original NSRegularExpression default — except
// `errorTrigger`, which is case-insensitive via the inline `(?i)`.

/// The classification and error-detection regexes used across the analyzer.
enum Patterns {
    static let helper = #/build-and-run\.sh|build-and-run\b|BuildAndRun/#
    static let build = #/\bxcodebuild\b|build-and-run|BuildAndRun|\btuist\b|\bswift build\b/#
    static let run = #/\bopen\s+.*\.app|(?:build-and-run|BuildAndRun)(?!.*--skip-run)|Contents\/MacOS\//#
    static let diagnostic = #/xcresulttool|-showBuildSettings|DiagnosticReports|log stream|grep .*error|DerivedData|rm -rf .*build|codesign --verify|spctl/#
    static let scaffold = #/tuist generate|tuist install|mkdir /#
    static let git = #/\bgit\b/#
    static let xcodebuild = #/\bxcodebuild\b/#
    static let clean = #/rm -rf .*build|DerivedData/#
    static let errorTrigger = #/(?i)error:|BUILD FAILED|fatal error|Command .* failed|linker command failed|code object is not signed|Undefined symbol|cannot find/#
}

extension Turn {
    /// The category label classifying this turn's activity.
    ///
    /// - Complexity: O(*t*) in the turn's tool count; each tool is scanned and a
    ///   handful of regexes are matched against its command.
    var classified: String {
        let names = tools.map { $0.name }
        let hasSkill = !skills.isEmpty
        let hasBuild = tools.contains { $0.isShell && $0.command.contains(Patterns.build) }
        let hasBuildError = tools.contains { $0.isError && $0.isShell && $0.command.contains(Patterns.build) }
        let hasRun = tools.contains { $0.isShell && $0.command.contains(Patterns.run) }
        let hasGit = tools.contains { $0.isShell && $0.command.contains(Patterns.git) }
        let isDiagnostic = tools.contains { $0.isShell && $0.command.contains(Patterns.diagnostic) }
        let hasScaffold = tools.contains { $0.command.contains(Patterns.scaffold) }
        let hasCreate = names.contains("create")
        let hasEdit = names.contains("edit")
        let hasView = names.contains("view")
        let hasAgent = names.contains("agent")

        if hasSkill && names.count <= 2 { return "skill-load" }
        if hasGit && !hasBuild { return "git" }
        if hasBuild && hasBuildError { return "build-fix" }
        if hasBuild && !hasBuildError { return "build-ok" }
        if hasRun { return "run" }
        if isDiagnostic && !hasEdit { return "diagnosing" }
        if hasScaffold { return "scaffold" }
        if hasAgent { return "subagent" }
        if hasCreate && !hasEdit { return "code-create" }
        if hasEdit { return "code-edit" }
        if hasView && !hasEdit && !hasCreate { return "explore" }
        if names.isEmpty { return "thinking" }
        return "other"
    }
}

// --------------------------------------------------------------------------- //
// Rendering
// --------------------------------------------------------------------------- //

let categoryLabels: [String: String] = [
    "skill-load": "Skill loading", "explore": "Reading/exploring",
    "scaffold": "Scaffolding", "code-create": "Creating files",
    "code-edit": "Editing code", "build-ok": "Build (success)",
    "build-fix": "Build (failed)", "run": "Running app", "git": "Git operations",
    "thinking": "Thinking (no tools)", "diagnosing": "Diagnosing errors",
    "subagent": "Subagent dispatch", "other": "Other",
]

extension String {
    /// The POSIX basename of this path: the text after the last `/`.
    var basename: String {
        if let index = lastIndex(of: "/") {
            return String(self[self.index(after: index)...])
        }
        return self
    }
}

extension JSONValue {
    /// The string value of `key`, stringified per Python `str()`, or `nil` when
    /// the member is missing or null.
    func string(forKey key: String) -> String? {
        guard let value = self[key], !value.isNull else { return nil }
        if let string = value.stringValue { return string }
        return value.pythonString
    }

    /// The value of `key` rendered per Python truthiness, or `nil` when it is
    /// missing, null, or falsey.
    func truthyString(forKey key: String) -> String? {
        guard let value = self[key], !value.isNull else { return nil }
        switch value {
        case let .string(string):
            return string.isEmpty ? nil : string
        case let .bool(bool):
            return bool ? "True" : nil
        case let .int(int):
            return int == 0 ? nil : String(int)
        case let .double(double):
            return double == 0 ? nil : value.pythonString
        case let .array(array):
            return array.isEmpty ? nil : value.pythonString
        case let .object(object):
            return object.isEmpty ? nil : value.pythonString
        case .null:
            return nil
        }
    }
}

extension Turn {
    /// The one-line markdown rendering of this turn's tools and skills.
    var toolListDescription: String {
        var parts: [String] = []
        for tool in tools {
            let errorMark = tool.isError ? " ❌" : ""
            var summary = ""
            let args = tool.args
            if tool.name == "shell" {
                let command = args.string(forKey: "command") ?? ""
                let firstLine = command.pythonLines.first ?? ""
                summary = firstLine.truncated(to: 60)
            } else if let path = args.truthyString(forKey: "path") ?? args.truthyString(forKey: "file_path") {
                summary = path.basename
            } else if tool.name == "skill" {
                summary = stringifyMaybe(args["skill"])
            } else if tool.name == "agent" {
                summary = stringifyMaybe(args["subagent_type"])
            } else if let pattern = args.truthyString(forKey: "pattern") {
                summary = pattern
            }
            if !summary.isEmpty {
                parts.append("\(tool.name)(\(summary))\(errorMark)")
            } else {
                parts.append("\(tool.name)\(errorMark)")
            }
        }
        let skillsTag = skills.isEmpty ? "" : " [skill: \(skills.joined(separator: ","))]"
        return parts.joined(separator: ", ") + skillsTag
    }
}

/// The Python `str(x)` rendering of a summary value; `nil`/missing becomes `""`.
func stringifyMaybe(_ value: JSONValue?) -> String {
    guard let value = value, !value.isNull else { return "" }
    if let string = value.stringValue { return string }
    return value.pythonString
}

/// Renders the parsed session into the final markdown report body.
func render(_ parsed: Parsed, includeSubagents: Bool) -> String {
    var allTurns: [Turn] = parsed.turns
    if includeSubagents {
        for subagent in parsed.subagents {
            allTurns += subagent.turns
        }
    }

    let buildOk = allTurns.filter { $0.category == "build-ok" }.count
    let buildFix = allTurns.filter { $0.category == "build-fix" }.count
    let attempts = buildOk + buildFix

    let usedHelper = allTurns.contains { turn in turn.tools.contains { $0.isShell && $0.command.contains(Patterns.helper) } }
    let usedRawXcodebuild = allTurns.contains { turn in turn.tools.contains {
        $0.isShell && $0.command.contains(Patterns.xcodebuild) && !$0.command.contains(Patterns.helper)
    } }
    let buildStatus: String
    if usedHelper && !usedRawXcodebuild {
        buildStatus = "Used build-and-run.sh for all builds"
    } else if usedHelper && usedRawXcodebuild {
        buildStatus = "Mixed: raw xcodebuild and build-and-run.sh"
    } else if usedRawXcodebuild {
        buildStatus = "NOT USED: raw xcodebuild only, never used build-and-run.sh"
    } else {
        buildStatus = "No build commands detected"
    }

    // build errors
    var buildErrors: [(Int, [String])] = []
    for turn in allTurns {
        for tool in turn.tools {
            if tool.isError && tool.isShell && tool.command.contains(Patterns.build) && !tool.errors.isEmpty {
                buildErrors.append((turn.number, tool.errors))
            }
        }
    }

    // skills timeline
    var skillTimeline: [(Int, String, String)] = []
    for turn in parsed.turns {
        for skill in turn.skills {
            skillTimeline.append((turn.number, skill, "parent"))
        }
    }
    for subagent in parsed.subagents {
        for turn in subagent.turns {
            for skill in turn.skills {
                skillTimeline.append((turn.number, skill, "subagent:\(subagent.type)"))
            }
        }
    }

    // token totals
    let outputTokens = allTurns.reduce(0) { $0 + $1.outputTokens }
    let cacheReadTokens = allTurns.reduce(0) { $0 + $1.cacheRead }
    let cacheCreateTokens = allTurns.reduce(0) { $0 + $1.cacheCreate }

    // category table — preserve dict-insertion order then stable sort by turns desc.
    var categoryOrder: [String] = []
    var categoryCounts: [String: (turns: Int, tokens: Int)] = [:]
    for turn in allTurns {
        let category = turn.category
        if categoryCounts[category] == nil {
            categoryCounts[category] = (0, 0)
            categoryOrder.append(category)
        }
        categoryCounts[category]!.turns += 1
        categoryCounts[category]!.tokens += turn.outputTokens
    }
    // Python sorted(..., key=turns, reverse=True) is stable: ties keep insertion order.
    let categoryRows = stableSortByTurnsDescending(order: categoryOrder, counts: categoryCounts)

    // stuck patterns
    var stuck: [String] = []
    var readsOrder: [String] = []
    var reads: [String: Int] = [:]
    for turn in allTurns {
        for tool in turn.tools {
            if tool.name == "view" {
                if let path = tool.args.truthyString(forKey: "path") ?? tool.args.truthyString(forKey: "file_path") {
                    let file = path.basename
                    if reads[file] == nil { reads[file] = 0; readsOrder.append(file) }
                    reads[file]! += 1
                }
            }
        }
    }
    var excessive: [(String, Int)] = []
    for file in readsOrder {
        let count = reads[file]!
        if count >= 3 { excessive.append((file, count)) }
    }
    if !excessive.isEmpty {
        let joined = excessive.map { "\($0.0) (\($0.1)x)" }.joined(separator: ", ")
        stuck.append("Repeated file reads: " + joined)
    }
    var consecutive = 0
    var maxConsecutive = 0
    for turn in allTurns {
        if turn.category == "build-fix" {
            consecutive += 1; maxConsecutive = max(maxConsecutive, consecutive)
        } else if turn.category == "build-ok" {
            consecutive = 0
        }
    }
    if maxConsecutive >= 3 {
        stuck.append("Build loop: \(maxConsecutive) consecutive build failures before success")
    }
    var cleans = 0
    for turn in allTurns {
        for tool in turn.tools {
            if tool.command.contains(Patterns.clean) { cleans += 1 }
        }
    }
    if cleans >= 2 {
        stuck.append("Cleaned build/DerivedData \(cleans)x (suggests stale build state)")
    }

    // ----- markdown -----
    var markdown: [String] = []
    markdown.append("# Session Analysis Report\n")
    markdown.append("## Overview\n")
    markdown.append("| Field | Value |")
    markdown.append("|-------|-------|")
    markdown.append("| Harness | Claude Code |")
    markdown.append("| Session ID | `\(parsed.sessionID)` |")
    markdown.append("| Model | \(parsed.model) |")
    markdown.append("| Duration | \(parsed.durationMin.minutesString) min |")
    markdown.append("| Turns (parent) | \(parsed.turns.count) |")
    if includeSubagents && !parsed.subagents.isEmpty {
        let subagentTurns = parsed.subagents.reduce(0) { $0 + $1.turns.count }
        markdown.append("| Subagents | \(parsed.subagents.count) (\(subagentTurns) turns) |")
    }
    markdown.append("| Output tokens (combined) | \(outputTokens.groupedDigits) |")
    markdown.append("| Cache read tokens | \(cacheReadTokens.groupedDigits) |")
    markdown.append("| Cache create tokens | \(cacheCreateTokens.groupedDigits) |")
    markdown.append("")

    markdown.append("## Prompt\n")
    var prompt = parsed.prompt
    if prompt.count > 500 {
        prompt = String(prompt.prefix(500)) + "..."
    }
    markdown.append("```"); markdown.append(prompt); markdown.append("```"); markdown.append("")

    markdown.append("## Turn Breakdown\n")
    if includeSubagents && !parsed.subagents.isEmpty {
        markdown.append("_Combined parent + \(parsed.subagents.count) subagent transcript(s)._\n")
    }
    markdown.append("| Category | Turns | Output Tokens |")
    markdown.append("|----------|------:|--------------:|")
    for (category, entry) in categoryRows {
        let label = categoryLabels[category] ?? category
        markdown.append("| \(label) | \(entry.turns) | \(entry.tokens.groupedDigits) |")
    }
    markdown.append("")

    markdown.append("## Skills\n")
    if !skillTimeline.isEmpty {
        markdown.append("**Invoked:**")
        for (number, skill, origin) in skillTimeline {
            let tag = origin == "parent" ? "" : " _(in \(origin))_"
            markdown.append("- Turn \(number): `\(skill)`\(tag)")
        }
    } else {
        markdown.append("_No skills were invoked during this session._")
    }
    markdown.append("")

    if includeSubagents && !parsed.subagents.isEmpty {
        markdown.append("## Subagents\n")
        markdown.append("| Agent ID | Type | Turns | Duration | Description |")
        markdown.append("|---|---|---:|---:|---|")
        for subagent in parsed.subagents {
            var description = subagent.description
            if description.count > 60 {
                description = String(description.prefix(60)) + "..."
            }
            markdown.append("| `\(subagent.id)` | \(subagent.type) | \(subagent.turns.count) | \(subagent.duration.minutesString) min | \(description) |")
        }
        markdown.append("")
    }

    markdown.append("## Build Analysis\n")
    markdown.append("- **Attempts:** \(attempts) (\(buildOk) success, \(buildFix) failed)")
    markdown.append("- **build-and-run.sh:** \(buildStatus)")
    markdown.append("")
    if !buildErrors.isEmpty {
        markdown.append("**Build errors encountered:**\n")
        for (number, errors) in buildErrors {
            markdown.append("Turn \(number):")
            for error in errors {
                markdown.append("- `\(error)`")
            }
        }
        markdown.append("")
    }

    if !stuck.isEmpty {
        markdown.append("## Stuck Patterns\n")
        for pattern in stuck {
            markdown.append("- \(pattern)")
        }
        markdown.append("")
    }

    markdown.append("## Turn Detail\n")
    markdown.append("_Parent session._\n")
    markdown.append("| # | Category | Tokens | Tools |")
    markdown.append("|--:|----------|-------:|-------|")
    for turn in parsed.turns {
        markdown.append("| \(turn.number) | \(turn.category) | \(turn.outputTokens.groupedDigits) | \(turn.toolListDescription) |")
    }
    markdown.append("")
    if includeSubagents {
        for subagent in parsed.subagents {
            markdown.append("_Subagent `\(subagent.type)` (id `\(subagent.id)`)._\n")
            markdown.append("| # | Category | Tokens | Tools |")
            markdown.append("|--:|----------|-------:|-------|")
            for turn in subagent.turns {
                markdown.append("| \(turn.number) | \(turn.category) | \(turn.outputTokens.groupedDigits) | \(turn.toolListDescription) |")
            }
            markdown.append("")
        }
    }

    return markdown.joined(separator: "\n")
}

/// Returns the categories sorted by turn count descending, preserving insertion
/// order for ties.
func stableSortByTurnsDescending(order: [String], counts: [String: (turns: Int, tokens: Int)])
    -> [(String, (turns: Int, tokens: Int))] {
    let indexed = order.enumerated().map { (index, key) in (index, key, counts[key]!) }
    let sorted = indexed.sorted { lhs, rhs in
        if lhs.2.turns != rhs.2.turns { return lhs.2.turns > rhs.2.turns }
        return lhs.0 < rhs.0
    }
    return sorted.map { ($0.1, $0.2) }
}

// --------------------------------------------------------------------------- //
// Privacy notice
// --------------------------------------------------------------------------- //

let privacyNotice = """
## Privacy and sensitivity — read before sharing this file

**This report was generated from your live agent session and was NOT redacted.** Depending on what your session involved, it can include:

- File contents and paths the agent read or edited (source, configuration, secrets accidentally pasted into prompts, internal URLs, customer data).
- Your prompts verbatim — including any credentials, tokens, identifiers, or proprietary information you typed.
- Tool output — `git` history, environment values echoed by failing commands, build logs containing machine names and `/Users/<you>/…` paths, signing identities, and crash traces.
- Error messages quoting source code or stack traces from third-party libraries.

**You are responsible for the contents of this file.** Open it in your editor and read it end-to-end before attaching it to a public issue, posting it in chat, or sending it outside your organization. Redact anything sensitive (paths, names, secrets, signing identities, business logic). When in doubt, share excerpts rather than the whole file, or ask the agent to summarize the metrics instead.

"""

/// Returns `report` with the privacy notice inserted just before `## Overview`.
func insertPrivacy(_ report: String) -> String {
    let lines = report.components(separatedBy: "\n")
    var insertionIndex = 1
    for (index, line) in lines.enumerated() {
        if line.hasPrefix("## Overview") { insertionIndex = index; break }
    }
    var result: [String] = []
    result.append(contentsOf: lines[0..<insertionIndex])
    result.append(privacyNotice)
    result.append("")
    result.append(contentsOf: lines[insertionIndex...])
    return result.joined(separator: "\n")
}

// --------------------------------------------------------------------------- //
// Main
// --------------------------------------------------------------------------- //

/// Parses the command-line arguments into their resolved values.
func parseArgs(_ arguments: [String]) -> (sessionID: String?, eventsFile: String?, output: String?, skipSubagents: Bool) {
    var sessionID: String? = nil
    var eventsFile: String? = nil
    var output: String? = nil
    var skipSubagents = false
    var index = 1
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--session-id":
            index += 1; if index < arguments.count { sessionID = arguments[index] }
        case "--events-file":
            index += 1; if index < arguments.count { eventsFile = arguments[index] }
        case "--output":
            index += 1; if index < arguments.count { output = arguments[index] }
        case "--skip-subagents":
            skipSubagents = true
        default:
            if argument.hasPrefix("--session-id=") { sessionID = String(argument.dropFirst("--session-id=".count)) }
            else if argument.hasPrefix("--events-file=") { eventsFile = String(argument.dropFirst("--events-file=".count)) }
            else if argument.hasPrefix("--output=") { output = String(argument.dropFirst("--output=".count)) }
        }
        index += 1
    }
    return (sessionID, eventsFile, output, skipSubagents)
}

/// Runs the analyzer end-to-end and returns the process exit code.
func runMain() -> Int32 {
    let arguments = CommandLine.arguments
    let parsedArguments = parseArgs(arguments)
    let fileManager = FileManager.default

    var path: URL
    if let eventsFile = parsedArguments.eventsFile {
        path = URL(fileURLWithPath: eventsFile)
        if !fileManager.fileExists(atPath: path.path) {
            FileHandle.standardError.write("Events file not found: \(eventsFile)\n".data(using: .utf8)!)
            return 1
        }
    } else if let sessionID = parsedArguments.sessionID {
        guard let found = findSession(byID: sessionID) else {
            FileHandle.standardError.write(
                "Session id '\(sessionID)' not found under \(projectsRoot().path)\n".data(using: .utf8)!)
            return 1
        }
        path = found
    } else {
        let environmentSessionID = ProcessInfo.processInfo.environment["CLAUDE_SESSION_ID"]
        var found: URL? = nil
        if let environmentSessionID = environmentSessionID {
            found = findSession(byID: environmentSessionID)
        }
        if found == nil {
            found = findLatestSession(preferredCwd: fileManager.currentDirectoryPath)
        }
        guard let resolved = found else {
            FileHandle.standardError.write(
                "No Claude Code sessions found under \(projectsRoot().path)\n".data(using: .utf8)!)
            FileHandle.standardError.write(
                "If you use a different agent harness, this analyzer doesn't support it yet.\n".data(using: .utf8)!)
            return 1
        }
        path = resolved
    }

    let includeSubagents = !parsedArguments.skipSubagents
    let parsed = parseSession(path, isSubagent: false, includeSubagents: includeSubagents)
    for turn in parsed.turns {
        turn.category = turn.classified
    }
    for subagentIndex in 0..<parsed.subagents.count {
        for turn in parsed.subagents[subagentIndex].turns {
            turn.category = turn.classified
        }
    }

    let report = insertPrivacy(render(parsed, includeSubagents: includeSubagents && !parsed.subagents.isEmpty))

    if let output = parsedArguments.output {
        do {
            try report.write(toFile: output, atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write("Failed to write \(output): \(error)\n".data(using: .utf8)!)
            return 1
        }
        print("\nReport saved to: \(output)")
        let banner = String(repeating: "=", count: 64)
        let lines = [
            banner,
            " PRIVACY NOTICE — READ BEFORE SHARING \(output)",
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
