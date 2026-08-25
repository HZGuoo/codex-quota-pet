import Foundation

public struct QuotaWindow: Codable, Equatable, Sendable {
    public let usedPercent: Int
    public let windowDurationMins: Int64?
    public let resetsAt: Int64?

    public var clampedUsedPercent: Int { min(100, max(0, usedPercent)) }
    public var remainingPercent: Int { 100 - clampedUsedPercent }
    public var resetDate: Date? { resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
}

public struct CreditsSnapshot: Codable, Equatable, Sendable {
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: String?
}

public struct SpendControlLimit: Codable, Equatable, Sendable {
    public let limit: String
    public let remainingPercent: Int
    public let resetsAt: Int64
    public let used: String
}

public struct QuotaBucket: Codable, Equatable, Sendable, Identifiable {
    public let limitId: String?
    public let limitName: String?
    public let primary: QuotaWindow?
    public let secondary: QuotaWindow?
    public let credits: CreditsSnapshot?
    public let individualLimit: SpendControlLimit?
    public let spendControlReached: Bool?
    public let planType: String?
    public let rateLimitReachedType: String?

    public var id: String { limitId ?? limitName ?? "codex" }
    public var displayName: String { limitName ?? limitId ?? "Codex" }
    public var windows: [QuotaWindow] { [primary, secondary].compactMap { $0 } }
    public var remainingPercent: Int? { windows.map(\.remainingPercent).min() }
    public var limitingWindow: QuotaWindow? {
        windows.min { $0.remainingPercent < $1.remainingPercent }
    }
}

public struct RateLimitResetCredits: Codable, Equatable, Sendable {
    public let availableCount: Int64
}

public struct QuotaSnapshot: Equatable, Sendable {
    public let buckets: [QuotaBucket]
    public let resetCredits: RateLimitResetCredits?
    public let refreshedAt: Date

    public var remainingPercent: Int? {
        buckets.compactMap(\.remainingPercent).min()
    }

    public var limitingBucket: QuotaBucket? {
        buckets.compactMap { bucket -> (QuotaBucket, Int)? in
            bucket.remainingPercent.map { (bucket, $0) }
        }.min { $0.1 < $1.1 }?.0
    }

    public var planType: String? {
        buckets.compactMap(\.planType).first
    }

    public static func decode(from data: Data, refreshedAt: Date = Date()) throws -> QuotaSnapshot {
        let response = try JSONDecoder().decode(GetAccountRateLimitsResponse.self, from: data)
        let buckets: [QuotaBucket]
        if let byID = response.rateLimitsByLimitId, !byID.isEmpty {
            buckets = byID.keys.sorted().compactMap { key in
                guard let bucket = byID[key] else { return nil }
                return bucket.withFallbackID(key)
            }
        } else {
            buckets = [response.rateLimits.withFallbackID("codex")]
        }
        return QuotaSnapshot(
            buckets: buckets,
            resetCredits: response.rateLimitResetCredits,
            refreshedAt: refreshedAt
        )
    }
}

private struct GetAccountRateLimitsResponse: Decodable {
    let rateLimits: QuotaBucket
    let rateLimitsByLimitId: [String: QuotaBucket]?
    let rateLimitResetCredits: RateLimitResetCredits?
}

private extension QuotaBucket {
    func withFallbackID(_ fallback: String) -> QuotaBucket {
        QuotaBucket(
            limitId: limitId ?? fallback,
            limitName: limitName,
            primary: primary,
            secondary: secondary,
            credits: credits,
            individualLimit: individualLimit,
            spendControlReached: spendControlReached,
            planType: planType,
            rateLimitReachedType: rateLimitReachedType
        )
    }
}

public struct AccountResponse: Decodable, Equatable, Sendable {
    public let account: AccountInfo?
    public let requiresOpenaiAuth: Bool
}

public enum AccountInfo: Equatable, Sendable {
    case apiKey
    case chatgpt(email: String?, planType: String)
    case amazonBedrock(usesCodexManagedCredentials: Bool)

    public var typeName: String {
        switch self {
        case .apiKey: "apiKey"
        case .chatgpt: "chatgpt"
        case .amazonBedrock: "amazonBedrock"
        }
    }
}

extension AccountInfo: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, email, planType, usesCodexManagedCredentials
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "apiKey":
            self = .apiKey
        case "chatgpt":
            self = .chatgpt(
                email: try container.decodeIfPresent(String.self, forKey: .email),
                planType: try container.decode(String.self, forKey: .planType)
            )
        case "amazonBedrock":
            self = .amazonBedrock(
                usesCodexManagedCredentials: try container.decodeIfPresent(
                    Bool.self,
                    forKey: .usesCodexManagedCredentials
                ) ?? false
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported account type: \(type)"
            )
        }
    }
}

public enum QuotaViewState: Equatable, Sendable {
    case loading
    case current(QuotaSnapshot)
    case stale(QuotaSnapshot, message: String)
    case error(String)

    public var snapshot: QuotaSnapshot? {
        switch self {
        case .loading, .error: nil
        case let .current(snapshot), let .stale(snapshot, _): snapshot
        }
    }

    public var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}
