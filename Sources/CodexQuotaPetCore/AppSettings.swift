import Foundation

public enum ProxyMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case disabled
    case http
    case socks5

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .disabled: "关闭"
        case .http: "HTTP"
        case .socks5: "SOCKS5"
        }
    }
}

public enum CompactQuotaDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fiveHour
    case weekly
    case both

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fiveHour: "5 小时额度"
        case .weekly: "周额度"
        case .both: "同时显示"
        }
    }

    public var shortDisplayName: String {
        switch self {
        case .fiveHour: "5小时"
        case .weekly: "1周"
        case .both: "同时显示"
        }
    }
}

public enum TokenUsageDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case today
    case last30Days

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .today: "当天"
        case .last30Days: "最近 30 天"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let minimumRefreshInterval = 60
    public static let maximumRefreshInterval = 3_600
    public static let minimumRefreshIntervalMinutes = 1
    public static let maximumRefreshIntervalMinutes = 60

    public var proxyMode: ProxyMode
    public var proxyURL: String
    public var allowDirectFallback: Bool
    public var refreshIntervalSeconds: Int
    public var showPet: Bool
    public var alwaysOnTop: Bool
    public var mousePassthrough: Bool
    public var collapsePetOnFocusLoss: Bool
    public var compactQuotaDisplayMode: CompactQuotaDisplayMode
    public var tokenUsageDisplayMode: TokenUsageDisplayMode
    public var launchAtLogin: Bool
    public var customCodexPath: String
    public var taskNotificationsEnabled: Bool
    public var notifyTaskCompleted: Bool
    public var notifyTaskFailed: Bool
    public var notifyWaitingForApproval: Bool
    public var notifyWaitingForInput: Bool
    public var privateNotificationContent: Bool

    public init(
        proxyMode: ProxyMode = .disabled,
        proxyURL: String = "http://127.0.0.1:10808",
        allowDirectFallback: Bool = false,
        refreshIntervalSeconds: Int = 60,
        showPet: Bool = true,
        alwaysOnTop: Bool = true,
        mousePassthrough: Bool = false,
        collapsePetOnFocusLoss: Bool = true,
        compactQuotaDisplayMode: CompactQuotaDisplayMode = .both,
        tokenUsageDisplayMode: TokenUsageDisplayMode = .today,
        launchAtLogin: Bool = false,
        customCodexPath: String = "",
        taskNotificationsEnabled: Bool = true,
        notifyTaskCompleted: Bool = true,
        notifyTaskFailed: Bool = true,
        notifyWaitingForApproval: Bool = true,
        notifyWaitingForInput: Bool = true,
        privateNotificationContent: Bool = false
    ) {
        self.proxyMode = proxyMode
        self.proxyURL = proxyURL
        self.allowDirectFallback = allowDirectFallback
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.showPet = showPet
        self.alwaysOnTop = alwaysOnTop
        self.mousePassthrough = mousePassthrough
        self.collapsePetOnFocusLoss = collapsePetOnFocusLoss
        self.compactQuotaDisplayMode = compactQuotaDisplayMode
        self.tokenUsageDisplayMode = tokenUsageDisplayMode
        self.launchAtLogin = launchAtLogin
        self.customCodexPath = customCodexPath
        self.taskNotificationsEnabled = taskNotificationsEnabled
        self.notifyTaskCompleted = notifyTaskCompleted
        self.notifyTaskFailed = notifyTaskFailed
        self.notifyWaitingForApproval = notifyWaitingForApproval
        self.notifyWaitingForInput = notifyWaitingForInput
        self.privateNotificationContent = privateNotificationContent
    }

    public static let defaults = AppSettings()

    public var refreshIntervalMinutes: Int {
        get {
            min(
                Self.maximumRefreshIntervalMinutes,
                max(Self.minimumRefreshIntervalMinutes, (refreshIntervalSeconds + 30) / 60)
            )
        }
        set {
            let minutes = min(
                Self.maximumRefreshIntervalMinutes,
                max(Self.minimumRefreshIntervalMinutes, newValue)
            )
            refreshIntervalSeconds = minutes * 60
        }
    }

    public var normalized: AppSettings {
        var copy = self
        let roundedMinutes = min(
            Self.maximumRefreshIntervalMinutes,
            max(Self.minimumRefreshIntervalMinutes, (refreshIntervalSeconds + 30) / 60)
        )
        copy.refreshIntervalSeconds = roundedMinutes * 60
        copy.proxyURL = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.customCodexPath = customCodexPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case proxyMode
        case proxyURL
        case allowDirectFallback
        case refreshIntervalSeconds
        case showPet
        case alwaysOnTop
        case mousePassthrough
        case collapsePetOnFocusLoss
        case compactQuotaDisplayMode
        case tokenUsageDisplayMode
        case launchAtLogin
        case customCodexPath
        case taskNotificationsEnabled
        case notifyTaskCompleted
        case notifyTaskFailed
        case notifyWaitingForApproval
        case notifyWaitingForInput
        case privateNotificationContent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            proxyMode: try container.decodeIfPresent(ProxyMode.self, forKey: .proxyMode) ?? .disabled,
            proxyURL: try container.decodeIfPresent(String.self, forKey: .proxyURL) ?? "http://127.0.0.1:10808",
            allowDirectFallback: try container.decodeIfPresent(Bool.self, forKey: .allowDirectFallback) ?? false,
            refreshIntervalSeconds: try container.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds) ?? 60,
            showPet: try container.decodeIfPresent(Bool.self, forKey: .showPet) ?? true,
            alwaysOnTop: try container.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? true,
            mousePassthrough: try container.decodeIfPresent(Bool.self, forKey: .mousePassthrough) ?? false,
            collapsePetOnFocusLoss: try container.decodeIfPresent(Bool.self, forKey: .collapsePetOnFocusLoss) ?? true,
            compactQuotaDisplayMode: try container.decodeIfPresent(
                CompactQuotaDisplayMode.self,
                forKey: .compactQuotaDisplayMode
            ) ?? .both,
            tokenUsageDisplayMode: try container.decodeIfPresent(
                TokenUsageDisplayMode.self,
                forKey: .tokenUsageDisplayMode
            ) ?? .today,
            launchAtLogin: try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false,
            customCodexPath: try container.decodeIfPresent(String.self, forKey: .customCodexPath) ?? "",
            taskNotificationsEnabled: try container.decodeIfPresent(Bool.self, forKey: .taskNotificationsEnabled) ?? true,
            notifyTaskCompleted: try container.decodeIfPresent(Bool.self, forKey: .notifyTaskCompleted) ?? true,
            notifyTaskFailed: try container.decodeIfPresent(Bool.self, forKey: .notifyTaskFailed) ?? true,
            notifyWaitingForApproval: try container.decodeIfPresent(Bool.self, forKey: .notifyWaitingForApproval) ?? true,
            notifyWaitingForInput: try container.decodeIfPresent(Bool.self, forKey: .notifyWaitingForInput) ?? true,
            privateNotificationContent: try container.decodeIfPresent(Bool.self, forKey: .privateNotificationContent) ?? false
        )
    }
}

