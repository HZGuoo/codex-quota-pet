import AppKit
import SwiftUI
import CodexQuotaPetCore

extension Notification.Name {
    static let collapseCodexQuotaPet = Notification.Name("CodexQuotaPet.collapse")
}

struct PetBallView: View {
    static let compactSize = CGSize(width: 60, height: 60)
    static let expandedWidth: CGFloat = 276

    @ObservedObject var store: QuotaStore
    @Environment(\.colorScheme) private var colorScheme
    let onExpansionChanged: (Bool) -> Void
    @State private var expanded = false

    var body: some View {
        Group {
            if expanded {
                expandedCard
            } else {
                compactBall
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                expanded.toggle()
                onExpansionChanged(expanded)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .collapseCodexQuotaPet)) { _ in
            guard expanded else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                expanded = false
                onExpansionChanged(false)
            }
        }
        .contextMenu {
            Button("立即刷新") { store.refresh() }
            Button(expanded ? "收起详情" : "展开详情") {
                expanded.toggle()
                onExpansionChanged(expanded)
            }
            Menu("额度显示") {
                compactDisplayModeButton("5小时", mode: .fiveHour)
                compactDisplayModeButton("1周", mode: .weekly)
                compactDisplayModeButton("同时显示", mode: .both)
            }
            Divider()
            Button("鼠标穿透") {
                store.mutateSettings { $0.mousePassthrough = true }
            }
            Button("隐藏额度球") {
                store.mutateSettings { $0.showPet = false }
            }
            Divider()
            Button("退出应用", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func compactDisplayModeButton(
        _ title: String,
        mode: CompactQuotaDisplayMode
    ) -> some View {
        Button {
            store.mutateSettings { $0.compactQuotaDisplayMode = mode }
        } label: {
            if store.settings.compactQuotaDisplayMode == mode {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var compactBall: some View {
        ZStack {
            Circle()
                .fill(AuroraStyle.surface(for: colorScheme))
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            AuroraStyle.accentBlue.opacity(colorScheme == .dark ? 0.22 : 0.30),
                            Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18),
                            AuroraStyle.accentPurple.opacity(colorScheme == .dark ? 0.20 : 0.27)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
            )
            Circle()
                .strokeBorder(
                    Color.white.opacity(colorScheme == .dark ? 0.18 : 0.58),
                    lineWidth: 0.6
                )
            compactQuotaRings
            compactQuotaContent
        }
        .frame(width: Self.compactSize.width, height: Self.compactSize.height)
        .clipShape(Circle())
        .help(petHelpText)
    }

    @ViewBuilder
    private var compactQuotaRings: some View {
        switch store.settings.compactQuotaDisplayMode {
        case .fiveHour:
            compactProgressRing(
                window: store.snapshot?.fiveHourWindow,
                color: AuroraStyle.accentBlue,
                lineWidth: 3.25,
                inset: 4
            )
        case .weekly:
            compactProgressRing(
                window: store.snapshot?.weeklyWindow,
                color: AuroraStyle.accentPurple,
                lineWidth: 3.25,
                inset: 4
            )
        case .both:
            compactProgressRing(
                window: store.snapshot?.fiveHourWindow,
                color: AuroraStyle.accentBlue,
                lineWidth: 2.5,
                inset: 3.5
            )
            compactProgressRing(
                window: store.snapshot?.weeklyWindow,
                color: AuroraStyle.accentPurple,
                lineWidth: 2.5,
                inset: 7.5
            )
        }
    }

    private func compactProgressRing(
        window: QuotaWindow?,
        color: Color,
        lineWidth: CGFloat,
        inset: CGFloat
    ) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(window?.remainingPercent ?? 0) / 100)
                .stroke(
                    store.state.isStale || window == nil
                        ? AnyShapeStyle(Color.gray)
                        : AnyShapeStyle(color),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .padding(inset)
    }

    @ViewBuilder
    private var compactQuotaContent: some View {
        switch store.settings.compactQuotaDisplayMode {
        case .fiveHour:
            compactSingleQuota(
                title: "5h",
                window: store.snapshot?.fiveHourWindow,
                accent: AuroraStyle.accentBlue
            )
        case .weekly:
            compactSingleQuota(
                title: "7d",
                window: store.snapshot?.weeklyWindow,
                accent: AuroraStyle.accentPurple
            )
        case .both:
            VStack(spacing: store.taskStatus.hasActivity ? 0 : 0.75) {
                compactDualQuota(
                    label: "5h",
                    window: store.snapshot?.fiveHourWindow,
                    accent: AuroraStyle.accentBlue
                )
                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 26, height: 0.5)
                compactDualQuota(
                    label: "7d",
                    window: store.snapshot?.weeklyWindow,
                    accent: AuroraStyle.accentPurple
                )
                if store.taskStatus.hasActivity {
                    compactTaskStatus
                }
            }
        }
    }

    private func compactSingleQuota(title: String, window: QuotaWindow?, accent: Color) -> some View {
        VStack(spacing: 0) {
            Text(percentText(for: window))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor(for: window?.remainingPercent))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
            if store.taskStatus.hasActivity {
                compactTaskStatus
            }
        }
        .offset(y: store.taskStatus.hasActivity ? 1 : 2.5)
    }

