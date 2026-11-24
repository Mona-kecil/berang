import AppKit
import SwiftUI
import TextGrab

/// A floating player that never takes focus, so the app being read stays frontmost. It shows while Berang reads,
/// gets a voice ready, or has something to say, and hides when it stops. Scrolling over it changes the speed.
///
/// It sits where you last dragged it, across readings and launches, as Model/Place.tla checks:
/// - Only your drag saves the spot. macOS moving the player off a display that went away saves nothing.
/// - Each time it shows, and whenever displays change, it goes to your spot, or to the right edge of the main display
///   while your spot's display is gone.
final class PlayerPanel: NSPanel {
    private let player: Player
    private let tips: Tips
    /// Scrolling not yet turned into a speed step.
    private var scrolled: CGFloat = 0
    /// Where the player was when you pressed on it, to tell a drag from a click.
    private var pressedAt: NSPoint?

    init(player: Player, shortcuts: Shortcuts, tips: Tips) {
        self.player = player
        self.tips = tips
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        // The pill draws its own soft shadow; a window shadow would trace the transparent margin around it.
        hasShadow = false
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: PlayerView(player: player, shortcuts: shortcuts, tips: tips))
        setContentSize(contentView!.fittingSize)
        place()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.isVisible == true { self?.place() } }
        }
        follow(player)
    }

    private func follow(_ player: Player) {
        let showing = player.state != .idle
        if showing, !isVisible {
            place()
            orderFrontRegardless()
        } else if !showing, isVisible {
            orderOut(nil)
            tips.readingStopped()
        }
        withObservationTracking { _ = player.state } onChange: { [weak self] in
            Task { @MainActor in self?.follow(player) }
        }
    }

    override var canBecomeKey: Bool { true }

    /// Puts the player at your spot, or at the right edge of the main display while your spot's display is gone.
    private func place() {
        if let spot = PlayerSpot.saved, let screen = NSScreen.screens.first(where: { $0.displayID == spot.display }) {
            setFrameOrigin(spot.origin(for: frame.size, in: screen.visibleFrame))
        } else if let screen = NSScreen.screens.first?.visibleFrame {
            setFrameOrigin(NSPoint(x: screen.maxX - frame.width - 24, y: screen.midY - frame.height / 2))
        }
    }

    /// Saves the spot when a press on the player ends somewhere else: a drag, never a move made by macOS or Berang.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown: pressedAt = frame.origin
        case .leftMouseUp:
            if let pressedAt, pressedAt != frame.origin, let screen {
                PlayerSpot.saved = PlayerSpot(frame, in: screen)
                tips.learn(.move)
            }
            pressedAt = nil
        default: break
        }
        super.sendEvent(event)
    }

    /// Grows leftward and down when the content grows, so a message never pushes the panel off the right edge and
    /// the controls stay where they were.
    override func setFrame(_ rect: NSRect, display: Bool) {
        var rect = rect
        if frame.width > 0, rect.width != frame.width { rect.origin.x = frame.maxX - rect.width }
        if frame.height > 0, rect.height != frame.height {
            rect.origin.y = max(frame.maxY - rect.height, screen?.visibleFrame.minY ?? -.infinity)
        }
        super.setFrame(rect, display: display)
    }

    /// One step of 0.1× per notch of a mouse wheel, or per 24 points of trackpad scrolling. Scrolling up is faster.
    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        scrolled += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 24 : event.scrollingDeltaY
        while abs(scrolled) >= 1 {
            let up: CGFloat = scrolled > 0 ? 1 : -1
            player.nudge(Float(up) / 10)
            tips.learn(.speed)
            scrolled -= up
        }
        if event.phase == .ended || event.phase == .cancelled { scrolled = 0 }
    }
}

struct PlayerView: View {
    let player: Player
    let shortcuts: Shortcuts
    let tips: Tips
    @State private var showsSpeed = false

