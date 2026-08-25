import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        TaskNotificationService.shared.configure()
        QuotaStore.shared.start()
        PetPanelController.shared.start(store: .shared)
    }

    func applicationWillTerminate(_ notification: Notification) {
        QuotaStore.shared.stop()
    }
}

@main
struct CodexQuotaPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = QuotaStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store)
        } label: {
            HStack(spacing: 4) {
                if let icon = BrandIcon.templateImage {
                    Image(nsImage: icon)
                } else {
                    Image(systemName: "gauge")
                }
                Text(store.menuTitle)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
