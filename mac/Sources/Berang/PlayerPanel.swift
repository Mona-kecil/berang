import AppKit
import SwiftUI
import TextGrab

/// A floating player that never takes focus, so the app being read stays frontmost.
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
            HStack(spacing: 14) {
                Button { player.skip(-1) } label: { Image(systemName: "backward.fill") }
                    .disabled(!reading)
                    .accessibilityLabel("Previous paragraph")
                Button(action: player.playPause) { mainIcon.frame(width: 36, height: 36) }
                    .accessibilityLabel(player.state == .playing ? "Pause" : "Play")
                Button { player.skip(1) } label: { Image(systemName: "forward.fill") }
                    .disabled(!reading)
                    .accessibilityLabel("Next paragraph")
                Menu {
                    ForEach(speeds, id: \.self) { s in Button(label(s)) { player.speed = s } }
                } label: {
                    Text(label(player.speed)).monospacedDigit()
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Speed")
                Button(action: player.stop) { Image(systemName: "xmark") }
                    .disabled(!reading)
                    .accessibilityLabel("Stop")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 15, weight: .semibold))
            if case .failed(let message) = player.state {
                failure(message)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var reading: Bool { player.state == .playing || player.state == .paused }

    @ViewBuilder private var mainIcon: some View {
        switch player.state {
        case .downloading, .loading: ProgressView().controlSize(.small)
        case .playing: Image(systemName: "pause.fill").font(.system(size: 22))
        default: Image(systemName: "play.fill").font(.system(size: 22))
        }
    }

    @ViewBuilder private func failure(_ message: String) -> some View {
        VStack(spacing: 6) {
            Text(message).font(.caption).multilineTextAlignment(.center)
                .frame(width: 200).fixedSize(horizontal: false, vertical: true)
            if message == GrabError.notTrusted.description {
                Button("Open Accessibility Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .font(.caption)
            }
        }
    }

    private func label(_ s: Float) -> String { s.formatted(.number.precision(.fractionLength(0...2))) + "×" }
}
