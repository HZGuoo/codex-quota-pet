import AppKit
import Combine
import SwiftUI
import CodexQuotaPetCore

final class PetPanel: NSPanel {
    var allowsKeyWindow = false

    override var canBecomeKey: Bool { allowsKeyWindow }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PetPanelController: NSObject, NSWindowDelegate {
    static let shared = PetPanelController()

    private var panel: PetPanel?
    private var hostingView: NSHostingView<PetBallView>?
    private var compactOriginBeforeExpansion: NSPoint?
    private var collapseOnFocusLoss = true
    private var cancellables: Set<AnyCancellable> = []
    private var screenObserver: Any?

    private override init() {
        super.init()
    }

    func start(store: QuotaStore) {
        guard panel == nil else { return }
        let compactSize = NSSize(
            width: PetBallView.compactSize.width,
            height: PetBallView.compactSize.height
        )
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)
        let origin = NSPoint(
            x: visibleFrame.maxX - compactSize.width - 28,
            y: visibleFrame.maxY - compactSize.height - 28
        )
        let panel = PetPanel(
            contentRect: NSRect(origin: origin, size: compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.setFrameAutosaveName("CodexQuotaPet.panelFrame")
        var compactFrame = panel.frame
        compactFrame.size = compactSize
        panel.setFrame(compactFrame, display: false)
        let hostingView = NSHostingView(rootView: PetBallView(
            store: store,
            onExpansionChanged: { [weak self] expanded in self?.resize(expanded: expanded) }
        ))
        panel.contentView = hostingView
        panel.delegate = self
        self.hostingView = hostingView
        self.panel = panel

        store.$settings
            .removeDuplicates()
            .sink { [weak self] settings in self?.apply(settings) }
            .store(in: &cancellables)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.ensureVisible() }
        }
        apply(store.settings)
        ensureVisible()
    }

    func show() {
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func apply(_ settings: AppSettings) {
        guard let panel else { return }
        panel.level = settings.alwaysOnTop ? .floating : .normal
        panel.ignoresMouseEvents = settings.mousePassthrough
        collapseOnFocusLoss = settings.collapsePetOnFocusLoss
        settings.showPet ? panel.orderFrontRegardless() : panel.orderOut(nil)
    }

    private func resize(expanded: Bool) {
        guard let panel, let hostingView else { return }
        guard expanded else {
            panel.allowsKeyWindow = false
            let compactSize = NSSize(
                width: PetBallView.compactSize.width,
                height: PetBallView.compactSize.height
            )
            let fallbackOrigin = NSPoint(
                x: panel.frame.midX - compactSize.width / 2,
                y: panel.frame.midY - compactSize.height / 2
            )
            let origin = compactOriginBeforeExpansion ?? fallbackOrigin
            compactOriginBeforeExpansion = nil
            setFrame(NSRect(origin: origin, size: compactSize), for: panel)
            return
        }

        panel.allowsKeyWindow = true
        compactOriginBeforeExpansion = panel.frame.origin
        hostingView.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self, weak panel, weak hostingView] in
            guard let self, let panel, let hostingView else { return }
            hostingView.layoutSubtreeIfNeeded()
            let fittingSize = hostingView.fittingSize
            let newSize = NSSize(width: PetBallView.expandedWidth, height: fittingSize.height)
            self.setSize(newSize, for: panel)
            panel.makeKey()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard collapseOnFocusLoss, panel?.allowsKeyWindow == true else { return }
        NotificationCenter.default.post(name: .collapseCodexQuotaPet, object: nil)
    }

    private func setSize(_ newSize: NSSize, for panel: NSPanel) {
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let frame = NSRect(
            x: center.x - newSize.width / 2,
            y: center.y - newSize.height / 2,
            width: newSize.width,
            height: newSize.height
        )
        setFrame(frame, for: panel)
    }

    private func setFrame(_ requestedFrame: NSRect, for panel: NSPanel) {
        var frame = requestedFrame
        frame = constrained(frame)
        panel.setFrame(frame, display: true, animate: true)
    }

    private func ensureVisible() {
        guard let panel else { return }
        let frame = constrained(panel.frame)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }

    private func constrained(_ frame: NSRect) -> NSRect {
        let targetScreen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main
        guard let visible = targetScreen?.visibleFrame else { return frame }
        var result = frame
        result.origin.x = min(max(result.origin.x, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.origin.y, visible.minY), visible.maxY - result.height)
        return result
    }
}
