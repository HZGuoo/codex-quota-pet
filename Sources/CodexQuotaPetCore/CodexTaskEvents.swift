import Foundation

public enum CodexTaskEventKind: String, Codable, Sendable, Equatable {
    case completed
    case failed
    case interrupted
    case waitingForApproval
    case waitingForInput
}

public struct CodexTaskEvent: Codable, Sendable, Equatable {
    public let kind: CodexTaskEventKind
    public let threadID: String
    public let turnID: String?
    public let title: String
    public let detail: String?
    public let occurredAt: Date

    public init(
        kind: CodexTaskEventKind,
        threadID: String,
        turnID: String?,
        title: String,
        detail: String? = nil,
        occurredAt: Date = Date()
    ) {
        self.kind = kind
        self.threadID = threadID
        self.turnID = turnID
        self.title = title
        self.detail = detail
        self.occurredAt = occurredAt
    }

    public var dedupeKey: String {
        [threadID, turnID ?? "-", kind.rawValue].joined(separator: ":")
    }
}

public struct CodexTaskStatusSummary: Sendable, Equatable {
    public var runningCount: Int
    public var waitingApprovalCount: Int
    public var waitingInputCount: Int

    public init(
        runningCount: Int = 0,
        waitingApprovalCount: Int = 0,
        waitingInputCount: Int = 0
    ) {
        self.runningCount = max(0, runningCount)
        self.waitingApprovalCount = max(0, waitingApprovalCount)
        self.waitingInputCount = max(0, waitingInputCount)
    }

    public static let zero = CodexTaskStatusSummary()

    public var totalActiveCount: Int {
        runningCount + waitingApprovalCount + waitingInputCount
    }

    public var hasActivity: Bool { totalActiveCount > 0 }
}

public enum CodexTaskLiveState: String, Codable, Sendable, Equatable {
    case running
    case waitingForApproval
    case waitingForInput
}

public struct CodexTaskStatusSnapshot: Sendable, Equatable {
    public var byThreadID: [String: CodexTaskLiveState]

    public init(byThreadID: [String: CodexTaskLiveState] = [:]) {
        self.byThreadID = byThreadID.filter { !$0.key.isEmpty }
    }

    public static let empty = CodexTaskStatusSnapshot()

    public var summary: CodexTaskStatusSummary {
        var result = CodexTaskStatusSummary.zero
        for state in byThreadID.values {
            switch state {
            case .running:
                result.runningCount += 1
            case .waitingForApproval:
                result.waitingApprovalCount += 1
            case .waitingForInput:
                result.waitingInputCount += 1
            }
        }
        return result
    }

    /// Applies the latest App Server states over rollout-log fallback states.
    public func overlaying(
        _ authoritative: [String: CodexTaskLiveState],
        inactiveThreadIDs: Set<String> = []
    ) -> CodexTaskStatusSnapshot {
        var merged = byThreadID
        for threadID in inactiveThreadIDs {
            merged.removeValue(forKey: threadID)
        }
        for (threadID, state) in authoritative where !threadID.isEmpty {
            merged[threadID] = state
        }
        return CodexTaskStatusSnapshot(byThreadID: merged)
    }
}

public struct CodexThreadTaskStatusUpdate: Sendable, Equatable {
    public let threadID: String
    public let state: CodexTaskLiveState?

    public init(threadID: String, state: CodexTaskLiveState?) {
        self.threadID = threadID
        self.state = state
    }
}

public struct CodexRolloutParseState: Sendable, Equatable {
    public var threadID: String
    public var currentTurnID: String?
    public var currentTitle: String
    public var cwd: String?
    public var isSubagent: Bool
    public var isTurnActive: Bool
    public var waitingApprovalCallIDs: Set<String>
    public var waitingInputCallIDs: Set<String>

    public init(
        threadID: String = "unknown",
        currentTurnID: String? = nil,
        currentTitle: String = "Codex 任务",
        cwd: String? = nil,
        isSubagent: Bool = false,
        isTurnActive: Bool = false,
        waitingApprovalCallIDs: Set<String> = [],
        waitingInputCallIDs: Set<String> = []
    ) {
        self.threadID = threadID
        self.currentTurnID = currentTurnID
        self.currentTitle = currentTitle
        self.cwd = cwd
        self.isSubagent = isSubagent
        self.isTurnActive = isTurnActive
        self.waitingApprovalCallIDs = waitingApprovalCallIDs
        self.waitingInputCallIDs = waitingInputCallIDs
    }


}