    var body: some View {
        VStack(spacing: 8) {
            // 160 points of buttons spread over the width.
            HStack(spacing: 13.5) {
                Button { player.skip(-1) } label: { small("backward.fill") }
                    .disabled(!reading)
                    .accessibilityLabel("Previous paragraph")
                Button(action: player.playPause) {
                    mainIcon.frame(width: 40, height: 40)
                        .raised(in: Circle(), face: Otter.orange, edge: Otter.orangeEdge, depth: 2.5)
                }
                .buttonStyle(KeyButtonStyle(radius: 20))
                .accessibilityLabel(player.state == .playing ? "Pause" : "Play")
                Button { player.skip(1) } label: { small("forward.fill") }
                    .disabled(!reading)
                    .accessibilityLabel("Next paragraph")
                Button { showsSpeed.toggle() } label: {
                    Text(speedLabel(player.speed)).font(Otter.font(12.5, .heavy)).monospacedDigit().foregroundStyle(Otter.ink)
                        .frame(minWidth: 36, minHeight: 28)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(showsSpeed ? Otter.mint : .clear))
                }
                .accessibilityLabel("Speed, \(speedLabel(player.speed))")
                .accessibilityAddTraits(showsSpeed ? .isSelected : [])
                Button(action: player.stop) { small("xmark") }
                    .accessibilityLabel("Stop")
            }
            .buttonStyle(PlainButtonStyle(radius: 10))
            if showsSpeed { SpeedControls(player: player, shortcuts: shortcuts).padding(.top, 4) }
            if player.resumedAt != nil {
                Button("Start over", systemImage: "arrow.counterclockwise", action: player.startOver)
                    .buttonStyle(PlainButtonStyle(radius: 6))
                    .font(Otter.font(11.5, .bold))
                    .foregroundStyle(Otter.teal)
            }
            if case .failed(let message) = player.state {
                failure(message)
            }
            if let tip = tips.showing { tipRow(tip) }
        }
        // One width in every state, so the panel never grows sideways and the buttons stay under the pointer.
        .frame(width: 214)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Otter.card)
            .shadow(color: Otter.shadow, radius: 12, y: 6))
        .padding(14)
        .fontDesign(.rounded)
        // The panel never takes focus from the app being read, so its controls show no focus ring.
        .focusEffectDisabled()
        .onChange(of: player.state == .idle) { _, idle in if idle { showsSpeed = false } }
    }

    private func tipRow(_ tip: Tip) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(tip.text(shortcuts)).font(Otter.font(11.5, .medium)).foregroundStyle(Otter.soft)
                .frame(width: 184, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button { tips.learn(tip) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(Otter.soft)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(PlainButtonStyle(radius: 5))
            .accessibilityLabel("Dismiss tip")
        }
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
                .frame(width: 214).fixedSize(horizontal: false, vertical: true)
            if message == GrabError.notTrusted.description {
                Button("Open Accessibility Settings") {
                    openPrivacy("Privacy_Accessibility")
                }
            } else if message.hasSuffix(ScreenAreaError.turnOn) {
                Button("Open Screen Recording Settings") {
                    openPrivacy("Privacy_ScreenCapture")
                }
            }
        }
        .buttonStyle(SoftButtonStyle())
    }

}

/// The speed, as "1×" or "2.3×".
func speedLabel(_ s: Float) -> String { s.formatted(.number.precision(.fractionLength(0...1))) + "×" }

/// Slower and faster by 0.1×, the speed and the words a minute it makes, a slider, and the usual speeds. Clicking the
/// speed goes back to 1×.
struct SpeedControls: View {
    let player: Player
    let shortcuts: Shortcuts
    private let presets: [Float] = [1, 1.5, 2, 2.5, 3]

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                step("minus", by: -0.1, name: "Slower", .slower)
                Spacer()
                Button { player.speed = 1 } label: {
                    VStack(spacing: 1) {
                        Text(speedLabel(player.speed)).font(Otter.font(22, .heavy)).monospacedDigit().foregroundStyle(Otter.ink)
                        // Kept in place before the voice's pace is known, so the controls don't shift.
                        Text(player.pace.map { "≈ \(Int(($0 * Double(player.speed)).rounded())) words/min" } ?? " ")
                            .font(Otter.font(11, .bold)).monospacedDigit().foregroundStyle(Otter.soft)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 2)
                }
                .help("Back to 1×")
                .accessibilityLabel("Speed \(speedLabel(player.speed)). Back to 1×")
                Spacer()
                step("plus", by: 0.1, name: "Faster", .faster)
            }
            Slider(value: Binding(get: { player.speed }, set: { player.speed = Player.step($0) }), in: Player.speeds)
                .tint(Otter.teal)
                .controlSize(.small)
                .accessibilityLabel("Speed")
            HStack(spacing: 5) {
                ForEach(presets, id: \.self) { s in
                    let on = player.speed == s
                    Button { player.speed = s } label: {
                        Text(speedLabel(s)).font(Otter.font(11.5, .heavy)).foregroundStyle(on ? .white : Otter.teal)
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Otter.teal : Otter.mint))
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle(radius: 8))
        .frame(width: 214)
    }

    private func step(_ symbol: String, by delta: Float, name: String, _ action: ShortcutAction) -> some View {
        Button { player.nudge(delta) } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .heavy)).foregroundStyle(Otter.teal)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Otter.mint))
        }
        .help("\(name)  \(shortcuts.combos[action]!.display)")
        .accessibilityLabel(name)
    }
}

/// Where you dragged the player: a display, and the player's top left corner on it as fractions of the display's
/// room, from the left and from the top. The player's size changes as it shows controls and messages, so the spot
/// leaves it out. Fractions keep the player on the display when its resolution changes; naming the display keeps it
/// there when displays are rearranged.
struct PlayerSpot: Codable {
    let display: String
    let x: Double
    let y: Double

    init(_ frame: NSRect, in screen: NSScreen) {
        let room = screen.visibleFrame
        display = screen.displayID
        x = Double((frame.minX - room.minX) / room.width)
        y = Double((room.maxY - frame.maxY) / room.height)
    }

    /// The origin that puts a player of `size` at the spot, kept wholly inside `room`.
    func origin(for size: NSSize, in room: NSRect) -> NSPoint {
        let left = room.minX + x * room.width, top = room.maxY - y * room.height
        return NSPoint(x: min(max(left, room.minX), room.maxX - size.width),
                       y: min(max(top, room.minY + size.height), room.maxY) - size.height)
    }

    static var saved: PlayerSpot? {
        get { UserDefaults.standard.data(forKey: "playerSpot").flatMap { try? JSONDecoder().decode(Self.self, from: $0) } }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "playerSpot") }
    }
}

extension NSScreen {
    /// The display's lasting identity, the same across launches and rearranging.
    var displayID: String {
        let number = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return "\(number)" }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
