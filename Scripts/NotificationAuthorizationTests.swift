import AppKit
import Foundation
import ObjectiveC
import UserNotifications

// Only authorization is exercised. These routes must never be called here.
@MainActor
enum CodexApplicationLauncher {
    static func openConversation(threadID: String) { fatalError("Unexpected conversation route") }
    static func activate() { fatalError("Unexpected application activation") }
}

private typealias Completion = @convention(block) (Bool, NSError?) -> Void
private typealias AuthorizationRequest = @convention(block)
    (UNUserNotificationCenter, UInt, @escaping Completion) -> Void

// The system completion block may be called from any queue. This test-only
// wrapper transfers it exactly once to a background queue, like the framework.
private final class BackgroundReply: @unchecked Sendable {
    let completion: Completion
    let granted: Bool
    let error: NSError?

    init(completion: @escaping Completion, granted: Bool, error: NSError?) {
        self.completion = completion
        self.granted = granted
        self.error = error
    }

    func send() {
        dispatchPrecondition(condition: .notOnQueue(.main))
        completion(granted, error)
    }
}

@main
struct NotificationAuthorizationTests {
    private static func makeReplacement(
        granted: Bool,
        error: NSError?,
        continuation: AsyncStream<Void>.Continuation
    ) -> AuthorizationRequest {
        { _, options, completion in
            precondition(options == UNAuthorizationOptions([.alert, .sound]).rawValue)
            let reply = BackgroundReply(completion: completion, granted: granted, error: error)
            DispatchQueue.global().async {
                reply.send()
                continuation.yield(())
                continuation.finish()
            }
        }
    }

    @MainActor
    static func main() async throws {
        let selector = #selector(UNUserNotificationCenter.requestAuthorization(options:completionHandler:))
        guard let method = class_getInstanceMethod(UNUserNotificationCenter.self, selector) else {
            fatalError("Authorization Objective-C method is unavailable")
        }
        let original = method_getImplementation(method)
        let service = TaskNotificationService.shared

        let scenarios: [(String, Bool, NSError?)] = [
            ("allowed", true, nil),
            ("denied", false, nil),
            ("error", false, NSError(domain: "NotificationAuthorizationTest", code: 1))
        ]
        for (name, granted, error) in scenarios {
            let (replies, continuation) = AsyncStream<Void>.makeStream()
            let replacement = makeReplacement(granted: granted, error: error, continuation: continuation)
            let implementation = imp_implementationWithBlock(replacement)
            method_setImplementation(method, implementation)
            defer {
                method_setImplementation(method, original)
                imp_removeBlock(implementation)
            }

            service.requestAuthorizationIfNeeded()
            let received = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    for await _ in replies { return true }
                    return false
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(5))
                    return false
                }
                let result = await group.next() ?? false
                group.cancelAll()
                return result
            }
            precondition(received, "Authorization did not invoke the system API")
            // Give the production task time to resume and handle success/error.
            try await Task.sleep(for: .milliseconds(100))
            MainActor.assertIsolated()
            print("✓ authorization \(name): background callback did not crash")
        }
        print("NotificationAuthorizationTests: 3 scenarios passed")
    }
}
