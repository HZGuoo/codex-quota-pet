import Foundation

public struct CodexTokenUsage: Sendable, Equatable {
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let totalTokens: Int64

    public init(inputTokens: Int64, outputTokens: Int64, totalTokens: Int64? = nil) {
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.totalTokens = max(0, totalTokens ?? (inputTokens + outputTokens))
    }

    public static let zero = CodexTokenUsage(inputTokens: 0, outputTokens: 0)

    public static func + (lhs: CodexTokenUsage, rhs: CodexTokenUsage) -> CodexTokenUsage {
        CodexTokenUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            totalTokens: lhs.totalTokens + rhs.totalTokens
        )
    }
}

public struct CodexLocalTokenUsageEvent: Sendable, Equatable {
    public let occurredAt: Date
    public let cumulativeUsage: CodexTokenUsage
    public let lastUsage: CodexTokenUsage

    public init(
        occurredAt: Date,
        cumulativeUsage: CodexTokenUsage,
        lastUsage: CodexTokenUsage
    ) {
        self.occurredAt = occurredAt
        self.cumulativeUsage = cumulativeUsage
        self.lastUsage = lastUsage
    }
}

public enum CodexLocalTokenUsageParser {
    private static let marker = Data("\"token_count\"".utf8)

    public static func parse(line: Data) -> CodexLocalTokenUsageEvent? {
        guard line.range(of: marker) != nil,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "event_msg",
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let cumulative = info["total_token_usage"] as? [String: Any],
              let last = info["last_token_usage"] as? [String: Any],
              let timestamp = object["timestamp"] as? String,
              let occurredAt = parseTimestamp(timestamp)
        else {
            return nil
        }

        let cumulativeUsage = tokenUsage(cumulative)
        let lastUsage = tokenUsage(last)
        guard cumulativeUsage.totalTokens > 0 || lastUsage.totalTokens > 0 else { return nil }

        return CodexLocalTokenUsageEvent(
            occurredAt: occurredAt,
            cumulativeUsage: cumulativeUsage,
            lastUsage: lastUsage
        )
    }

    private static func tokenUsage(_ object: [String: Any]) -> CodexTokenUsage {
        let input = integer(object["input_tokens"])
        let output = integer(object["output_tokens"])
        let total = integer(object["total_tokens"])
        return CodexTokenUsage(
            inputTokens: input,
            outputTokens: output,
            totalTokens: total > 0 ? total : nil
        )
    }

    private static func integer(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return max(0, number.int64Value) }
        if let string = value as? String, let number = Int64(string) { return max(0, number) }
        return 0
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

public struct CodexDailyTokenUsage: Sendable, Equatable, Identifiable {
    public let day: Date
    public let usage: CodexTokenUsage

    public init(day: Date, usage: CodexTokenUsage) {
        self.day = day
        self.usage = usage
    }

    public var id: Date { day }
}

public struct CodexTokenUsageSnapshot: Sendable, Equatable {
    public let days: [CodexDailyTokenUsage]
    public let syncedAt: Date?
    public let lastReportedDay: Date?

    public init(
        days: [CodexDailyTokenUsage] = [],
        syncedAt: Date? = nil,
        lastReportedDay: Date? = nil
    ) {
        self.days = days.sorted { $0.day < $1.day }
        self.syncedAt = syncedAt
        self.lastReportedDay = lastReportedDay
    }

    public static let empty = CodexTokenUsageSnapshot()

    public var total: CodexTokenUsage {
        days.reduce(.zero) { $0 + $1.usage }
    }

    public var averageDailyTokens: Int64 {
        guard !days.isEmpty else { return 0 }
        return total.totalTokens / Int64(days.count)
    }

    public var peakDailyTokens: Int64 {
        days.map(\.usage.totalTokens).max() ?? 0
    }

    public func usage(on date: Date, calendar: Calendar = .autoupdatingCurrent) -> CodexTokenUsage {
        let day = calendar.startOfDay(for: date)
        return days.first(where: { calendar.isDate($0.day, inSameDayAs: day) })?.usage ?? .zero
    }

    public static func decodeCloud(
        from data: Data,
        calendar: Calendar = .autoupdatingCurrent,
        syncedAt: Date = Date(),
        dayCount: Int = 30
    ) throws -> CodexTokenUsageSnapshot {
        let response = try JSONDecoder().decode(CloudResponse.self, from: data)
        let today = calendar.startOfDay(for: syncedAt)
        guard dayCount > 0,
              let firstDay = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today)
        else {
            throw CodexTokenUsageError.invalidDateRange
        }

        var usageByDay: [Date: Int64] = [:]
        var reportedDays: [Date] = []
        for bucket in response.dailyUsageBuckets ?? [] {
            guard let day = parseCloudDay(bucket.startDate, calendar: calendar) else {
                throw CodexTokenUsageError.invalidStartDate(bucket.startDate)
            }
            reportedDays.append(day)
            guard day >= firstDay, day <= today else { continue }
            usageByDay[day, default: 0] += max(0, bucket.tokens)
        }

        let days = (0..<dayCount).compactMap { offset -> CodexDailyTokenUsage? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else {
                return nil
            }
            return CodexDailyTokenUsage(
                day: day,
                usage: CodexTokenUsage(
                    inputTokens: 0,
                    outputTokens: 0,
                    totalTokens: usageByDay[day] ?? 0
                )
            )
        }
        return CodexTokenUsageSnapshot(
            days: days,
            syncedAt: syncedAt,
            lastReportedDay: reportedDays.max()
        )
    }

    private struct CloudResponse: Decodable {
        let dailyUsageBuckets: [CloudDailyBucket]?
    }

    private struct CloudDailyBucket: Decodable {
        let startDate: String
        let tokens: Int64
    }

    private static func parseCloudDay(_ value: String, calendar: Calendar) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

public enum CodexTokenUsageError: LocalizedError, Equatable {
    case invalidDateRange
    case invalidStartDate(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDateRange:
            "云端 Token 用量的日期范围无效。"
        case let .invalidStartDate(value):
            "云端 Token 用量包含无效日期：\(value)"
        }
    }
}
