import Foundation

public actor CodexRolloutTaskMonitor {
    public nonisolated let events: AsyncStream<CodexTaskEvent>
    public nonisolated let statusUpdates: AsyncStream<CodexTaskStatusSummary>
    public nonisolated let threadStatusUpdates: AsyncStream<CodexTaskStatusSnapshot>

    private struct FileState: Sendable {
        var offset: UInt64
        var pendingData = Data()
        var parseState: CodexRolloutParseState
    }

    private struct PendingApproval: Sendable {
        let event: CodexTaskEvent
        let fileURL: URL
        let deliverAfter: Date
    }

    private let continuation: AsyncStream<CodexTaskEvent>.Continuation
    private let statusContinuation: AsyncStream<CodexTaskStatusSummary>.Continuation
    private let threadStatusContinuation: AsyncStream<CodexTaskStatusSnapshot>.Continuation
    private let sessionsURL: URL
    private var fileStates: [URL: FileState] = [:]
    private var pollingTask: Task<Void, Never>?
    private var startedAt = Date.distantFuture
    private var pendingApprovals: [String: PendingApproval] = [:]
    private var lastStatus = CodexTaskStatusSummary.zero
    private var lastThreadStatus = CodexTaskStatusSnapshot.empty

    public init(sessionsURL: URL? = nil) {
        self.sessionsURL = sessionsURL
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/sessions", isDirectory: true)
        var eventContinuation: AsyncStream<CodexTaskEvent>.Continuation!
        self.events = AsyncStream { eventContinuation = $0 }
        self.continuation = eventContinuation
        var statusContinuation: AsyncStream<CodexTaskStatusSummary>.Continuation!
        self.statusUpdates = AsyncStream { statusContinuation = $0 }
        self.statusContinuation = statusContinuation
        var threadStatusContinuation: AsyncStream<CodexTaskStatusSnapshot>.Continuation!
        self.threadStatusUpdates = AsyncStream { threadStatusContinuation = $0 }
        self.threadStatusContinuation = threadStatusContinuation
    }

    deinit {
        continuation.finish()
        statusContinuation.finish()
        threadStatusContinuation.finish()
        pollingTask?.cancel()
    }

    public func start(pollInterval: TimeInterval = 2) {
        guard pollingTask == nil else { return }
        startedAt = Date()
        baselineExistingFiles()
        publishStatus(force: true)
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(max(0.5, pollInterval)))
                guard !Task.isCancelled else { return }
                await self?.scan()
            }
        }
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        fileStates.removeAll()
        pendingApprovals.removeAll()
        startedAt = .distantFuture
        lastStatus = .zero
        lastThreadStatus = .empty
        statusContinuation.yield(.zero)
        threadStatusContinuation.yield(.empty)
    }

    public func scanNow() {
        scan()
    }

    private func baselineExistingFiles() {
        fileStates.removeAll()
        for url in rolloutFiles() {
            guard let size = fileSize(url) else { continue }
            fileStates[url] = FileState(
                offset: size,
                parseState: bootstrapParseState(for: url, size: size)
            )
        }
    }

    private func scan() {
        let files = rolloutFiles()
        let existingURLs = Set(files)
        fileStates = fileStates.filter { existingURLs.contains($0.key) }
        pendingApprovals = pendingApprovals.filter { existingURLs.contains($0.value.fileURL) }
        for url in files {
            guard let size = fileSize(url) else { continue }
            if fileStates[url] == nil {
                fileStates[url] = FileState(
                    offset: 0,
                    parseState: CodexRolloutParseState(threadID: url.deletingPathExtension().lastPathComponent)
                )
            }
            readAppendedData(from: url, size: size)
        }
        flushPendingApprovals()
        publishStatus()
    }

    private func readAppendedData(from url: URL, size: UInt64) {
        guard var state = fileStates[url] else { return }
        if size < state.offset {
            state.offset = 0
            state.pendingData.removeAll()
        }
        guard size > state.offset,
              let handle = try? FileHandle(forReadingFrom: url) else {
            fileStates[url] = state
            return
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: state.offset)
            guard let data = try handle.readToEnd(), !data.isEmpty else {
                fileStates[url] = state
                return
            }
            state.offset += UInt64(data.count)
            state.pendingData.append(data)
            consumeCompleteLines(in: &state, fileURL: url)
            fileStates[url] = state
        } catch {
            fileStates[url] = state
        }
    }

    private func consumeCompleteLines(in state: inout FileState, fileURL: URL) {
        while let newline = state.pendingData.firstIndex(of: 0x0A) {
            let line = Data(state.pendingData[..<newline])
            state.pendingData.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            if let resolvedCallID = CodexRolloutEventParser.resolvedToolCallID(line: line) {
                pendingApprovals.removeValue(forKey: resolvedCallID)
            }
            for event in CodexRolloutEventParser.parse(line: line, state: &state.parseState) {
                guard event.occurredAt >= startedAt.addingTimeInterval(-1) else { continue }
                if event.kind == .waitingForApproval,
                   let detail = event.detail,
                   detail.hasPrefix("approval-call:") {
                    let callID = String(detail.dropFirst("approval-call:".count))
                    let cleanEvent = CodexTaskEvent(
                        kind: event.kind,
                        threadID: event.threadID,
                        turnID: event.turnID,
                        title: event.title,
                        occurredAt: event.occurredAt
                    )
                    pendingApprovals[callID] = PendingApproval(
                        event: cleanEvent,
                        fileURL: fileURL,
                        deliverAfter: Date().addingTimeInterval(2.5)
                    )
                } else {
                    continuation.yield(event)
                }
            }
        }
    }

    private func flushPendingApprovals() {
        let now = Date()
        let due = pendingApprovals.filter { $0.value.deliverAfter <= now }
        for (callID, pending) in due {
            pendingApprovals.removeValue(forKey: callID)
            if var fileState = fileStates[pending.fileURL] {
                fileState.parseState.waitingApprovalCallIDs.insert(callID)
                fileStates[pending.fileURL] = fileState
            }
            continuation.yield(pending.event)
        }
    }

    private func publishStatus(force: Bool = false) {
        var byThreadID: [String: CodexTaskLiveState] = [:]
        for fileState in fileStates.values {
            let state = fileState.parseState
            guard !state.isSubagent, state.isTurnActive else { continue }
            let liveState: CodexTaskLiveState
            if !state.waitingInputCallIDs.isEmpty {
                liveState = .waitingForInput
            } else if !state.waitingApprovalCallIDs.isEmpty {
                liveState = .waitingForApproval
            } else {
                liveState = .running
            }
            if let existing = byThreadID[state.threadID] {
                byThreadID[state.threadID] = preferredState(existing, liveState)
            } else {
                byThreadID[state.threadID] = liveState
            }
        }
        let threadStatus = CodexTaskStatusSnapshot(byThreadID: byThreadID)
        let summary = threadStatus.summary
        guard force || summary != lastStatus || threadStatus != lastThreadStatus else { return }
        lastStatus = summary
        lastThreadStatus = threadStatus
        statusContinuation.yield(summary)
        threadStatusContinuation.yield(threadStatus)
    }

    private func preferredState(
        _ first: CodexTaskLiveState,
        _ second: CodexTaskLiveState
    ) -> CodexTaskLiveState {
        func priority(_ state: CodexTaskLiveState) -> Int {
            switch state {
            case .running: 0
            case .waitingForApproval: 1
            case .waitingForInput: 2
            }
        }
        return priority(second) > priority(first) ? second : first
    }

    private func bootstrapParseState(for url: URL, size: UInt64) -> CodexRolloutParseState {
        var state = CodexRolloutParseState(threadID: url.deletingPathExtension().lastPathComponent)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return state }
        defer { try? handle.close() }

        let recentThreshold = Date().addingTimeInterval(-24 * 60 * 60)
        let isRecent = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))
            .flatMap(\.contentModificationDate)
            .map { $0 >= recentThreshold }
            ?? false
        if isRecent, size <= 128 * 1024 * 1024,
           let data = try? handle.readToEnd() {
            parseBootstrapLines(data, droppingFirstPartialLine: false, state: &state)
            return state
        }

        let headLimit = 128 * 1024
        if let head = try? handle.read(upToCount: headLimit) {
            if let firstLine = head.split(separator: 0x0A, omittingEmptySubsequences: true).first {
                _ = CodexRolloutEventParser.parse(line: Data(firstLine), state: &state)
            }
        }

        let tailLimit: UInt64 = 512 * 1024
        if size > UInt64(headLimit) {
            let tailOffset = size > tailLimit ? size - tailLimit : UInt64(headLimit)
            try? handle.seek(toOffset: tailOffset)
            if let tail = try? handle.readToEnd() {
                parseBootstrapLines(tail, droppingFirstPartialLine: tailOffset > 0, state: &state)
            }
        }
        return state
    }

    private func parseBootstrapLines(
        _ data: Data,
        droppingFirstPartialLine: Bool,
        state: inout CodexRolloutParseState
    ) {
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        if droppingFirstPartialLine, !lines.isEmpty { lines.removeFirst() }
        for line in lines {
            _ = CodexRolloutEventParser.parse(line: Data(line), state: &state)
        }
    }

    private func rolloutFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            urls.append(url)
        }
        return urls
    }

    private func fileSize(_ url: URL) -> UInt64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else { return nil }
        return UInt64(fileSize)
    }
}
