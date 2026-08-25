import AppKit
import SwiftUI
import CodexQuotaPetCore

struct MenuBarView: View {
    @ObservedObject var store: QuotaStore

    var body: some View {
        ZStack {
            AuroraBackdrop(material: .popover)

            VStack(alignment: .leading, spacing: 12) {
                header
                quotaDetails
                    .padding(12)
                    .glassCard(cornerRadius: 13, shadowOpacity: 0.035)
                controls
            }
            .padding(14)
        }
        .frame(width: 330)
        .tint(AuroraStyle.accent)
        .background(MenuBarWindowConfigurator())
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(.thinMaterial)
                Circle().fill(
                    LinearGradient(
                        colors: [
                            AuroraStyle.accentBlue.opacity(0.20),
                            AuroraStyle.accentPurple.opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                Circle().strokeBorder(Color.white.opacity(0.68), lineWidth: 0.7)
                if let icon = BrandIcon.templateImage {
                    Image(nsImage: icon)
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 23, height: 23)
                        .foregroundStyle(AuroraStyle.accent)
                } else {
                    Image(systemName: "gauge")
                        .font(.title2)
                        .foregroundStyle(AuroraStyle.accent)
                }
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex Quota Pet")
                    .font(.headline)
                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text(store.remainingPercent.map { "\($0)%" } ?? "--")
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var quotaDetails: some View {
        if let snapshot = store.snapshot {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("套餐")
                    Spacer()
                    Text(snapshot.planType?.uppercased() ?? "未知")
                }
                .font(.caption)

                ForEach(snapshot.buckets) { bucket in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(bucket.displayName).lineLimit(1)
                            Spacer()
                            Text(bucket.remainingPercent.map { "剩余 \($0)%" } ?? "--")
                                .monospacedDigit()
                        }
                        .font(.caption.weight(.medium))
                        if let window = bucket.limitingWindow {
                            HStack {
                                Text(windowDescription(window))
                                Spacer()
                                if let reset = window.resetDate {
                                    Text(reset, style: .relative)
                                    Text("后重置")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    Text("更新于")
                    Spacer()
                    Text(snapshot.refreshedAt.formatted(date: .omitted, time: .standard))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        } else {
            Text("尚无额度数据。请检查 ChatGPT 登录状态、Codex 路径和代理设置。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    store.refresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(AppActionButtonStyle(foregroundColor: AuroraStyle.accent))
                .disabled(store.isRefreshing)
                Spacer()
                if store.isRefreshing { ProgressView().controlSize(.small) }
                Text(proxySummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(proxySummary)
            }

            VStack(spacing: 0) {
                settingToggle(
                    "显示桌面额度球",
                    isOn: Binding(
                        get: { store.settings.showPet },
                        set: { value in store.mutateSettings { $0.showPet = value } }
                    )
                )
                Divider()
                settingToggle(
                    "保持最前",
                    isOn: Binding(
                        get: { store.settings.alwaysOnTop },
                        set: { value in store.mutateSettings { $0.alwaysOnTop = value } }
                    )
                )
                Divider()
                settingToggle(
                    "鼠标穿透",
                    isOn: Binding(
                        get: { store.settings.mousePassthrough },
                        set: { value in store.mutateSettings { $0.mousePassthrough = value } }
                    )
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .glassCard(cornerRadius: 11, shadowOpacity: 0.025)

            HStack {
                Button {
                    openSettings()
                } label: {
                    Label("更多设置…", systemImage: "gearshape")
                }
                .buttonStyle(AppActionButtonStyle(foregroundColor: AuroraStyle.accent))
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出", systemImage: "power")
                }
                .buttonStyle(AppActionButtonStyle(foregroundColor: .red))
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func settingToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .fixedSize()
        }
        .frame(minHeight: 30)
        .contentShape(Rectangle())
    }

    private var proxySummary: String {
        store.settings.proxyMode == .disabled ? "直连" : store.settings.proxyURL
    }

    private var statusColor: Color {
        guard !store.state.isStale, let remaining = store.remainingPercent else { return .gray }
        if remaining >= 60 { return .green }
        if remaining >= 30 { return .orange }
        return .red
    }

    private func openSettings() {
        let menuWindow = NSApp.keyWindow
        menuWindow?.orderOut(nil)
        DispatchQueue.main.async {
            SettingsWindowController.shared.show(store: store)
        }
    }

    private func windowDescription(_ window: QuotaWindow) -> String {
        guard let minutes = window.windowDurationMins else { return "已用 \(window.clampedUsedPercent)%" }
        if minutes % 10_080 == 0 { return "\(minutes / 10_080) 周窗口 · 已用 \(window.clampedUsedPercent)%" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440) 天窗口 · 已用 \(window.clampedUsedPercent)%" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时窗口 · 已用 \(window.clampedUsedPercent)%" }
        return "\(minutes) 分钟窗口 · 已用 \(window.clampedUsedPercent)%"
    }
}

private struct MenuBarWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        MenuBarWindowConfigurationView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? MenuBarWindowConfigurationView)?.configureWindow()
    }

    private final class MenuBarWindowConfigurationView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        func configureWindow() {
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window else { return }
                window.backgroundColor = .clear
                window.isOpaque = false
                window.contentView?.wantsLayer = true
                window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
                window.contentView?.layer?.borderWidth = 0
            }
        }
    }
}
