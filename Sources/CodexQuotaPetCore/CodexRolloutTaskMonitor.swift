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

    private struct RolloutFile: Sendable {
        let url: URL
        let size: UInt64
        let modifiedAt: Date
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
    private var trackedFileURLs: Set<URL> = []
    private var pollingTask: Task<Void, Never>?
    private var nextFileDiscoveryAt = Date.distantPast
    private var startedAt = Date.distantFuture
    private var pendingApprovals: [String: PendingApproval] = [:]
    private var lastStatus = CodexTaskStatusSummary.zero
    private var lastThreadStatus = CodexTaskStatusSnapshot.empty

    private static let fileDiscoveryInterval: TimeInterval = 10
    private static let recentFileGraceInterval: TimeInterval = 10 * 60

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
                await self?.scan(forceFileDiscovery: false)
            }
        }
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        fileStates.removeAll()
        trackedFileURLs.removeAll()
        nextFileDiscoveryAt = .distantPast
        pendingApprovals.removeAll()
        startedAt = .distantFuture
        lastStatus = .zero
        lastThreadStatus = .empty
        statusContinuation.yield(.zero)
        threadStatusContinuation.yield(.empty)
    }

    public func scanNow() {
        scan(forceFileDiscovery: true)
    }

    private func baselineExistingFiles() {
        fileStates.removeAll()
        trackedFileURLs.removeAll()
        let recentThreshold = Date().addingTimeInterval(-Self.recentFileGraceInterval)
        for file in rolloutFiles() {
            let state = FileState(
                offset: file.size,
                parseState: bootstrapParseState(for: file.url, size: file.size)
            )
            fileStates[file.url] = state
            if state.parseState.isTurnActive || file.modifiedAt >= recentThreshold {
                trackedFileURLs.insert(file.url)
            }
        }
        nextFileDiscoveryAt = Date().addingTimeInterval(Self.fileDiscoveryInterval)
    }

    private func scan(forceFileDiscovery: Bool) {
        if forceFileDiscovery || Date() >= nextFileDiscoveryAt {
            refreshTrackedFiles()
        }

        for url in Array(trackedFileURLs) {
            guard let size = fileSize(url) else {
                trackedFileURLs.remove(url)
                fileStates.removeValue(forKey: url)
                pendingApprovals = pendingApprovals.filter { $0.value.fileURL != url }
                continue
            }
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

    private func refreshTrackedFiles() {
        let files = rolloutFiles()
        let existingURLs = Set(files.map(\.url))
        fileStates = fileStates.filter { existingURLs.contains($0.key) }
        pendingApprovals = pendingApprovals.filter { existingURLs.contains($0.value.fileURL) }

        let recentThreshold = Date().addingTimeInterval(-Self.recentFileGraceInterval)
        var nextTrackedFileURLs: Set<URL> = []
        for file in files {
            if fileStates[file.url] == nil {
                fileStates[file.url] = FileState(
                    offset: 0,
                    parseState: CodexRolloutParseState(
                        threadID: file.url.deletingPathExtension().lastPathComponent
                    )
                )
            }
            if fileStates[file.url]?.parseState.isTurnActive == true
                || file.modifiedAt >= recentThreshold {
                nextTrackedFileURLs.insert(file.url)
            }
        }
        trackedFileURLs = nextTrackedFileURLs
        nextFileDiscoveryAt = Date().addingTimeInterval(Self.fileDiscoveryInterval)
    }

    private func readAppendedData(from url: URL, size: UInt64) {
        guard var state = fileStates[url] else { return }
        if size < state.offset {
            state.offset = 0
            state.pendingData.removeAll()
            state.parseState = CodexRolloutParseState(
                threadID: url.deletingPathExtension().lastPathComponent
            )
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
        for url in trackedFileURLs {
            guard let fileState = fileStates[url] else { continue }
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

    private func rolloutFiles() -> [RolloutFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [RolloutFile] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            ), values.isRegularFile == true,
               let size = values.fileSize,
               let modifiedAt = values.contentModificationDate else {
                continue
            }
            files.append(RolloutFile(url: url, size: UInt64(size), modifiedAt: modifiedAt))
        }
        return files
    }

    private func fileSize(_ url: URL) -> UInt64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else { return nil }
        return UInt64(fileSize)
    }
}
