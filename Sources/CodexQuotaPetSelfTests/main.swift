import Foundation
import CodexQuotaPetCore

enum SelfTestError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        if case let .failed(message) = self { return message }
        return nil
    }
}

@main
struct CodexQuotaPetSelfTests {
    static func main() async throws {
        var passed = 0
        try run("multi-bucket decoding") {
            let data = Data(#"""
            {
              "rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":300}},
              "rateLimitsByLimitId":{
                "codex":{"limitId":"codex","planType":"plus","primary":{"usedPercent":40,"windowDurationMins":300},"secondary":{"usedPercent":65,"windowDurationMins":10080}},
                "other":{"primary":{"usedPercent":20,"windowDurationMins":300}}
              },
              "rateLimitResetCredits":{"availableCount":2,"credits":[]}
            }
            """#.utf8)
            let snapshot = try QuotaSnapshot.decode(from: data)
            try expect(snapshot.buckets.count == 2, "expected two buckets")
            try expect(snapshot.remainingPercent == 35, "expected most constrained remaining value")
            try expect(snapshot.fiveHourWindow?.remainingPercent == 60, "expected five-hour window")
            try expect(snapshot.weeklyWindow?.remainingPercent == 35, "expected weekly window")
            try expect(snapshot.planType == "plus", "expected Plus plan")
            try expect(snapshot.resetCredits?.availableCount == 2, "expected reset credits")
        }
        passed += 1

        try run("legacy and percentage clamping") {
            let data = Data(#"{"rateLimits":{"primary":{"usedPercent":140},"secondary":{"usedPercent":-10}},"rateLimitsByLimitId":null}"#.utf8)
            let snapshot = try QuotaSnapshot.decode(from: data)
            try expect(snapshot.buckets.count == 1, "expected legacy fallback")
            try expect(snapshot.buckets[0].id == "codex", "expected fallback id")
            try expect(snapshot.buckets[0].primary?.remainingPercent == 0, "expected upper clamp")
            try expect(snapshot.buckets[0].secondary?.remainingPercent == 100, "expected lower clamp")
            try expect(snapshot.fiveHourWindow?.remainingPercent == 0, "legacy primary should map to five-hour")
            try expect(snapshot.weeklyWindow?.remainingPercent == 100, "legacy secondary should map to weekly")

            let weeklyOnlyData = Data(#"{"rateLimits":{"primary":{"usedPercent":40,"windowDurationMins":10080}},"rateLimitsByLimitId":null}"#.utf8)
            let weeklyOnly = try QuotaSnapshot.decode(from: weeklyOnlyData)
            try expect(weeklyOnly.fiveHourWindow == nil, "weekly window must not be duplicated as five-hour")
            try expect(weeklyOnly.weeklyWindow?.remainingPercent == 60, "expected duration-based weekly window")
        }
        passed += 1

        try run("proxy environment") {
            let http = AppSettings(proxyMode: .http, proxyURL: "http://127.0.0.1:10808")
            let httpEnvironment = try ProxyEnvironment.make(
                base: ["PATH": "/bin", "HTTPS_PROXY": "http://old:1"],
                settings: http
            )
            try expect(httpEnvironment["HTTPS_PROXY"] == http.proxyURL, "expected HTTP proxy override")
            try expect(httpEnvironment["ALL_PROXY"] == http.proxyURL, "expected ALL_PROXY")

            let socks = AppSettings(proxyMode: .socks5, proxyURL: "socks5://127.0.0.1:10808")
            let socksEnvironment = try ProxyEnvironment.make(base: [:], settings: socks)
            try expect(socksEnvironment["ALL_PROXY"] == "socks5h://127.0.0.1:10808", "expected remote DNS SOCKS")
            try expect(socksEnvironment["HTTP_PROXY"] == nil, "SOCKS must not add HTTP fallback")

            let directEnvironment = try ProxyEnvironment.make(
                base: ["HTTP_PROXY": "http://old:1"],
                settings: AppSettings(proxyMode: .disabled)
            )
            try expect(directEnvironment["HTTP_PROXY"] == nil, "disabled proxy must clear inherited value")

            try ProxyEndpointPreflight.check(settings: AppSettings(proxyMode: .disabled))
        }
        passed += 1

        try run("settings validation") {
            try expect(AppSettings.defaults.proxyMode == .disabled, "proxy should default to disabled")
            try expect(AppSettings(refreshIntervalSeconds: 1).normalized.refreshIntervalSeconds == 60, "minimum interval")
            try expect(AppSettings(refreshIntervalSeconds: 9_999).normalized.refreshIntervalSeconds == 3_600, "maximum interval")
            try expect(AppSettings(refreshIntervalSeconds: 89).normalized.refreshIntervalSeconds == 60, "whole minute rounding")
            var minuteSettings = AppSettings()
            minuteSettings.refreshIntervalMinutes = 15
            try expect(minuteSettings.refreshIntervalSeconds == 900, "minute input conversion")
            do {
                try AppSettings(proxyMode: .http, proxyURL: "http://localhost").validateProxy()
                throw SelfTestError.failed("missing proxy port should fail")
            } catch is SettingsValidationError {}
        }
        passed += 1

        try run("backward-compatible notification settings") {
            let legacy = Data(#"{"proxyMode":"disabled","proxyURL":"http://127.0.0.1:10808","refreshIntervalSeconds":900,"showPet":false}"#.utf8)
            let settings = try JSONDecoder().decode(AppSettings.self, from: legacy)
            try expect(settings.refreshIntervalMinutes == 15, "legacy refresh setting should be preserved")
            try expect(settings.showPet == false, "legacy pet setting should be preserved")
            try expect(settings.collapsePetOnFocusLoss, "focus-loss collapse should default on for legacy settings")
            try expect(settings.taskNotificationsEnabled, "notifications should default on for legacy settings")
            try expect(settings.notifyTaskCompleted, "completion notification should default on")
            try expect(!settings.privateNotificationContent, "privacy mode should default off")
            try expect(settings.compactQuotaDisplayMode == .both, "legacy compact display should show both quotas")

            var updated = settings
            updated.compactQuotaDisplayMode = .weekly
            let roundTrip = try JSONDecoder().decode(
                AppSettings.self,
                from: JSONEncoder().encode(updated)
            )
            try expect(roundTrip.compactQuotaDisplayMode == .weekly, "compact display mode should persist")
        }
        passed += 1

        try run("Codex conversation deep links") {
            let plain = CodexDeepLink.conversationURL(threadID: "  thread-123_abc  ")
            try expect(
                plain?.absoluteString == "codex://threads/thread-123_abc",
                "expected a portable conversation route"
            )

            let opaque = CodexDeepLink.conversationURL(threadID: "thread/with?reserved#characters")
            try expect(
                opaque?.absoluteString == "codex://threads/thread%2Fwith%3Freserved%23characters",
                "thread id must remain one encoded path component"
            )
            try expect(
                CodexDeepLink.conversationURL(threadID: " \n ") == nil,
                "blank thread id should not produce a route"
            )
        }
        passed += 1

        try run("task event parsing") {
            var state = CodexRolloutParseState()
            _ = CodexRolloutEventParser.parse(line: Data(#"{"timestamp":"2026-08-15T01:00:00.000Z","type":"session_meta","payload":{"id":"thread-1","cwd":"/tmp/project","thread_source":"user","source":"vscode"}}"#.utf8), state: &state)
            _ = CodexRolloutEventParser.parse(line: Data(#"{"timestamp":"2026-08-15T01:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}"#.utf8), state: &state)
            _ = CodexRolloutEventParser.parse(line: Data(#"{"timestamp":"2026-08-15T01:00:02.000Z","type":"event_msg","payload":{"type":"user_message","message":"修复通知功能\n请补测试"}}"#.utf8), state: &state)
            try expect(state.isTurnActive, "task should be marked active after task_started")

            let inputLine = Data(#"{"timestamp":"2026-08-15T01:00:03.000Z","type":"response_item","payload":{"type":"function_call","name":"request_user_input","call_id":"input-1","arguments":"{\"questions\":[{\"question\":\"请选择发布方式\"}]}","internal_chat_message_metadata_passthrough":{"turn_id":"turn-1"}}}"#.utf8)
            let inputEvent = CodexRolloutEventParser.parse(line: inputLine, state: &state).first
            try expect(inputEvent?.kind == .waitingForInput, "expected waiting-for-input event")
            try expect(inputEvent?.detail == "请选择发布方式", "expected question detail")
            try expect(state.waitingInputCallIDs == ["input-1"], "expected waiting input state")
            let inputOutput = Data(#"{"timestamp":"2026-08-15T01:00:03.500Z","type":"response_item","payload":{"type":"function_call_output","call_id":"input-1","output":"ok"}}"#.utf8)
            _ = CodexRolloutEventParser.parse(line: inputOutput, state: &state)
            try expect(state.waitingInputCallIDs.isEmpty, "input response should resume the task")

            let approvalLine = Data(#"{"timestamp":"2026-08-15T01:00:04.000Z","type":"response_item","payload":{"type":"custom_tool_call","name":"exec","call_id":"approval-1","input":"{\"sandbox_permissions\":\"require_escalated\"}"}}"#.utf8)
            let approvalEvent = CodexRolloutEventParser.parse(line: approvalLine, state: &state).first
            try expect(approvalEvent?.kind == .waitingForApproval, "expected waiting-for-approval event")
            try expect(state.waitingApprovalCallIDs == ["approval-1"], "expected waiting approval state")
            let approvalOutput = Data(#"{"timestamp":"2026-08-15T01:00:04.500Z","type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"approval-1","output":[]}}"#.utf8)
            try expect(
                CodexRolloutEventParser.resolvedToolCallID(line: approvalOutput) == "approval-1",
                "expected approval resolution id"
            )
            _ = CodexRolloutEventParser.parse(line: approvalOutput, state: &state)
            try expect(state.waitingApprovalCallIDs.isEmpty, "approval result should resume the task")

            let permissionLine = Data(#"{"timestamp":"2026-08-15T01:00:04.600Z","type":"response_item","payload":{"type":"custom_tool_call","name":"exec","call_id":"approval-2","input":"const r = await tools.request_permissions({permissions:[{type:\"network\"}]});"}}"#.utf8)
            let permissionEvent = CodexRolloutEventParser.parse(line: permissionLine, state: &state).first
            try expect(permissionEvent?.kind == .waitingForApproval, "expected request_permissions approval event")
            try expect(state.waitingApprovalCallIDs == ["approval-2"], "expected request_permissions waiting state")
            let permissionOutput = Data(#"{"timestamp":"2026-08-15T01:00:04.700Z","type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"approval-2","output":[]}}"#.utf8)
            _ = CodexRolloutEventParser.parse(line: permissionOutput, state: &state)
            try expect(state.waitingApprovalCallIDs.isEmpty, "permission result should resume the task")

            let completeLine = Data(#"{"timestamp":"2026-08-15T01:00:05.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1","completed_at":1786755605}}"#.utf8)
            let completeEvent = CodexRolloutEventParser.parse(line: completeLine, state: &state).first
            try expect(completeEvent?.kind == .completed, "expected completion event")
            try expect(completeEvent?.threadID == "thread-1", "expected thread id")
            try expect(completeEvent?.turnID == "turn-1", "expected turn id")
            try expect(completeEvent?.title == "修复通知功能", "expected prompt-derived title")
            try expect(!state.isTurnActive, "completed task should no longer be active")
        }
        passed += 1

        try run("app-server task notification parsing") {
            let params = Data(#"{"threadId":"thread-2","status":{"type":"active","activeFlags":["waitingOnApproval"]}}"#.utf8)
            let notification = CodexNotification(method: "thread/status/changed", params: params)
            let event = CodexAppServerTaskEventParser.parse(notification)
            let status = CodexAppServerTaskEventParser.statusUpdate(notification)
            try expect(event?.kind == .waitingForApproval, "expected app-server approval event")
            try expect(event?.threadID == "thread-2", "expected app-server thread id")
            try expect(status?.state == .waitingForApproval, "expected authoritative approval state")

            let runningParams = Data(#"{"threadId":"thread-2","status":{"type":"active","activeFlags":[]}}"#.utf8)
            let running = CodexAppServerTaskEventParser.statusUpdate(
                CodexNotification(method: "thread/status/changed", params: runningParams)
            )
            try expect(running?.state == .running, "active app-server thread should be running")

            let idleParams = Data(#"{"threadId":"thread-2","status":{"type":"idle"}}"#.utf8)
            let idle = CodexAppServerTaskEventParser.statusUpdate(
                CodexNotification(method: "thread/status/changed", params: idleParams)
            )
            try expect(idle?.state == nil, "idle app-server thread should be removed")
        }
        passed += 1

        try run("task status source merging") {
            let rollout = CodexTaskStatusSnapshot(byThreadID: [
                "thread-1": .running,
                "thread-2": .waitingForInput
            ])
            let merged = rollout.overlaying([
                "thread-1": .waitingForApproval,
                "thread-3": .running
            ])
            try expect(merged.summary.runningCount == 1, "expected one merged running thread")
            try expect(merged.summary.waitingApprovalCount == 1, "app-server should override rollout")
            try expect(merged.summary.waitingInputCount == 1, "rollout fallback should be retained")
            try expect(merged.summary.totalActiveCount == 3, "same thread must not be counted twice")

            let afterCompletion = rollout.overlaying(
                ["thread-1": .waitingForApproval],
                inactiveThreadIDs: ["thread-2"]
            )
            try expect(
                afterCompletion.byThreadID["thread-2"] == nil,
                "authoritative inactive state should suppress stale rollout activity"
            )
        }
        passed += 1

        try await runAsync("rollout monitor suppresses history and emits appended state") {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let rollout = directory.appendingPathComponent("rollout-test.jsonl")
            let baseline = """
            {"timestamp":"2026-08-15T00:00:00.000Z","type":"session_meta","payload":{"id":"thread-monitor","thread_source":"user","source":"vscode"}}
            {"timestamp":"2026-08-15T00:00:01.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"old-turn","completed_at":1}}
            """
            try (baseline + "\n").write(to: rollout, atomically: true, encoding: .utf8)

            let monitor = CodexRolloutTaskMonitor(sessionsURL: directory)
            let collector = Task<CodexTaskEvent?, Never> {
                for await event in monitor.events { return event }
                return nil
            }
            await monitor.start(pollInterval: 60)

            let now = Int(Date().timeIntervalSince1970)
            let appended = """
            {"timestamp":"2026-08-15T01:00:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"new-turn"}}
            {"timestamp":"2026-08-15T01:00:01.000Z","type":"event_msg","payload":{"type":"user_message","message":"测试新增状态"}}
            {"timestamp":"2026-08-15T01:00:02.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"new-turn","completed_at":\(now)}}
            """
            let handle = try FileHandle(forWritingTo: rollout)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((appended + "\n").utf8))
            try handle.close()
            await monitor.scanNow()
            let event = await collector.value
            try expect(event?.turnID == "new-turn", "monitor should ignore baseline completion")
            try expect(event?.title == "测试新增状态", "monitor should use the latest prompt")
            await monitor.stop()
        }
        passed += 1

        try await runAsync("rollout monitor publishes live task counts") {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let rollout = directory.appendingPathComponent("rollout-status.jsonl")
            let baseline = """
            {"timestamp":"2026-08-15T01:00:00.000Z","type":"session_meta","payload":{"id":"thread-status","thread_source":"user","source":"vscode"}}
            {"timestamp":"2026-08-15T01:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-status"}}
            {"timestamp":"2026-08-15T01:00:02.000Z","type":"event_msg","payload":{"type":"user_message","message":"验证状态计数"}}
            """
            try (baseline + "\n").write(to: rollout, atomically: true, encoding: .utf8)

            let monitor = CodexRolloutTaskMonitor(sessionsURL: directory)
            let statusCollector = Task<[CodexTaskStatusSummary], Never> {
                var values: [CodexTaskStatusSummary] = []
                for await status in monitor.statusUpdates {
                    values.append(status)
                    if values.count == 4 { return values }
                }
                return values
            }
            await monitor.start(pollInterval: 60)

            func append(_ line: String) throws {
                let handle = try FileHandle(forWritingTo: rollout)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data((line + "\n").utf8))
                try handle.close()
            }

            try append(#"{"timestamp":"2026-08-15T01:00:03.000Z","type":"response_item","payload":{"type":"function_call","name":"request_user_input","call_id":"input-status","arguments":"{\"questions\":[{\"question\":\"请选择\"}]}"}}"#)
            await monitor.scanNow()
            try append(#"{"timestamp":"2026-08-15T01:00:04.000Z","type":"response_item","payload":{"type":"function_call_output","call_id":"input-status","output":"ok"}}"#)
            await monitor.scanNow()
            let now = Int(Date().timeIntervalSince1970)
            try append(#"{"timestamp":"2026-08-15T01:00:05.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-status","completed_at":\#(now)}}"#)
            await monitor.scanNow()

            let statuses = await statusCollector.value
            try expect(statuses.count == 4, "expected running, waiting, resumed, and completed states")
            try expect(statuses[0] == CodexTaskStatusSummary(runningCount: 1), "expected initial running count")
            try expect(statuses[1] == CodexTaskStatusSummary(waitingInputCount: 1), "expected waiting input count")
            try expect(statuses[2] == CodexTaskStatusSummary(runningCount: 1), "expected resumed running count")
            try expect(statuses[3] == .zero, "expected zero active tasks after completion")
            await monitor.stop()
        }
        passed += 1

        try await runAsync("rollout approval updates status without notification debounce") {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let rollout = directory.appendingPathComponent("rollout-approval.jsonl")
            let baseline = """
            {"timestamp":"2026-08-23T01:00:00.000Z","type":"session_meta","payload":{"id":"thread-approval","thread_source":"user","source":"vscode"}}
            {"timestamp":"2026-08-23T01:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-approval"}}
            """
            try (baseline + "\n").write(to: rollout, atomically: true, encoding: .utf8)

            let monitor = CodexRolloutTaskMonitor(sessionsURL: directory)
            let collector = Task<[CodexTaskStatusSnapshot], Never> {
                var values: [CodexTaskStatusSnapshot] = []
                for await status in monitor.threadStatusUpdates {
                    values.append(status)
                    if values.count == 2 { return values }
                }
                return values
            }
            await monitor.start(pollInterval: 60)

            let approval = #"{"timestamp":"2026-08-23T01:00:02.000Z","type":"response_item","payload":{"type":"custom_tool_call","name":"exec","call_id":"approval-live","input":"const r = await tools.request_permissions({permissions:[{type:\"network\"}]});"}}"#
            let handle = try FileHandle(forWritingTo: rollout)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((approval + "\n").utf8))
            try handle.close()
            await monitor.scanNow()

            let statuses = await collector.value
            try expect(statuses.count == 2, "expected running and waiting snapshots")
            try expect(
                statuses[0].byThreadID["thread-approval"] == .running,
                "expected initial running state"
            )
            try expect(
                statuses[1].byThreadID["thread-approval"] == .waitingForApproval,
                "approval status should not wait for notification debounce"
            )
            await monitor.stop()
        }
        passed += 1

        try await runAsync("app-server handshake and JSONL request matching") {
            let executable = try makeFakeServer(respondToRateLimits: true)
            let client = CodexAppServerClient()
            let notificationTask = Task<CodexNotification?, Never> {
                for await event in client.events {
                    if case let .notification(notification) = event { return notification }
                }
                return nil
            }
            var settings = AppSettings.defaults
            settings.proxyMode = .disabled
            try await client.start(settings: settings, executableURL: executable)
            let account = try await client.readAccount(timeoutSeconds: 2)
            let inventory = try await client.readThreadStatusInventory(timeoutSeconds: 2)
            let snapshot = try await client.readRateLimits(timeoutSeconds: 2)
            let notification = await notificationTask.value
            try expect(account.account == .chatgpt(email: nil, planType: "plus"), "expected ChatGPT account")
            try expect(inventory.activeByThreadID["thread-running"] == .running, "expected paged running thread")
            try expect(inventory.activeByThreadID["thread-approval"] == .waitingForApproval, "expected paged approval thread")
            try expect(inventory.activeByThreadID["thread-child"] == nil, "child thread should not be counted")
            try expect(
                inventory.inactiveThreadIDs == ["thread-stale", "thread-idle", "thread-error"],
                "expected all authoritative inactive states"
            )
            let staleRollout = CodexTaskStatusSnapshot(byThreadID: ["thread-stale": .running])
            try expect(
                staleRollout.overlaying(
                    inventory.activeByThreadID,
                    inactiveThreadIDs: inventory.inactiveThreadIDs
                ).summary == CodexTaskStatusSummary(runningCount: 1, waitingApprovalCount: 1),
                "authoritative inventory should suppress stale rollout state"
            )
            try expect(snapshot.remainingPercent == 60, "expected fake remaining value")
            try expect(notification?.method == "thread/status/changed", "expected full notification method")
            try expect(notification?.params != nil, "expected notification params to be preserved")
            await client.stop()
        }
        passed += 1

        try await runAsync("request timeout") {
            let executable = try makeFakeServer(respondToRateLimits: false)
            let client = CodexAppServerClient()
            var settings = AppSettings.defaults
            settings.proxyMode = .disabled
            try await client.start(settings: settings, executableURL: executable)
            do {
                _ = try await client.readRateLimits(timeoutSeconds: 0.15)
                throw SelfTestError.failed("expected timeout")
            } catch let error as CodexAppServerError {
                try expect(error == .requestTimedOut("account/rateLimits/read"), "unexpected timeout error")
            }
            await client.stop()
        }
        passed += 1

        print("CodexQuotaPetSelfTests: \(passed) groups passed")
        if CommandLine.arguments.contains("--live") {
            try await liveProbe()
        }
        if CommandLine.arguments.contains("--dead-proxy") {
            try await deadProxyProbe()
        }
    }

    private static func run(_ name: String, operation: () throws -> Void) throws {
        try operation()
        print("✓ \(name)")
    }

    @MainActor
    private static func runAsync(
        _ name: String,
        operation: @MainActor () async throws -> Void
    ) async throws {
        try await operation()
        print("✓ \(name)")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw SelfTestError.failed(message) }
    }

    @MainActor
    private static func liveProbe() async throws {
        let client = CodexAppServerClient()
        do {
            let settings = AppSettings(proxyMode: .http)
            try await client.start(settings: settings)
            let account = try await client.readAccount(timeoutSeconds: 10)
            guard case let .chatgpt(_, planType)? = account.account else {
                throw SelfTestError.failed("live probe requires ChatGPT authentication")
            }
            let snapshot = try await client.readRateLimits(timeoutSeconds: 10)
            print("✓ live proxy probe: plan=\(planType), remaining=\(snapshot.remainingPercent.map(String.init) ?? "--")%")
            await client.stop()
        } catch {
            await client.stop()
            throw error
        }
    }

    @MainActor
    private static func deadProxyProbe() async throws {
        let client = CodexAppServerClient()
        var settings = AppSettings(proxyMode: .http)
        settings.proxyURL = "http://127.0.0.1:1"
        do {
            try await client.start(settings: settings)
            _ = try await client.readRateLimits(timeoutSeconds: 3)
            await client.stop()
            throw SelfTestError.failed("dead proxy unexpectedly succeeded; direct fallback may have occurred")
        } catch is SelfTestError {
            await client.stop()
            throw SelfTestError.failed("dead proxy unexpectedly succeeded; direct fallback may have occurred")
        } catch {
            await client.stop()
            print("✓ dead proxy blocks request without direct fallback")
        }
    }

    private static func makeFakeServer(respondToRateLimits: Bool) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("fake-codex")
        let accountResponse = respondToRateLimits
            ? #"printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","email":null,"planType":"plus"},"requiresOpenaiAuth":true}}'"#
            : ":"
        let firstThreadPageResponse = respondToRateLimits
            ? #"printf '%s\n' '{"id":3,"result":{"data":[{"id":"thread-running","parentThreadId":null,"status":{"type":"active","activeFlags":[]}},{"id":"thread-stale","parentThreadId":null,"status":{"type":"notLoaded"}},{"id":"thread-child","parentThreadId":"thread-running","status":{"type":"active","activeFlags":[]}}],"nextCursor":"page-2"}}'"#
            : ":"
        let secondThreadPageResponse = respondToRateLimits
            ? #"printf '%s\n' '{"id":4,"result":{"data":[{"id":"thread-approval","parentThreadId":null,"status":{"type":"active","activeFlags":["waitingOnApproval"]}},{"id":"thread-idle","parentThreadId":null,"status":{"type":"idle"}},{"id":"thread-error","parentThreadId":null,"status":{"type":"systemError"}}],"nextCursor":null}}'"#
            : ":"
        let rateLimitResponse = respondToRateLimits
            ? #"printf '%s\n' '{"id":5,"result":{"rateLimits":{"limitId":"codex","planType":"plus","primary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":1787200782}}}}'"#
            : ":"
        let contents = """
        #!/bin/sh
        count=0
        while IFS= read -r line; do
          count=$((count + 1))
          case "$count" in
            1)
              printf '%s\\n' '{"id":1,"result":{"userAgent":"fake","platformFamily":"unix","platformOs":"macos"}}'
              ;;
            2)
              printf '%s\\n' '{"method":"thread/status/changed","params":{"threadId":"fake-thread","status":{"type":"active","activeFlags":["waitingOnUserInput"]}}}'
              ;;
            3)
              \(accountResponse)
              ;;
            4)
              \(firstThreadPageResponse)
              ;;
            5)
              \(secondThreadPageResponse)
              ;;
            6)
              \(rateLimitResponse)
              ;;
          esac
        done
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }
}
