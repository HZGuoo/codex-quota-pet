import AppKit
import CodexQuotaPetCore

@MainActor
enum CodexApplicationLauncher {
    private static let bundleIdentifier = "com.openai.codex"

    /// Opens a conversation when the installed Codex version supports its
    /// registered URL route. Older versions safely fall back to activation.
    static func openConversation(threadID: String) {
        guard let conversationURL = CodexDeepLink.conversationURL(threadID: threadID),
              NSWorkspace.shared.urlForApplication(toOpen: conversationURL) != nil else {
            activate()
            return
        }

        guard NSWorkspace.shared.open(conversationURL) else {
            activate()
            return
        }
    }

    static func activate() {
        if let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first {
            application.unhide()
            application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return
        }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            NSSound.beep()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        )
    }
}
