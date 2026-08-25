import Combine
import Foundation
import ServiceManagement
import CodexQuotaPetCore

@MainActor
final class QuotaStore: ObservableObject {
    static let shared = QuotaStore()

    @Published private(set) var state: QuotaViewState = .loading
    @Published private(set) var settings: AppSettings
    @Published private(set) var isRefreshing = false
    @Published private(set) var settingsMessage: String?
    @Published private(set) var taskStatus = CodexTaskStatusSummary.zero

    private let client = CodexAppServerClient()
    private let taskMonitor = CodexRolloutTaskMonitor()
    private var started = false
    private var connected = false
    private var eventTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var notificationRefreshTask: Task<Void, Never>?
    private var taskEventTask: Task<Void, Never>?
    private var taskStatusTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var seenTaskEvents: [String: Date] = [:]
    private var rolloutTaskStatus = CodexTaskStatusSnapshot.empty
    private var appServerTaskStatus: [String: CodexTaskLiveState] = [:]
    private var appServerInactiveThreadIDs: Set<String> = []

    private static let settingsKey = "CodexQuotaPet.settings.v1"
    private static let legacyDefaultsSuite = "com.local.CodexQuotaPet"
    private static let panelFrameKey = "NSWindow Frame CodexQuotaPet.panelFrame"
    private static let reconnectDelays: [UInt64] = [1, 2, 5, 15, 30]
    private static let syncTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("HHmmss")
        return formatter
    }()

    private init() {
        var loaded = Self.loadSettings().normalized
        loaded.launchAtLogin = SMAppService.mainApp.status == .enabled
        settings = loaded
    }

    var snapshot: QuotaSnapshot? { state.snapshot }
    var remainingPercent: Int? { snapshot?.remainingPercent }

    var menuTitle: String {
        switch state {
        case .loading:
            "…"
        case .error:
            "--"
        case let .current(snapshot):
            snapshot.remainingPercent.map { "\($0)%" } ?? "--"
        case let .stale(snapshot, _):
            snapshot.remainingPercent.map { "\($0)%*" } ?? "--"
        }
    }

    var statusMessage: String {
        switch state {
        case .loading:
            "正在连接 Codex…"
        case let .current(snapshot):
            "数据同步于 \(Self.syncTimeFormatter.string(from: snapshot.refreshedAt))"
        case let .stale(_, message), let .error(message):
            message
        }
    }

    func start() {
        guard !started else { return }
        started = true

        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in client.events {
                guard !Task.isCancelled else { return }
                self.handle(event)
            }
        }
        taskEventTask = Task { [weak self] in
            guard let self else { return }
            for await event in taskMonitor.events {
                guard !Task.isCancelled else { return }
                self.handleTaskEvent(event)
            }
        }
        taskStatusTask = Task { [weak self] in
            guard let self else { return }
            for await status in taskMonitor.threadStatusUpdates {
                guard !Task.isCancelled else { return }
                self.rolloutTaskStatus = status
                self.publishMergedTaskStatus()
            }
        }
        Task { await taskMonitor.start() }
        updateTaskMonitoring()
        restartPolling()
        Task { [weak self] in await self?.connectAndRefresh() }
    }

    func stop() {
        started = false
        eventTask?.cancel()
        pollingTask?.cancel()
        reconnectTask?.cancel()
        notificationRefreshTask?.cancel()
        taskEventTask?.cancel()
        taskStatusTask?.cancel()
        rolloutTaskStatus = .empty
        appServerTaskStatus.removeAll()
        appServerInactiveThreadIDs.removeAll()
        taskStatus = .zero
        Task { await client.stop() }
        Task { await taskMonitor.stop() }
    }

    func refresh() {
        Task { [weak self] in await self?.connectAndRefresh() }
    }

    func applySettings(_ newSettings: AppSettings) {
        let normalized = newSettings.normalized
        do {
            try normalized.validateProxy()
        } catch {
            settingsMessage = error.localizedDescription
            return
        }

        let old = settings
        do {
            if old.launchAtLogin != normalized.launchAtLogin {
                if normalized.launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            settingsMessage = "登录启动设置失败：\(error.localizedDescription)"
            return
        }

        settings = normalized
        Self.saveSettings(normalized)
        settingsMessage = "设置已保存"

        if old.taskNotificationsEnabled != normalized.taskNotificationsEnabled {
            updateTaskMonitoring()
        }

        if old.refreshIntervalSeconds != normalized.refreshIntervalSeconds {
            restartPolling()
            refresh()
        }

        let connectionChanged = old.proxyMode != normalized.proxyMode
            || old.proxyURL != normalized.proxyURL
            || old.allowDirectFallback != normalized.allowDirectFallback
            || old.customCodexPath != normalized.customCodexPath
        if connectionChanged {
            connected = false
            reconnectAttempt = 0
            clearAppServerTaskStatus()
            Task { [weak self] in
                guard let self else { return }
                await client.stop()
                await connectAndRefresh()
            }
        }
    }

    func mutateSettings(_ mutation: (inout AppSettings) -> Void) {
        var copy = settings
        mutation(&copy)
        applySettings(copy)
    }

    func testConnection(with draft: AppSettings) async -> Result<QuotaSnapshot, Error> {
        let testClient = CodexAppServerClient()
        do {
            let normalized = draft.normalized
            try normalized.validateProxy()
            try await testClient.start(settings: normalized)
            let account = try await testClient.readAccount(timeoutSeconds: 10)
            try Self.validateAccount(account)
            let snapshot = try await testClient.readRateLimits(timeoutSeconds: 10)
            await testClient.stop()
            return .success(snapshot)
        } catch {
            await testClient.stop()
            return .failure(error)
        }
    }

    private func connectAndRefresh() async {
        guard started, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            if !(await client.isRunning) {
                connected = false
                clearAppServerTaskStatus()
                try await client.start(settings: settings)
            }
            if !connected {
                let account = try await client.readAccount()
                try Self.validateAccount(account)
                connected = true
            }

            let snapshot = try await client.readRateLimits()
            state = .current(snapshot)
            reconnectAttempt = 0
            reconnectTask?.cancel()
            reconnectTask = nil
        } catch is CancellationError {
            return
        } catch {
            connected = await client.isRunning
            markFailure(error.localizedDescription)
            if !connected { scheduleReconnect() }
        }
    }

    private func handle(_ event: CodexClientEvent) {
        switch event {
        case let .notification(notification):
            if notification.method == "account/rateLimits/updated" {
                notificationRefreshTask?.cancel()
                notificationRefreshTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    await self?.connectAndRefresh()
                }
            }
            if let statusUpdate = CodexAppServerTaskEventParser.statusUpdate(notification) {
                applyAppServerTaskStatus(statusUpdate)
            }
            if let taskEvent = CodexAppServerTaskEventParser.parse(notification) {
                handleTaskEvent(taskEvent)
            }
        case let .terminated(message):
            connected = false
            clearAppServerTaskStatus()
            markFailure(message ?? "Codex app-server 已退出")
            scheduleReconnect()
        }
    }

    private func updateTaskMonitoring() {
        if settings.taskNotificationsEnabled {
            TaskNotificationService.shared.requestAuthorizationIfNeeded()
        } else {
            seenTaskEvents.removeAll()
        }
    }

    private func handleTaskEvent(_ event: CodexTaskEvent) {
        guard settings.taskNotificationsEnabled, shouldNotify(event.kind) else { return }
        guard seenTaskEvents[event.dedupeKey] == nil else { return }
        seenTaskEvents[event.dedupeKey] = Date()
        if seenTaskEvents.count > 500 {
            let oldestKeys = seenTaskEvents
                .sorted { $0.value < $1.value }
                .prefix(seenTaskEvents.count - 400)
                .map(\.key)
            oldestKeys.forEach { seenTaskEvents.removeValue(forKey: $0) }
        }
        TaskNotificationService.shared.deliver(
            event,
            privateContent: settings.privateNotificationContent
        )
    }

    private func applyAppServerTaskStatus(_ update: CodexThreadTaskStatusUpdate) {
        if let state = update.state {
            appServerTaskStatus[update.threadID] = state
            appServerInactiveThreadIDs.remove(update.threadID)
        } else {
            appServerTaskStatus.removeValue(forKey: update.threadID)
            appServerInactiveThreadIDs.insert(update.threadID)
        }
        publishMergedTaskStatus()
    }

    private func clearAppServerTaskStatus() {
        guard !appServerTaskStatus.isEmpty || !appServerInactiveThreadIDs.isEmpty else { return }
        appServerTaskStatus.removeAll()
        appServerInactiveThreadIDs.removeAll()
        publishMergedTaskStatus()
    }

    private func publishMergedTaskStatus() {
        taskStatus = rolloutTaskStatus.overlaying(
            appServerTaskStatus,
            inactiveThreadIDs: appServerInactiveThreadIDs
        ).summary
    }

    private func shouldNotify(_ kind: CodexTaskEventKind) -> Bool {
        switch kind {
        case .completed:
            settings.notifyTaskCompleted
        case .failed:
            settings.notifyTaskFailed
        case .interrupted:
            false
        case .waitingForApproval:
            settings.notifyWaitingForApproval
        case .waitingForInput:
            settings.notifyWaitingForInput
        }
    }

    private func markFailure(_ message: String) {
        if let snapshot = state.snapshot {
            state = .stale(snapshot, message: message)
        } else {
            state = .error(message)
        }
    }

    private func scheduleReconnect() {
        guard started, reconnectTask == nil else { return }
        let index = min(reconnectAttempt, Self.reconnectDelays.count - 1)
        let delay = Self.reconnectDelays[index]
        reconnectAttempt += 1
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            reconnectTask = nil
            await connectAndRefresh()
            if !connected { scheduleReconnect() }
        }
    }

    private func restartPolling() {
        pollingTask?.cancel()
        let interval = settings.normalized.refreshIntervalSeconds
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self?.connectAndRefresh()
            }
        }
    }

    private static func validateAccount(_ response: AccountResponse) throws {
        guard let account = response.account else {
            throw QuotaStoreError.notLoggedIn
        }
        guard case .chatgpt = account else {
            throw QuotaStoreError.unsupportedAccount(account.typeName)
        }
    }

    private static func loadSettings() -> AppSettings {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return decoded
        }

        guard let legacyDefaults = UserDefaults(suiteName: legacyDefaultsSuite),
              let data = legacyDefaults.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .defaults
        }

        UserDefaults.standard.set(data, forKey: settingsKey)
        if UserDefaults.standard.object(forKey: panelFrameKey) == nil,
           let legacyFrame = legacyDefaults.object(forKey: panelFrameKey) {
            UserDefaults.standard.set(legacyFrame, forKey: panelFrameKey)
        }
        return decoded
    }

    private static func saveSettings(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }
}

enum QuotaStoreError: LocalizedError {
    case notLoggedIn
    case unsupportedAccount(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            "尚未登录 ChatGPT。请先打开 ChatGPT 或 Codex 完成登录。"
        case let .unsupportedAccount(type):
            "当前认证类型为 \(type)，订阅额度查询仅支持 ChatGPT 登录。"
        }
    }
}