public enum CodexRolloutEventParser {
    public static func parse(line: Data, state: inout CodexRolloutParseState) -> [CodexTaskEvent] {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String,
              let payload = object["payload"] as? [String: Any] else {
            return []
        }

        let timestamp = parseTimestamp(object["timestamp"] as? String) ?? Date()

        if type == "session_meta" {
            if let id = payload["id"] as? String { state.threadID = id }
            if let cwd = payload["cwd"] as? String { state.cwd = cwd }
            let source = payload["source"] as? [String: Any]
            state.isSubagent = payload["thread_source"] as? String == "subagent"
                || source?["subagent"] != nil
            return []
        }

        if type == "event_msg", let eventType = payload["type"] as? String {
            switch eventType {
            case "task_started":
                state.currentTurnID = payload["turn_id"] as? String
                state.isTurnActive = true
                state.waitingApprovalCallIDs.removeAll()
                state.waitingInputCallIDs.removeAll()
            case "user_message":
                if let message = payload["message"] as? String {
                    state.currentTitle = notificationTitle(from: message)
                }
            case "task_complete":
                state.isTurnActive = false
                state.waitingApprovalCallIDs.removeAll()
                state.waitingInputCallIDs.removeAll()
                guard !state.isSubagent else { return [] }
                let turnID = payload["turn_id"] as? String ?? state.currentTurnID
                return [makeEvent(
                    kind: .completed,
                    state: state,
                    turnID: turnID,
                    timestamp: eventDate(payload, key: "completed_at") ?? timestamp
                )]
            case "turn_aborted":
                state.isTurnActive = false
                state.waitingApprovalCallIDs.removeAll()
                state.waitingInputCallIDs.removeAll()
                guard !state.isSubagent else { return [] }
                let reason = payload["reason"] as? String
                let kind: CodexTaskEventKind = reason == "interrupted" ? .interrupted : .failed
                return [makeEvent(
                    kind: kind,
                    state: state,
                    turnID: payload["turn_id"] as? String ?? state.currentTurnID,
                    detail: reason,
                    timestamp: eventDate(payload, key: "completed_at") ?? timestamp
                )]
            default:
                break
            }
            return []
        }

        guard type == "response_item", !state.isSubagent else { return [] }
        let itemType = payload["type"] as? String
        let name = payload["name"] as? String
        let turnID = ((payload["internal_chat_message_metadata_passthrough"] as? [String: Any])?["turn_id"] as? String)
            ?? state.currentTurnID

        if itemType == "function_call_output" || itemType == "custom_tool_call_output",
           let callID = payload["call_id"] as? String {
            state.waitingApprovalCallIDs.remove(callID)
            state.waitingInputCallIDs.remove(callID)
            return []
        }

        if itemType == "function_call", name == "request_user_input" {
            if let callID = payload["call_id"] as? String {
                state.waitingInputCallIDs.insert(callID)
            }
            return [makeEvent(
                kind: .waitingForInput,
                state: state,
                turnID: turnID,
                detail: firstQuestion(from: payload["arguments"] as? String),
                timestamp: timestamp
            )]
        }

        if itemType == "function_call" || itemType == "custom_tool_call" {
            let arguments = (payload["arguments"] as? String) ?? (payload["input"] as? String) ?? ""
            if requiresApproval(arguments) {
                let callID = payload["call_id"] as? String
                if let callID { state.waitingApprovalCallIDs.insert(callID) }
                return [makeEvent(
                    kind: .waitingForApproval,
                    state: state,
                    turnID: turnID,
                    detail: callID.map { "approval-call:\($0)" },
                    timestamp: timestamp
                )]
            }
        }

        return []
    }

    public static func resolvedToolCallID(line: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "response_item",
              let payload = object["payload"] as? [String: Any],
              let type = payload["type"] as? String,
              type == "function_call_output" || type == "custom_tool_call_output" else {
            return nil
        }
        return payload["call_id"] as? String
    }

