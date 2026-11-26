import AppKit
import SwiftUI

/// A permission Berang needs you to switch on in System Settings.
enum Permission {
    case accessibility, screenRecording

    var pane: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(self == .accessibility ? "Accessibility" : "ScreenCapture")")!
    }

    var line: String {
        switch self {
        case .accessibility: "Switch on Berang"
        // macOS reports Screen Recording as on only once Berang has reopened, and offers to do it.
        case .screenRecording: "Switch on Berang, then choose Quit & Reopen"
        }
    }
}

/// The guide beside System Settings while you switch on a permission: what to switch on, and Berang's icon to drag
/// into the list in case Berang isn't in it. It never takes focus, so System Settings keeps the keyboard.
///
/// Model/Permission.tla checks:
/// - Accessibility's guide closes once the once-a-second check finds access on, and Berang comes to the front then,
///   once. No other guide brings Berang forward, and neither does a switch you turned on with no guide up.
/// - A new ask replaces the guide on screen, so there is never more than one.
/// - A guide closes after System Settings has been gone for a moment, and waits longer while Settings is opening.
@MainActor final class PermissionGuide {
    /// Called when Accessibility turns on while its guide shows.
    var granted: () -> Void = {}

    private var panel: GuidePanel?
    /// The guide fading out, which a new ask removes so two never show.
    private var leaving: GuidePanel?
    private var watching: Task<Void, Never>?
    private var lastSeen = ContinuousClock.now
    private var lastChecked = ContinuousClock.now
    private var appeared = false

    private static let checkEvery = Duration.seconds(1)
    private static let grace = Duration.milliseconds(1500)
    private static let launchGrace = Duration.seconds(6)

    /// Opens the permission's pane and shows its guide beside System Settings.
    func show(_ permission: Permission) {
        if permission == .accessibility, AXIsProcessTrusted() { return }
        NSWorkspace.shared.open(permission.pane)
        leaving?.orderOut(nil)
        if panel?.permission != permission {
            panel?.orderOut(nil)
            let next = GuidePanel(permission: permission) { [weak self] in self?.close() }
            next.follow(Self.settingsFrame())
            next.orderFrontRegardless()
            panel = next
        }
        lastSeen = .now
        lastChecked = .now
        appeared = false
        watching?.cancel()
        watching = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(40))
                self?.look()
            }
        }
    }

    func close() {
        watching?.cancel()
        watching = nil
        leaving?.orderOut(nil)
        leaving = panel
        leaving?.dismiss()
        panel = nil
    }

    private func look() {
        guard let panel else { return }
        let now = ContinuousClock.now
        if let frame = Self.settingsFrame() {
            lastSeen = now
            appeared = true
            panel.follow(frame)
        }
        if panel.permission == .accessibility, now - lastChecked >= Self.checkEvery {
            lastChecked = now
            if AXIsProcessTrusted() {
                close()
                granted()
                return
            }
        }
        if now - lastSeen > (appeared ? Self.grace : Self.launchGrace) { close() }
    }

    /// Where System Settings' window is, in screen coordinates, if one shows. The list of windows gives their
    /// bounds without Screen Recording access.
    private static func settingsFrame() -> NSRect? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first?
            .processIdentifier,
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
            let top = NSScreen.screens.first?.frame.maxY
        else { return nil }
        return windows
            .filter { $0[kCGWindowOwnerPID as String] as? pid_t == pid && $0[kCGWindowLayer as String] as? Int == 0 }
            .compactMap { ($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } }
            .max { $0.width * $0.height < $1.width * $1.height }
            .map { NSRect(x: $0.minX, y: top - $0.maxY, width: $0.width, height: $0.height) }
    }
}

@MainActor @Observable private final class GuideModel {
    var shown = false
    /// The edge of the guide that touches System Settings, which it grows out of.
    var anchor = UnitPoint.leading
}

private final class GuidePanel: NSPanel {
    let permission: Permission
    private let model = GuideModel()
    private var beside = false

    /// The room around the card for its shadow, its gap to System Settings, and its drop below Settings' top edge.
    private static let margin: CGFloat = 12
    private static let gap: CGFloat = 8
    private static let drop: CGFloat = 72

    init(permission: Permission, close: @escaping () -> Void) {
        self.permission = permission
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        // The card draws its own shadow; a window shadow would trace the transparent margin around it.
        hasShadow = false
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = GuideHost(rootView: GuideView(permission: permission, model: model, margin: Self.margin, close: close))
        // Measured first: without sizing options, the view reports no size.
        let size = host.fittingSize
        host.sizingOptions = []
        contentView = host
        setContentSize(size)
    }

    // System Settings keeps the keyboard.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Sits beside `settings`, on its right or else its left, level with a spot near its top. Without System Settings
    /// it rests at the right of the main screen until the window shows; once beside it, it stays where it was if the
    /// window goes.
    func follow(_ settings: NSRect?) {
        guard let settings else {
            guard !beside, let room = NSScreen.screens.first?.visibleFrame else { return }
            setFrameOrigin(NSPoint(x: room.maxX - frame.width + Self.margin - 16, y: room.midY - frame.height / 2))
            return
        }
        let room = NSScreen.screens.max { overlap($0.frame, settings) < overlap($1.frame, settings) }?.visibleFrame
            ?? settings
        let margin = Self.margin
        var x = settings.maxX + Self.gap - margin
        var anchor = UnitPoint.leading
        if x + frame.width - margin > room.maxX {
            x = settings.minX - Self.gap - frame.width + margin
            anchor = .trailing
        }
        x = min(max(x, room.minX - margin), room.maxX - frame.width + margin)
        let y = min(max(settings.maxY - Self.drop - frame.height + margin, room.minY - margin),
                    room.maxY - frame.height + margin)
        let target = NSRect(origin: NSPoint(x: x, y: y), size: frame.size)
        model.anchor = anchor
        let glide = isVisible && !beside && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        beside = true
        guard target != frame else { return }
        if glide {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
                animator().setFrame(target, display: true)
            }
        } else {
            setFrame(target, display: true)
        }
    }

    func dismiss() {
        withAnimation(.easeOut(duration: 0.12)) { model.shown = false }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            self?.orderOut(nil)
        }
    }

    private func overlap(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let both = a.intersection(b)
        return both.isNull ? 0 : both.width * both.height
    }
}

/// Takes the click that first reaches it, because the guide is never the key window.
private final class GuideHost: NSHostingView<GuideView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct GuideView: View {
    let permission: Permission
    let model: GuideModel
    let margin: CGFloat
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 4) {
                Text(permission.line)
                    .font(Otter.font(14, .heavy)).foregroundStyle(Otter.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Otter.soft)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(PlainButtonStyle(radius: 8))
                .accessibilityLabel("Close")
            }
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 56, height: 56)
                .onDrag {
                    NSItemProvider(object: Bundle.main.bundleURL as NSURL)
                } preview: {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                }
                .pointerStyle(.grabIdle)
                .accessibilityLabel("Berang. Drag it into the list.")
            Text("Not in the list? Drag me in.")
                .font(Otter.font(11.5, .medium)).foregroundStyle(Otter.soft)
        }
        .frame(width: 168)
        .card(padding: 14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Otter.card)
                .shadow(color: Otter.shadow, radius: 6, y: 3)
        }
        .padding(margin)
        .opacity(model.shown ? 1 : 0)
        .scaleEffect(model.shown || reduceMotion ? 1 : 0.96, anchor: model.anchor)
        .onAppear { withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.22)) { model.shown = true } }
    }
}