    private func compactDualQuota(label: String, window: QuotaWindow?, accent: Color) -> some View {
        VStack(spacing: -1) {
            Text(percentText(for: window))
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor(for: window?.remainingPercent))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 6.25, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
        }
        .frame(height: 15.5)
    }

    private func quotaWindowRow(title: String, window: QuotaWindow?) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(percentText(for: window))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(statusColor(for: window?.remainingPercent))
                    .monospacedDigit()
            }
            ProgressView(value: Double(window?.remainingPercent ?? 0), total: 100)
                .tint(store.state.isStale || window == nil ? .gray : AuroraStyle.accent)
            HStack(spacing: 4) {
                Text(window.map { "已用 \($0.clampedUsedPercent)%" } ?? "暂无数据")
                Spacer()
                if let reset = window?.resetDate {
                    Image(systemName: "clock")
                    Text(reset, style: .relative)
                    Text("后重置")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AuroraStyle.accent.opacity(0.055))
        )
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex 剩余额度")
                        .font(.headline)
                    Text(store.snapshot?.planType?.uppercased() ?? "CHATGPT")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("双窗口")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 7) {
                quotaWindowRow(title: "5 小时额度", window: store.snapshot?.fiveHourWindow)
                quotaWindowRow(title: "周额度", window: store.snapshot?.weeklyWindow)
            }

            expandedTaskStatus

            HStack(spacing: 6) {
                Text(store.statusMessage)
                    .lineLimit(2)
                if store.isRefreshing { ProgressView().controlSize(.small) }
                Spacer(minLength: 4)
                Text("单击收起")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption2)
            .foregroundStyle(store.state.isStale ? .orange : .secondary)
        }
        .padding(14)
        .frame(width: Self.expandedWidth)
        .fixedSize(horizontal: false, vertical: true)
        .glassCard(cornerRadius: 18, shadowOpacity: 0.04)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AuroraStyle.accentPurple.opacity(0.32), lineWidth: 1)
        )
    }

    private var compactTaskStatus: some View {
        HStack(spacing: 2.5) {
            if store.taskStatus.runningCount > 0 {
                compactStatusItem(
                    systemName: "bolt.fill",
                    count: store.taskStatus.runningCount,
                    color: AuroraStyle.accentBlue
                )
            }
            if store.taskStatus.waitingApprovalCount > 0 {
                compactStatusItem(
                    systemName: "hand.raised.fill",
                    count: store.taskStatus.waitingApprovalCount,
                    color: .orange
                )
            }
            if store.taskStatus.waitingInputCount > 0 {
                compactStatusItem(
                    systemName: "questionmark.bubble.fill",
                    count: store.taskStatus.waitingInputCount,
                    color: .purple
                )
            }
        }
        .frame(height: 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(taskStatusAccessibilityText)
    }

    private func compactStatusItem(systemName: String, count: Int, color: Color) -> some View {
        HStack(spacing: 0.5) {
            Image(systemName: systemName)
                .font(.system(size: 5.5, weight: .bold))
            Text(shortCount(count))
                .font(.system(size: 6.5, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(color)
    }

    private var expandedTaskStatus: some View {
        HStack(spacing: 5) {
            expandedStatusChip(
                title: "执行",
                systemName: "bolt.fill",
                count: store.taskStatus.runningCount,
                color: AuroraStyle.accentBlue
            )
            expandedStatusChip(
                title: "待批准",
                systemName: "hand.raised.fill",
                count: store.taskStatus.waitingApprovalCount,
                color: .orange
            )
            expandedStatusChip(
                title: "待输入",
                systemName: "questionmark.bubble.fill",
                count: store.taskStatus.waitingInputCount,
                color: .purple
            )
        }
    }

    private func expandedStatusChip(
        title: String,
        systemName: String,
        count: Int,
        color: Color
    ) -> some View {
        Button {
            CodexApplicationLauncher.activate()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                Spacer(minLength: 1)
                Text("\(count)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(count > 0 ? color : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(count > 0 ? color.opacity(0.12) : AuroraStyle.accent.opacity(0.055))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(AuroraStyle.accentPurple.opacity(0.16), lineWidth: 0.6)
            }
        }
        .buttonStyle(TaskStatusChipButtonStyle())
        .help("在 Codex 中查看\(title)任务")
        .accessibilityLabel("在 Codex 中查看\(title)任务，当前 \(count) 个")
    }

    private func shortCount(_ count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }

    private var taskStatusAccessibilityText: String {
        "执行中 \(store.taskStatus.runningCount)，等待批准 \(store.taskStatus.waitingApprovalCount)，等待输入 \(store.taskStatus.waitingInputCount)"
    }

    private var petHelpText: String {
        let fiveHour = percentText(for: store.snapshot?.fiveHourWindow)
        let weekly = percentText(for: store.snapshot?.weeklyWindow)
        return "5 小时剩余 \(fiveHour)，周额度剩余 \(weekly)\n\(store.statusMessage)\n\(taskStatusAccessibilityText)"
    }

    private var compactRemainingPercent: Int? {
        let fiveHour = store.snapshot?.fiveHourWindow?.remainingPercent
        let weekly = store.snapshot?.weeklyWindow?.remainingPercent
        switch store.settings.compactQuotaDisplayMode {
        case .fiveHour:
            return fiveHour
        case .weekly:
            return weekly
        case .both:
            return [fiveHour, weekly].compactMap { $0 }.min()
        }
    }

    private var compactProgress: CGFloat {
        CGFloat(compactRemainingPercent ?? 0) / 100
    }

    private func percentText(for window: QuotaWindow?) -> String {
        window.map { "\($0.remainingPercent)%" } ?? "--"
    }

    private func statusColor(for remaining: Int?) -> Color {
        guard !store.state.isStale, let remaining else { return .gray }
        if remaining >= 60 { return .green }
        if remaining >= 30 { return .orange }
        return .red
    }
}

private struct TaskStatusChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
