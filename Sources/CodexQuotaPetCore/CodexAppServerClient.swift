import Foundation

public struct CodexNotification: Sendable, Equatable {
    public let method: String
    public let params: Data?

    public init(method: String, params: Data?) {
        self.method = method
        self.params = params
    }
}

public enum CodexClientEvent: Sendable, Equatable {
    case notification(CodexNotification)
    case terminated(String?)
}

public enum CodexAppServerError: LocalizedError, Equatable {
    case notRunning
    case alreadyRunning
    case invalidMessage
    case requestTimedOut(String)
    case serverError(code: Int?, message: String)
    case processExited(String?)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notRunning:
            "Codex app-server 尚未启动。"
        case .alreadyRunning:
            "Codex app-server 已经在运行。"
        case .invalidMessage:
            "Codex app-server 返回了无法识别的数据。"
        case let .requestTimedOut(method):
            "请求超时：\(method)"
        case let .serverError(_, message):
            message
        case let .processExited(message):
            message.map { "Codex app-server 已退出：\($0)" } ?? "Codex app-server 已退出。"
        case let .writeFailed(message):
            "无法写入 Codex app-server：\(message)"
        }
    }
}

public actor CodexAppServerClient {
    public nonisolated let events: AsyncStream<CodexClientEvent>

    private let eventContinuation: AsyncStream<CodexClientEvent>.Continuation
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var recentStderr: [String] = []
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var timeoutTasks: [Int: Task<Void, Never>] = [:]
    private var nextRequestID = 1
    private var generation = 0

    public init() {
        var continuation: AsyncStream<CodexClientEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    deinit {
        eventContinuation.finish()
        process?.terminate()
    }

    public var isRunning: Bool {
        process?.isRunning == true
    }

    public func start(settings: AppSettings) async throws {
        guard process == nil else { throw CodexAppServerError.alreadyRunning }
        let executableURL = try CodexExecutableResolver.resolve(customPath: settings.customCodexPath)
        try await start(settings: settings, executableURL: executableURL)
    }

    public func start(settings: AppSettings, executableURL: URL) async throws {
        guard process == nil else { throw CodexAppServerError.alreadyRunning }
        try ProxyEndpointPreflight.check(settings: settings)

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let child = Process()
        child.executableURL = executableURL
        child.arguments = ["app-server"]
        child.standardInput = inputPipe
        child.standardOutput = outputPipe
        child.standardError = errorPipe
        child.environment = try ProxyEnvironment.make(settings: settings)

        generation += 1
        let childGeneration = generation
        child.terminationHandler = { [weak self] _ in
            Task { await self?.handleTermination(generation: childGeneration) }
        }

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.receiveStdout(data, generation: childGeneration) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.receiveStderr(data, generation: childGeneration) }
        }

        do {
            try child.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        process = child
        stdinHandle = inputPipe.fileHandleForWriting
        stdoutBuffer.removeAll(keepingCapacity: true)
        stderrBuffer.removeAll(keepingCapacity: true)
        recentStderr.removeAll(keepingCapacity: true)

        do {
            let params: [String: Any] = [
                "clientInfo": [
                    "name": "codex_quota_pet",
                    "title": "Codex Quota Pet",
                    "version": "0.1.0"
                ]
            ]
            _ = try await request(method: "initialize", params: params, timeoutSeconds: 10)
            try sendNotification(method: "initialized", params: [:])
        } catch {
            stop()
            throw error
        }
    }

    public func restart(settings: AppSettings) async throws {
        stop()
        try await start(settings: settings)
    }

    public func stop() {
        generation += 1
        let child = process
        process = nil

        for (_, timeoutTask) in timeoutTasks { timeoutTask.cancel() }
        timeoutTasks.removeAll()
        for (_, continuation) in pending {
            continuation.resume(throwing: CancellationError())
        }
        pending.removeAll()

        stdinHandle?.closeFile()
        stdinHandle = nil
        if let stdout = child?.standardOutput as? Pipe {
            stdout.fileHandleForReading.readabilityHandler = nil
        }
        if let stderr = child?.standardError as? Pipe {
            stderr.fileHandleForReading.readabilityHandler = nil
        }
        if child?.isRunning == true { child?.terminate() }
    }

    public func readAccount(timeoutSeconds: TimeInterval = 10) async throws -> AccountResponse {
        let data = try await request(
            method: "account/read",
            params: ["refreshToken": false],
            timeoutSeconds: timeoutSeconds
        )
        return try JSONDecoder().decode(AccountResponse.self, from: data)
    }

    public func readRateLimits(timeoutSeconds: TimeInterval = 10) async throws -> QuotaSnapshot {
        let data = try await request(
            method: "account/rateLimits/read",
            params: nil,
            timeoutSeconds: timeoutSeconds
        )
        return try QuotaSnapshot.decode(from: data)
    }

    private func request(
        method: String,
        params: [String: Any]?,
        timeoutSeconds: TimeInterval
    ) async throws -> Data {
        guard process?.isRunning == true, let stdinHandle else {
            throw CodexAppServerError.notRunning
        }

        let id = nextRequestID
        nextRequestID += 1
        var message: [String: Any] = ["method": method, "id": id]
        if let params { message["params"] = params }
        let messageData = try Self.jsonLine(message)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                do {
                    try stdinHandle.write(contentsOf: messageData)
                } catch {
                    pending.removeValue(forKey: id)
                    continuation.resume(throwing: CodexAppServerError.writeFailed(error.localizedDescription))
                    return
                }

                timeoutTasks[id] = Task { [weak self] in
                    let nanos = UInt64(max(0.1, timeoutSeconds) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanos)
                    guard !Task.isCancelled else { return }
                    await self?.timeoutRequest(id: id, method: method)
                }
            }
        } onCancel: {
            Task { await self.cancelRequest(id: id) }
        }
    }

    private func sendNotification(method: String, params: [String: Any]) throws {
        guard let stdinHandle else { throw CodexAppServerError.notRunning }
        let data = try Self.jsonLine(["method": method, "params": params])
        do {
            try stdinHandle.write(contentsOf: data)
        } catch {
            throw CodexAppServerError.writeFailed(error.localizedDescription)
        }
    }

    private static func jsonLine(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        return data
    }

    private func receiveStdout(_ data: Data, generation receivedGeneration: Int) {
        guard receivedGeneration == generation else { return }
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = Data(stdoutBuffer[..<newline])
            stdoutBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handleLine(line)
        }
    }

    private func handleLine(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let id = object["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
            timeoutTasks.removeValue(forKey: id)?.cancel()
            if let error = object["error"] as? [String: Any] {
                continuation.resume(throwing: CodexAppServerError.serverError(
                    code: error["code"] as? Int,
                    message: error["message"] as? String ?? "Codex app-server 请求失败。"
                ))
                return
            }
            guard let result = object["result"],
                  let resultData = try? JSONSerialization.data(withJSONObject: result) else {
                continuation.resume(throwing: CodexAppServerError.invalidMessage)
                return
            }
            continuation.resume(returning: resultData)
            return
        }

        if let method = object["method"] as? String {
            let paramsData = object["params"].flatMap {
                try? JSONSerialization.data(withJSONObject: $0)
            }
            eventContinuation.yield(.notification(CodexNotification(method: method, params: paramsData)))
        }
    }

    private func receiveStderr(_ data: Data, generation receivedGeneration: Int) {
        guard receivedGeneration == generation else { return }
        stderrBuffer.append(data)
        while let newline = stderrBuffer.firstIndex(of: 0x0A) {
            let lineData = Data(stderrBuffer[..<newline])
            stderrBuffer.removeSubrange(...newline)
            let line = String(decoding: lineData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            recentStderr.append(Self.sanitize(line))
            if recentStderr.count > 20 { recentStderr.removeFirst(recentStderr.count - 20) }
        }
    }

    private static func sanitize(_ line: String) -> String {
        let lowered = line.lowercased()
        if lowered.contains("token") || lowered.contains("authorization") || lowered.contains("bearer") {
            return "[已隐藏可能包含凭证的日志]"
        }
        return String(line.prefix(500))
    }

    private func timeoutRequest(id: Int, method: String) {
        timeoutTasks.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(
            throwing: CodexAppServerError.requestTimedOut(method)
        )
    }

    private func cancelRequest(id: Int) {
        timeoutTasks.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    private func handleTermination(generation terminatedGeneration: Int) {
        guard terminatedGeneration == generation else { return }
        let message = recentStderr.last
        process = nil
        stdinHandle = nil
        for (_, timeoutTask) in timeoutTasks { timeoutTask.cancel() }
        timeoutTasks.removeAll()
        for (_, continuation) in pending {
            continuation.resume(throwing: CodexAppServerError.processExited(message))
        }
        pending.removeAll()
        eventContinuation.yield(.terminated(message))
    }
}
