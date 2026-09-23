import Foundation

/// A point-in-time, privacy-preserving view of local Codex usage and activity.
///
/// The snapshot contains quota metadata, aggregate token counts, and task-state
/// counts. It intentionally contains no prompt text, response text, or credentials.
public struct CodexObservabilitySnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let capturedAt: Date
    public let quota: QuotaSnapshot
    public let tokenUsage: CodexTokenUsageSnapshot
    public let tasks: CodexTaskStatusSummary

    public init(
        schemaVersion: Int = 1,
        capturedAt: Date = Date(),
        quota: QuotaSnapshot,
        tokenUsage: CodexTokenUsageSnapshot,
        tasks: CodexTaskStatusSummary
    ) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.quota = quota
        self.tokenUsage = tokenUsage
        self.tasks = tasks
    }
}

/// High-level API for tools that need one complete Codex observability snapshot.
///
/// One instance owns one local `codex app-server` child process. Call `stop()`
/// when the consumer no longer needs it. The actor also stops the child process
/// when it is released.
public actor CodexObservabilityClient {
    private let appServer: CodexAppServerClient

    public init(appServer: CodexAppServerClient = CodexAppServerClient()) {
        self.appServer = appServer
    }

    public func start(settings: AppSettings = AppSettings()) async throws {
        try await appServer.start(settings: settings)
    }

    public func capture() async throws -> CodexObservabilitySnapshot {
        async let quota = appServer.readRateLimits()
        async let usage = appServer.readAccountTokenUsage()
        async let inventory = appServer.readThreadStatusInventory()

        return try await CodexObservabilitySnapshot(
            quota: quota,
            tokenUsage: usage,
            tasks: inventory.summary
        )
    }

    public func stop() async {
        await appServer.stop()
    }
}

public extension CodexThreadTaskStatusInventory {
    var summary: CodexTaskStatusSummary {
        CodexTaskStatusSnapshot(byThreadID: activeByThreadID).summary
    }
}

public enum CodexObservationExportFormat: String, CaseIterable, Sendable {
    case json
    case csv
}

public enum CodexObservationExporter {
    public static func export(
        _ snapshot: CodexObservabilitySnapshot,
        format: CodexObservationExportFormat
    ) throws -> Data {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(snapshot)
        case .csv:
            return Data(csv(snapshot).utf8)
        }
    }

    private static func csv(_ snapshot: CodexObservabilitySnapshot) -> String {
        var rows = [
            "category,name,window_minutes,used_percent,remaining_percent,resets_at,input_tokens,output_tokens,total_tokens,count"
        ]
        let iso = ISO8601DateFormatter()

        for bucket in snapshot.quota.buckets {
            for (index, window) in bucket.windows.enumerated() {
                rows.append([
                    "quota",
                    escape("\(bucket.displayName)-\(index + 1)"),
                    window.windowDurationMins.map(String.init) ?? "",
                    String(window.usedPercent),
                    String(window.remainingPercent),
                    window.resetDate.map(iso.string(from:)) ?? "",
                    "", "", "", ""
                ].joined(separator: ","))
            }
        }

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        for day in snapshot.tokenUsage.days {
            rows.append([
                "token_usage", dayFormatter.string(from: day.day), "", "", "", "",
                String(day.usage.inputTokens), String(day.usage.outputTokens),
                String(day.usage.totalTokens), ""
            ].joined(separator: ","))
        }

        let taskCounts = [
            ("running", snapshot.tasks.runningCount),
            ("waiting_for_approval", snapshot.tasks.waitingApprovalCount),
            ("waiting_for_input", snapshot.tasks.waitingInputCount)
        ]
        for (name, count) in taskCounts {
            rows.append("task,\(name),,,,,,,,\(count)")
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
