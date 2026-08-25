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
            Divider()
            Button("鼠标穿透") {
                store.mutateSettings { $0.mousePassthrough = true }
            }
            Button("隐藏额度球") {
                store.mutateSettings { $0.showPet = false }
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
                .strokeBorder(AuroraStyle.accentPurple.opacity(0.38), lineWidth: 0.8)
            Circle()
                .stroke(AuroraStyle.accent.opacity(0.15), lineWidth: 5)
                .padding(4)
            if store.remainingPercent == nil || store.state.isStale {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.gray, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(4)
            } else {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [
                                AuroraStyle.accentBlue,
                                AuroraStyle.accent,
                                AuroraStyle.accentPurple,
                                AuroraStyle.accentBlue
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(4)
            }
            VStack(spacing: 0) {
                Text(percentageText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(statusColor)
                    .monospacedDigit()
                if store.taskStatus.hasActivity {
                    compactTaskStatus
                } else {
                    Text("Codex")
                        .font(.system(size: 7.5, weight: .medium, design: .rounded))
                        .foregroundStyle(AuroraStyle.accent.opacity(0.74))
                }
            }
            .offset(y: 2)
        }
        .frame(width: Self.compactSize.width, height: Self.compactSize.height)
        .clipShape(Circle())
        .help(petHelpText)
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
                Text(percentageText)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(statusColor)
            }
            ProgressView(value: Double(store.remainingPercent ?? 0), total: 100)
                .tint(store.state.isStale ? .gray : AuroraStyle.accent)

            expandedTaskStatus

            if let snapshot = store.snapshot {
                VStack(spacing: 5) {
                    ForEach(snapshot.buckets.prefix(3)) { bucket in
                        HStack {
                            Text(bucket.displayName)
                                .lineLimit(1)
                            Spacer()
                            Text(bucket.remainingPercent.map { "剩余 \($0)%" } ?? "--")
                                .monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
                if let reset = snapshot.limitingBucket?.limitingWindow?.resetDate {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(reset, style: .relative)
                        Text("后重置 · \(Self.resetTimeFormatter.string(from: reset))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

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
        "\(store.statusMessage)\n\(taskStatusAccessibilityText)"
    }

    private var progress: CGFloat {
        CGFloat(store.remainingPercent ?? 0) / 100
    }

    private var percentageText: String {
        store.remainingPercent.map { "\($0)%" } ?? "--"
    }

    private var statusColor: Color {
        guard !store.state.isStale, let remaining = store.remainingPercent else { return .gray }
        if remaining >= 60 { return .green }
        if remaining >= 30 { return .orange }
        return .red
    }

    private static let resetTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MdHHmm")
        return formatter
    }()
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
