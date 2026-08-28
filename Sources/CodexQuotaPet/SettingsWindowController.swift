import AppKit
import SwiftUI
import CodexQuotaPetCore

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(store: QuotaStore) {
        if let window {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Quota Pet 设置"
        window.backgroundColor = .clear
        window.isOpaque = false
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = PersistentScrollbarHostingView(rootView: SettingsView(store: store))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
    }
}

private struct SettingsView: View {
    @ObservedObject var store: QuotaStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var draft: AppSettings
    @State private var proxyURLText: String
    @State private var refreshMinutesText: String
    @State private var codexPathText: String
    @State private var proxyIsEditing = false
    @State private var refreshIsEditing = false
    @State private var proxyInputError: String?
    @State private var refreshInputError: String?
    @State private var isTesting = false
    @State private var testMessage: String?
    @FocusState private var focusedInput: SettingsInputField?

    init(store: QuotaStore) {
        self.store = store
        _draft = State(initialValue: store.settings)
        _proxyURLText = State(initialValue: store.settings.proxyURL)
        _refreshMinutesText = State(initialValue: String(store.settings.refreshIntervalMinutes))
        _codexPathText = State(initialValue: Self.resolvedCodexPath(for: store.settings))
    }

    var body: some View {
        ZStack {
            AuroraBackdrop(material: .sidebar)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Form {
                Section("网络代理") {
                Picker("模式", selection: $draft.proxyMode) {
                    ForEach(ProxyMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                HStack(spacing: 8) {
                    Text("代理地址")
                    Spacer()
                    TextField("http://127.0.0.1:10808", text: $proxyURLText)
                        .labelsHidden()
                        .settingsInputStyle(
                            isEditing: proxyIsEditing,
                            isInvalid: proxyInputError != nil
                        )
                        .frame(maxWidth: 340)
                        .focused($focusedInput, equals: .proxyURL)
                        .onSubmit { finishProxyEditing() }
                        .disabled(draft.proxyMode == .disabled)
                        .accessibilityLabel("代理地址")
                }
                if let proxyInputError {
                    Text(proxyInputError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                }
                .listRowBackground(glassRowColor)

                Section("刷新") {
                HStack(spacing: 8) {
                    Text("刷新间隔（1～60 分钟）")
                    Spacer()
                    TextField("分钟数", text: $refreshMinutesText)
                        .labelsHidden()
                        .settingsInputStyle(
                            isEditing: refreshIsEditing,
                            isInvalid: refreshInputError != nil
                        )
                        .frame(width: 64)
                        .multilineTextAlignment(.center)
                        .focused($focusedInput, equals: .refreshMinutes)
                        .onChange(of: refreshMinutesText) { newValue in
                            if let minutes = validRefreshMinutes(from: newValue) {
                                draft.refreshIntervalMinutes = minutes
                                refreshInputError = nil
                            } else {
                                refreshInputError = "请输入 1～60 的整数分钟。"
                            }
                        }
                        .onSubmit { finishRefreshEditing() }
                        .accessibilityLabel("刷新间隔（分钟）")
                    Text("分钟")
                    refreshAdjustmentControl
                    Button {
                        refreshMinutesText = "1"
                        draft.refreshIntervalMinutes = 1
                        refreshIsEditing = false
                        refreshInputError = nil
                        focusedInput = nil
                    } label: {
                        Label("恢复默认", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(AppActionButtonStyle())
                }
                }
                .listRowBackground(glassRowColor)

                Section("桌面额度球") {
                Toggle("显示额度球", isOn: $draft.showPet)
                Picker("额度显示", selection: $draft.compactQuotaDisplayMode) {
                    ForEach(CompactQuotaDisplayMode.allCases) { mode in
                        Text(mode.shortDisplayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("保持最前", isOn: $draft.alwaysOnTop)
                Toggle("鼠标穿透", isOn: $draft.mousePassthrough)
                Toggle("失去焦点时自动收起", isOn: $draft.collapsePetOnFocusLoss)
                }
                .listRowBackground(glassRowColor)

                Section("任务状态通知") {
                Toggle("启用系统通知", isOn: $draft.taskNotificationsEnabled)
                Group {
                    Toggle("任务完成", isOn: $draft.notifyTaskCompleted)
                    Toggle("任务失败", isOn: $draft.notifyTaskFailed)
                    Toggle("等待操作批准", isOn: $draft.notifyWaitingForApproval)
                    Toggle("等待用户输入", isOn: $draft.notifyWaitingForInput)
                    Toggle("隐藏任务内容", isOn: $draft.privateNotificationContent)
                }
                .disabled(!draft.taskNotificationsEnabled)
                .opacity(draft.taskNotificationsEnabled ? 1 : 0.45)
                }
                .listRowBackground(glassRowColor)

                Section("应用") {
                Toggle("登录后自动运行", isOn: $draft.launchAtLogin)
                HStack(alignment: .firstTextBaseline) {
                    Text("Codex 可执行文件")
                    Spacer()
                    Button {
                        chooseCodex()
                    } label: {
                        Label("选择…", systemImage: "folder")
                    }
                    .buttonStyle(AppActionButtonStyle())
                }
                Text(codexPathText.isEmpty ? "未找到 Codex 可执行文件" : codexPathText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(codexPathText.isEmpty ? "未找到 Codex 可执行文件" : codexPathText)
                    .textSelection(.enabled)
                }
                .listRowBackground(glassRowColor)

                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(12)

                Divider().opacity(0.45)
                actionFooter
            }
        }
        .frame(width: 520, height: 520)
        .tint(AuroraStyle.accent)
        .onChange(of: focusedInput) { newValue in
            switch newValue {
            case .proxyURL:
                proxyIsEditing = true
                proxyInputError = nil
            case .refreshMinutes:
                refreshIsEditing = true
                refreshInputError = nil
                moveInsertionPointToEnd()
            case nil:
                break
            }
        }
    }

    private var glassRowColor: Color {
        AuroraStyle.surface(for: colorScheme)
    }

    private var actionFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    runConnectionTest()
                } label: {
                    Label("测试连接", systemImage: "network")
                }
                .buttonStyle(AppActionButtonStyle())
                .disabled(isTesting)
                if isTesting { ProgressView().controlSize(.small) }
                Spacer()
                Button {
                    restoreDraft()
                } label: {
                    Label("放弃修改", systemImage: "xmark")
                }
                    .buttonStyle(AppActionButtonStyle())
                    .disabled(!hasAnyChanges)
                Button {
                    applyDraft()
                } label: {
                    Label("应用修改", systemImage: "checkmark")
                }
                    .buttonStyle(AppActionButtonStyle(foregroundColor: AuroraStyle.accent))
                    .disabled(hasUnconfirmedInput || !hasDraftChanges)
            }

            if let testMessage {
                Text(testMessage)
                    .font(.caption)
                    .foregroundStyle(testMessage.contains("成功") ? .green : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else if let settingsMessage = store.settingsMessage {
                Text(settingsMessage)
                    .font(.caption)
                    .foregroundStyle(settingsMessage.contains("保存") ? .green : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AuroraStyle.accent.opacity(0.10))
                .frame(height: 1)
        }
    }

    private var refreshMinutesBinding: Binding<Int> {
        Binding(
            get: {
                validRefreshMinutes(from: refreshMinutesText) ?? draft.refreshIntervalMinutes
            },
            set: { minutes in
                refreshMinutesText = String(minutes)
                draft.refreshIntervalMinutes = minutes
                refreshIsEditing = false
                refreshInputError = nil
                focusedInput = nil
            }
        )
    }

    private var refreshAdjustmentControl: some View {
        VStack(spacing: 4) {
            refreshAdjustmentButton(
                systemName: "chevron.up",
                accessibilityLabel: "增加刷新间隔",
                delta: 1
            )
            refreshAdjustmentButton(
                systemName: "chevron.down",
                accessibilityLabel: "减少刷新间隔",
                delta: -1
            )
        }
    }

    private func refreshAdjustmentButton(
        systemName: String,
        accessibilityLabel: String,
        delta: Int
    ) -> some View {
        let currentValue = refreshMinutesBinding.wrappedValue
        let boundary = delta > 0
            ? AppSettings.maximumRefreshIntervalMinutes
            : AppSettings.minimumRefreshIntervalMinutes

        return Button {
            let adjusted = min(
                AppSettings.maximumRefreshIntervalMinutes,
                max(AppSettings.minimumRefreshIntervalMinutes, currentValue + delta)
            )
            refreshMinutesBinding.wrappedValue = adjusted
        } label: {
            Image(systemName: systemName)
        }
        .buttonStyle(RefreshAdjustmentButtonStyle())
        .disabled(currentValue == boundary)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var hasUnconfirmedInput: Bool {
        proxyIsEditing
            || proxyInputError != nil
            || refreshInputError != nil
    }

    private var hasDraftChanges: Bool {
        var candidate = draft.normalized
        var current = store.settings.normalized
        candidate.customCodexPath = Self.resolvedCodexPath(for: candidate)
        current.customCodexPath = Self.resolvedCodexPath(for: current)
        return candidate != current
    }

    private var hasAnyChanges: Bool {
        hasDraftChanges
            || proxyURLText != draft.proxyURL
            || refreshMinutesText != String(draft.refreshIntervalMinutes)
            || codexPathText != Self.resolvedCodexPath(for: draft)
    }

    private func validRefreshMinutes(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed),
              (AppSettings.minimumRefreshIntervalMinutes...AppSettings.maximumRefreshIntervalMinutes).contains(value) else {
            return nil
        }
        return value
    }

    private func finishRefreshEditing() {
        guard let minutes = validRefreshMinutes(from: refreshMinutesText) else {
            refreshInputError = "请输入 1～60 的整数分钟。"
            return
        }
        draft.refreshIntervalMinutes = minutes
        refreshMinutesText = String(minutes)
        refreshIsEditing = false
        refreshInputError = nil
        focusedInput = nil
    }

    private func finishProxyEditing() {
        var candidate = draft
        candidate.proxyURL = proxyURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try candidate.validateProxy()
            draft.proxyURL = candidate.proxyURL
            proxyURLText = candidate.proxyURL
            proxyIsEditing = false
            proxyInputError = nil
            focusedInput = nil
        } catch {
            proxyInputError = error.localizedDescription
        }
    }

    private func runConnectionTest() {
        var testSettings = draft
        testSettings.proxyURL = proxyURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let minutes = validRefreshMinutes(from: refreshMinutesText) {
            testSettings.refreshIntervalMinutes = minutes
        }

        isTesting = true
        testMessage = "正在测试连接…"
        Task {
            let result = await store.testConnection(with: testSettings)
            isTesting = false
            switch result {
            case let .success(snapshot):
                testMessage = "连接成功，当前剩余 \(snapshot.remainingPercent.map(String.init) ?? "--")%。"
            case let .failure(error):
                testMessage = "连接失败：\(error.localizedDescription)"
            }
        }
    }

    private func restoreDraft() {
        draft = store.settings
        proxyURLText = store.settings.proxyURL
        refreshMinutesText = String(store.settings.refreshIntervalMinutes)
        codexPathText = Self.resolvedCodexPath(for: store.settings)
        proxyIsEditing = false
        refreshIsEditing = false
        proxyInputError = nil
        refreshInputError = nil
        focusedInput = nil
        testMessage = nil
    }

    private func applyDraft() {
        guard !hasUnconfirmedInput else { return }
        refreshIsEditing = false
        focusedInput = nil
        store.applySettings(draft)
        if store.settings == draft.normalized {
            draft = store.settings
            proxyURLText = store.settings.proxyURL
            refreshMinutesText = String(store.settings.refreshIntervalMinutes)
            codexPathText = Self.resolvedCodexPath(for: store.settings)
        }
    }

    private func chooseCodex() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            let selectedPath = panel.url?.path ?? draft.customCodexPath
            draft.customCodexPath = selectedPath
            codexPathText = selectedPath
        }
    }

    private func moveInsertionPointToEnd() {
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                guard focusedInput == .refreshMinutes,
                      let editor = NSApp.keyWindow?.fieldEditor(false, for: nil) as? NSTextView else {
                    return
                }
                let end = editor.string.utf16.count
                editor.setSelectedRange(NSRange(location: end, length: 0))
                editor.scrollRangeToVisible(NSRange(location: end, length: 0))
            }
        }
    }

    private static func resolvedCodexPath(for settings: AppSettings) -> String {
        (try? CodexExecutableResolver.resolve(customPath: settings.customCodexPath).path)
            ?? settings.customCodexPath
    }
}

private enum SettingsInputField: Hashable {
    case proxyURL
    case refreshMinutes
}

private final class PersistentScrollbarHostingView<Content: View>: NSHostingView<Content> {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureScrollbars()
    }

    override func layout() {
        super.layout()
        configureScrollbars()
    }

    private func configureScrollbars() {
        func configure(in view: NSView) {
            if let scrollView = view as? NSScrollView {
                if !scrollView.hasVerticalScroller { scrollView.hasVerticalScroller = true }
                if scrollView.autohidesScrollers { scrollView.autohidesScrollers = false }
                if scrollView.scrollerStyle != .legacy { scrollView.scrollerStyle = .legacy }
                if !(scrollView.verticalScroller is ModernVerticalScroller) {
                    let scroller = ModernVerticalScroller(frame: .zero)
                    scroller.controlSize = .small
                    scrollView.verticalScroller = scroller
                }
                scrollView.drawsBackground = false
                scrollView.backgroundColor = .clear
                scrollView.wantsLayer = true
                scrollView.layer?.cornerRadius = 14
                scrollView.layer?.cornerCurve = .continuous
                scrollView.layer?.masksToBounds = true
                scrollView.contentView.drawsBackground = false
                scrollView.contentView.backgroundColor = .clear
                scrollView.verticalScroller?.isHidden = false
                scrollView.verticalScroller?.alphaValue = 1
            }
            view.subviews.forEach { configure(in: $0) }
        }

        configure(in: self)
    }
}

private final class ModernVerticalScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        drawKnobSlot(in: bounds, highlight: false)
        drawKnob()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        let trackWidth: CGFloat = 5
        let trackRect = NSRect(
            x: bounds.midX - trackWidth / 2,
            y: bounds.minY + 6,
            width: trackWidth,
            height: max(0, bounds.height - 12)
        )
        NSColor(red: 0.42, green: 0.35, blue: 0.87, alpha: 0.11).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: trackWidth / 2, yRadius: trackWidth / 2).fill()
    }