public enum SettingsValidationError: LocalizedError, Equatable {
    case missingProxyURL
    case invalidProxyURL
    case unsupportedProxyScheme(expected: String)

    public var errorDescription: String? {
        switch self {
        case .missingProxyURL:
            "请输入代理地址。"
        case .invalidProxyURL:
            "代理地址无效，需要包含主机和端口。"
        case let .unsupportedProxyScheme(expected):
            "代理协议不匹配，应使用 \(expected)。"
        }
    }
}

public extension AppSettings {
    func validateProxy() throws {
        guard proxyMode != .disabled else { return }
        guard !proxyURL.isEmpty else { throw SettingsValidationError.missingProxyURL }
        guard let components = URLComponents(string: proxyURL),
              let scheme = components.scheme?.lowercased(),
              components.host != nil,
              components.port != nil else {
            throw SettingsValidationError.invalidProxyURL
        }

        switch proxyMode {
        case .disabled:
            break
        case .http:
            guard scheme == "http" || scheme == "https" else {
                throw SettingsValidationError.unsupportedProxyScheme(expected: "http:// 或 https://")
            }
        case .socks5:
            guard scheme == "socks5" || scheme == "socks5h" else {
                throw SettingsValidationError.unsupportedProxyScheme(expected: "socks5:// 或 socks5h://")
            }
        }
    }
}