    private static func makeEvent(
        kind: CodexTaskEventKind,
        state: CodexRolloutParseState,
        turnID: String?,
        detail: String? = nil,
        timestamp: Date
    ) -> CodexTaskEvent {
        CodexTaskEvent(
            kind: kind,
            threadID: state.threadID,
            turnID: turnID,
            title: state.currentTitle,
            detail: detail,
            occurredAt: timestamp
        )
    }

    private static func eventDate(_ payload: [String: Any], key: String) -> Date? {
        if let value = payload[key] as? TimeInterval {
            return Date(timeIntervalSince1970: value)
        }
        if let value = payload[key] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(value))
        }
        return nil
    }

    private static func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func firstQuestion(from arguments: String?) -> String? {
        guard let arguments,
              let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let questions = object["questions"] as? [[String: Any]],
              let question = questions.first?["question"] as? String else {
            return nil
        }
        return String(question.prefix(120))
    }

    private static func requiresApproval(_ arguments: String) -> Bool {
        let compact = arguments.replacingOccurrences(of: " ", with: "")
        return compact.contains("\"sandbox_permissions\":\"require_escalated\"")
            || compact.contains("sandbox_permissions=\"require_escalated\"")
    }

    private static func notificationTitle(from message: String) -> String {
        let meaningfulLine = message
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("<") }
            ?? "Codex 任务"
        let collapsed = meaningfulLine
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if collapsed.count <= 52 { return collapsed }
        return String(collapsed.prefix(51)) + "…"
    }
}

public enum CodexAppServerTaskEventParser {
    public static func statusUpdate(_ notification: CodexNotification) -> CodexThreadTaskStatusUpdate? {
        guard let data = notification.params,
              let params = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        switch notification.method {
        case "thread/status/changed":
            guard let threadID = params["threadId"] as? String,
                  let status = params["status"] as? [String: Any],
                  let type = status["type"] as? String else { return nil }
            guard type == "active" else {
                return CodexThreadTaskStatusUpdate(threadID: threadID, state: nil)
            }
            let flags = status["activeFlags"] as? [String] ?? []
            let state: CodexTaskLiveState
            if flags.contains("waitingOnApproval") {
                state = .waitingForApproval
            } else if flags.contains("waitingOnUserInput") {
                state = .waitingForInput
            } else {
                state = .running
            }
            return CodexThreadTaskStatusUpdate(threadID: threadID, state: state)
        case "turn/completed":
            guard let turn = params["turn"] as? [String: Any],
                  let threadID = (params["threadId"] as? String) ?? (turn["threadId"] as? String) else {
                return nil
            }
            return CodexThreadTaskStatusUpdate(threadID: threadID, state: nil)
        default:
            return nil
        }
    }

    public static func parse(_ notification: CodexNotification) -> CodexTaskEvent? {
        guard let data = notification.params,
              let params = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        switch notification.method {
        case "thread/status/changed":
            guard let threadID = params["threadId"] as? String,
                  let status = params["status"] as? [String: Any],
                  let type = status["type"] as? String else { return nil }
            if type == "systemError" {
                return CodexTaskEvent(
                    kind: .failed,
                    threadID: threadID,
                    turnID: nil,
                    title: "Codex 任务",
                    detail: "系统错误"
                )
            }
            guard type == "active", let flags = status["activeFlags"] as? [String] else { return nil }
            if flags.contains("waitingOnApproval") {
                return CodexTaskEvent(
                    kind: .waitingForApproval,
                    threadID: threadID,
                    turnID: nil,
                    title: "Codex 任务"
                )
            }
            if flags.contains("waitingOnUserInput") {
                return CodexTaskEvent(
                    kind: .waitingForInput,
                    threadID: threadID,
                    turnID: nil,
                    title: "Codex 任务"
                )
            }
        case "turn/completed":
            guard let turn = params["turn"] as? [String: Any],
                  let status = turn["status"] as? String else { return nil }
            let kind: CodexTaskEventKind
            switch status {
            case "completed": kind = .completed
            case "failed": kind = .failed
            case "interrupted": kind = .interrupted
            default: return nil
            }
            let error = turn["error"] as? [String: Any]
            return CodexTaskEvent(
                kind: kind,
                threadID: (params["threadId"] as? String) ?? (turn["threadId"] as? String) ?? "app-server",
                turnID: turn["id"] as? String,
                title: "Codex 任务",
                detail: error?["message"] as? String
            )
        default:
            break
        }
        return nil
    }
}
