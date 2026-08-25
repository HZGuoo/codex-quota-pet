import Foundation
import UserNotifications
import CodexQuotaPetCore

@MainActor
final class TaskNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TaskNotificationService()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
    }

    func configure() {
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func deliver(_ event: CodexTaskEvent, privateContent: Bool) {
        let content = UNMutableNotificationContent()
        content.title = notificationHeading(for: event.kind)
        content.body = privateContent ? privateBody(for: event.kind) : notificationBody(for: event)
        content.sound = .default
        content.threadIdentifier = event.threadID
        content.categoryIdentifier = "codex.task-status"
        content.userInfo = [
            "threadId": event.threadID,
            "turnId": event.turnID ?? "",
            "openCodex": true
        ]

        let request = UNNotificationRequest(
            identifier: "codex-quota-pet.\(event.dedupeKey)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              response.notification.request.content.userInfo["openCodex"] as? Bool == true else {
            return
        }
        let threadID = response.notification.request.content.userInfo["threadId"] as? String
        await MainActor.run {
            if let threadID, !threadID.isEmpty {
                CodexApplicationLauncher.openConversation(threadID: threadID)
            } else {
                CodexApplicationLauncher.activate()
            }
        }
    }

    private func notificationHeading(for kind: CodexTaskEventKind) -> String {
        switch kind {
        case .completed: "Codex 任务已完成"
        case .failed: "Codex 任务执行失败"
        case .interrupted: "Codex 任务已中断"
        case .waitingForApproval: "Codex 需要你的批准"
        case .waitingForInput: "Codex 正在等待你的输入"
        }
    }

    private func notificationBody(for event: CodexTaskEvent) -> String {
        let title = "“\(event.title)”"
        switch event.kind {
        case .completed:
            return "\(title)已完成。"
        case .failed:
            return event.detail.map { "\(title)执行失败：\($0)" } ?? "\(title)执行失败。"
        case .interrupted:
            return "\(title)已中断。"
        case .waitingForApproval:
            return "\(title)正在等待操作批准。"
        case .waitingForInput:
            return event.detail.map { "\(title)：\($0)" } ?? "\(title)正在等待你的输入。"
        }
    }

    private func privateBody(for kind: CodexTaskEventKind) -> String {
        switch kind {
        case .completed: "一个 Codex 任务已完成。"
        case .failed: "一个 Codex 任务执行失败。"
        case .interrupted: "一个 Codex 任务已中断。"
        case .waitingForApproval: "一个 Codex 任务正在等待操作批准。"
        case .waitingForInput: "一个 Codex 任务正在等待你的输入。"
        }
    }
}