    override func drawKnob() {
        let rawKnobRect = rect(for: .knob)
        guard rawKnobRect.height > 0 else { return }
        let knobWidth: CGFloat = 7
        let knobRect = NSRect(
            x: bounds.midX - knobWidth / 2,
            y: rawKnobRect.minY + 1,
            width: knobWidth,
            height: max(12, rawKnobRect.height - 2)
        )
        NSColor(red: 0.42, green: 0.35, blue: 0.87, alpha: 0.48).setFill()
        NSBezierPath(roundedRect: knobRect, xRadius: knobWidth / 2, yRadius: knobWidth / 2).fill()
    }
}

private struct RefreshAdjustmentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Color.primary)
            .frame(width: 26, height: 16)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? AuroraStyle.accent.opacity(0.16)
                            : AuroraStyle.accent.opacity(0.07)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(AuroraStyle.accent.opacity(0.18), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.84 : 1) : 0.32)
    }
}

private extension View {
    func settingsInputStyle(isEditing: Bool, isInvalid: Bool) -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .foregroundStyle(isEditing ? Color.black : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isInvalid
                            ? Color.red.opacity(0.16)
                            : isEditing
                                ? Color.white
                                : AuroraStyle.accent.opacity(0.07)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        isInvalid ? Color.red : AuroraStyle.accent.opacity(isEditing ? 0.38 : 0.18),
                        lineWidth: isInvalid ? 1.5 : 1
                    )
            )
    }
}
