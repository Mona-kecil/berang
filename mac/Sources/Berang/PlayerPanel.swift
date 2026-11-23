import AppKit
import SwiftUI
import TextGrab

/// A floating player that never takes focus, so the app being read stays frontmost. It shows while Berang reads,
/// gets a voice ready, or has something to say, and hides when it stops.
final class PlayerPanel: NSPanel {
    init(player: Player) {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: PlayerView(player: player))
        setContentSize(contentView!.fittingSize)
        if let screen = NSScreen.main?.visibleFrame {
            setFrameOrigin(NSPoint(x: screen.maxX - frame.width - 24, y: screen.midY - frame.height / 2))
        }
        follow(player)
    }

    private func follow(_ player: Player) {
        let showing = player.state != .idle
        if showing, !isVisible { orderFrontRegardless() } else if !showing, isVisible { orderOut(nil) }
        withObservationTracking { _ = player.state } onChange: { [weak self] in
            Task { @MainActor in self?.follow(player) }
        }
    }

    override var canBecomeKey: Bool { true }

    /// Grows leftward when the content widens, so a message never pushes the panel off the right edge.
    override func setFrame(_ rect: NSRect, display: Bool) {
        var rect = rect
        if frame.width > 0, rect.width != frame.width { rect.origin.x = frame.maxX - rect.width }
        super.setFrame(rect, display: display)
    }
}

struct PlayerView: View {
    let player: Player
    private let speeds: [Float] = [0.75, 1, 1.25, 1.5, 2, 2.5, 3]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30).accessibilityHidden(true)
                Button { player.skip(-1) } label: { small("backward.fill") }
                    .disabled(!reading)
                    .accessibilityLabel("Previous paragraph")
                Button(action: player.playPause) {
                    mainIcon.frame(width: 40, height: 40)
                        .background(Circle().fill(Otter.orange))
                        .background(Circle().fill(Otter.orangeEdge).offset(y: 2.5))
                }
                .accessibilityLabel(player.state == .playing ? "Pause" : "Play")
                Button { player.skip(1) } label: { small("forward.fill") }
                    .disabled(!reading)
                    .accessibilityLabel("Next paragraph")
                Menu {
                    ForEach(speeds, id: \.self) { s in Button(label(s)) { player.speed = s } }
                } label: {
                    Text(label(player.speed)).font(Otter.font(12.5, .heavy)).monospacedDigit().foregroundStyle(Otter.ink)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Speed")
                Button(action: player.stop) { small("xmark") }
                    .accessibilityLabel("Stop")
            }
            .buttonStyle(.plain)
            if player.resumedAt != nil {
                Button("Start over", systemImage: "arrow.counterclockwise", action: player.startOver)
                    .buttonStyle(.plain)
                    .font(Otter.font(11.5, .bold))
                    .foregroundStyle(Otter.teal)
            }
            if case .failed(let message) = player.state {
                failure(message)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Otter.card)
            .shadow(color: Otter.ink.opacity(0.22), radius: 12, y: 6))
        .padding(14)
        .fontDesign(.rounded)
    }

    private func small(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(Otter.teal)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Otter.mint))
    }

    private var reading: Bool { player.state == .playing || player.state == .paused }

    @ViewBuilder private var mainIcon: some View {
        switch player.state {
        case .downloading: ProgressView(value: player.download ?? 0).progressViewStyle(.circular).controlSize(.small).tint(.white)
        case .loading: ProgressView().controlSize(.small).tint(.white)
        case .playing: Image(systemName: "pause.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
        default: Image(systemName: "play.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
        }
    }

    @ViewBuilder private func failure(_ message: String) -> some View {
        VStack(spacing: 6) {
            Text(message).font(Otter.font(11.5, .medium)).foregroundStyle(Otter.ink).multilineTextAlignment(.center)
                .frame(width: 200).fixedSize(horizontal: false, vertical: true)
            if message == GrabError.notTrusted.description {
                Button("Open Accessibility Settings") {
                    openPrivacy("Privacy_Accessibility")
                }
                .font(Otter.font(11.5, .bold))
            } else if message.hasSuffix(ScreenAreaError.turnOn) {
                Button("Open Screen Recording Settings") {
                    openPrivacy("Privacy_ScreenCapture")
                }
                .font(Otter.font(11.5, .bold))
            }
        }
    }

    private func label(_ s: Float) -> String { s.formatted(.number.precision(.fractionLength(0...2))) + "×" }
}
