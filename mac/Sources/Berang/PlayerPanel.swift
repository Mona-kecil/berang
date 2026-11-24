import AppKit
import SwiftUI
import TextGrab

/// A floating player that never takes focus, so the app being read stays frontmost. It shows while Berang reads,
/// gets a voice ready, or has something to say, and hides when it stops. Scrolling over it changes the speed.
///
/// It rests against the left or right edge of a screen. You drag it anywhere; when you let go, it slides to the nearer
/// edge, or to the edge you flicked it toward, at the height you let go. It stays there across readings and
/// launches, as Model/Place.tla checks:
/// - Only your drag saves the spot. macOS moving the player off a display that went away saves nothing.
/// - Each time it shows, and whenever displays change, it goes to your spot, or to the right edge of the main display
///   while your spot's display is gone.
final class PlayerPanel: NSPanel {
    private let player: Player
    private let tips: Tips
    private let dock = Dock()
    /// Scrolling not yet turned into a speed step.
    private var scrolled: CGFloat = 0
    /// A smaller size waiting for the content to finish closing.
    private var shrink: Task<Void, Never>?
    /// While you press on the player: where the window was, to tell a drag from a click, and the pointer's recent
    /// path, to tell a flick from a drop.
    private var press: (origin: NSPoint, path: [(x: CGFloat, time: TimeInterval)], timer: Timer)?
    /// Closing the controls a moment after the pointer leaves, so passing over the edge doesn't flicker them.
    private var close: Task<Void, Never>?

    init(player: Player, shortcuts: Shortcuts, tips: Tips) {
        self.player = player
        self.tips = tips
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        // The player draws its own shadow; a window shadow would trace the transparent margin around it.
        hasShadow = false
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = PlayerHost(rootView: PlayerView(player: player, shortcuts: shortcuts, tips: tips, dock: dock) {
            [weak self] in self?.fit($0)
        })
        host.pointer = { [weak self] inside in self?.pointer(inside) }
        // Measured first: without sizing options, the view reports no size.
        let size = host.fittingSize
        // The player sizes the window itself, through `fit`, so content that animates away isn't cut off.
        host.sizingOptions = []
        contentView = host
        setContentSize(size)
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

    /// Grows at once, so content opening has room, and shrinks once content closing has faded out.
    private func fit(_ size: CGSize) {
        shrink?.cancel()
        guard isVisible, size.height < frame.height || size.width < frame.width else { return setContentSize(size) }
        shrink = Task { [weak self] in
            try? await Task.sleep(for: PlayerView.motionTime)
            if !Task.isCancelled { self?.setContentSize(size) }
        }
    }

    /// Opens the controls while the pointer is over the player.
    private func pointer(_ inside: Bool) {
        close?.cancel()
        if inside {
            dock.open = true
            tips.learn(.more)
        } else {
            close = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                if !Task.isCancelled { self?.dock.open = false }
            }
        }
    }

    /// Puts the player at your spot, or at the right edge of the main display while your spot's display is gone.
    private func place() {
        if let spot = PlayerSpot.saved, let screen = NSScreen.screens.first(where: { $0.displayID == spot.display }) {
            dock.side = spot.side
            setFrameOrigin(spot.origin(for: frame.size, in: screen.visibleFrame))
        } else if let room = NSScreen.screens.first?.visibleFrame {
            dock.side = .right
            setFrameOrigin(NSPoint(x: Self.x(for: .right, width: frame.width, in: room), y: room.midY - frame.height / 2))
        }
    }

    /// The window's left side for a player resting on `side` of `room`. The margin for the shadow on the edge's side
    /// hangs off the screen, so the player itself touches the edge.
    static func x(for side: Dock.Side, width: CGFloat, in room: NSRect) -> CGFloat {
        side == .left ? room.minX - PlayerView.margin : room.maxX - width + PlayerView.margin
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown: pressed()
        case .leftMouseUp: released()
        default: break
        }
        super.sendEvent(event)
    }

    /// Follows the pointer while the button is down, since macOS moves the window itself and reports nothing on the way.
    private func pressed() {
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.track() }
        }
        // Common modes, so it also runs while macOS moves the window.
        RunLoop.main.add(timer, forMode: .common)
        press = (frame.origin, [], timer)
    }

    private func track() {
        guard var press else { return }
        let now = NSEvent.mouseLocation, time = ProcessInfo.processInfo.systemUptime
        press.path = press.path.filter { time - $0.time < 0.1 } + [(now.x, time)]
        self.press = press
        if !dock.dragging, frame.origin != press.origin { dock.dragging = true }
    }

    /// A press that moved the player ends in a slide to an edge, and saves the spot: only your drag saves it, never a
    /// move made by macOS or Berang.
    private func released() {
        guard let press else { return }
        press.timer.invalidate()
        self.press = nil
        guard dock.dragging || frame.origin != press.origin else { return }
        let samples = press.path
        let speed = samples.count > 1 ? (samples.last!.x - samples.first!.x) / max(samples.last!.time - samples.first!.time, 0.001) : 0
        let center = NSPoint(x: frame.midX, y: frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? screen else { return }
        let room = screen.visibleFrame
        // Where the player is heading, not only where it was let go: a flick picks the edge it was thrown toward.
        let side: Dock.Side = center.x + speed * 0.2 < room.midX ? .left : .right
        let y = min(max(frame.minY, room.minY - PlayerView.margin), room.maxY - frame.height + PlayerView.margin)
        let target = NSRect(x: Self.x(for: side, width: frame.width, in: room), y: y, width: frame.width, height: frame.height)
        dock.side = side
        dock.dragging = false
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            setFrame(target, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
                animator().setFrame(target, display: true)
            }
        }
        PlayerSpot.saved = PlayerSpot(top: target.maxY - PlayerView.margin, side: side, on: screen)
        tips.learn(.move)
    }

    /// Keeps the edge it rests on and its top in place when the content changes size, so the controls stay where
    /// they were and a message never pushes the player off the screen.
    override func setFrame(_ rect: NSRect, display: Bool) {
        var rect = rect
        if frame.width > 0, rect.width != frame.width, dock.side == .right { rect.origin.x = frame.maxX - rect.width }
        if frame.height > 0, rect.height != frame.height {
            rect.origin.y = max(frame.maxY - rect.height, (screen?.visibleFrame.minY ?? -.infinity) - PlayerView.margin)
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

/// The floating player's place on screen and what it shows, shared by its window and its view.
@MainActor @Observable final class Dock {
    enum Side: String, Codable { case left, right }
    var side = Side.right
    /// The pointer is over the player, so it shows every control.
    var open = false
    /// You're dragging the player, so it is round on every side.
    var dragging = false
}

/// Tells the window when the pointer enters and leaves the player, also while another app is active.
private final class PlayerHost: NSHostingView<PlayerView> {
    var pointer: (Bool) -> Void = { _ in }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self && area.userInfo?["player"] != nil { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: ["player": true]))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if event.trackingArea?.userInfo?["player"] != nil { pointer(true) }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea?.userInfo?["player"] != nil { pointer(false) }
    }
}

struct PlayerView: View {
    let player: Player
    let shortcuts: Shortcuts
    let tips: Tips
    let dock: Dock
    /// Called with the player's new size when its content changes.
    let resized: (CGSize) -> Void
    @State private var showsSpeed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Room around the player for its shadow. On the screen's edge, it hangs off the screen.
    static let margin: CGFloat = 14
    /// How long a row takes to open or close, with time for the spring to settle.
    static let motionTime = Duration.milliseconds(250)
    /// Controls and cards open and close with the player growing and their content fading. With Reduce Motion, they
    /// just appear.
    private var motion: Animation? { reduceMotion ? nil : .snappy(duration: 0.2) }
    private var expanded: Bool { dock.open || showsSpeed }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if dock.side == .right { cards; bar } else { bar; cards }
        }
        // Start over, tips, and the controls come and go on their own. Changes that shortcuts make, such as the
        // speed, stay instant.
        .animation(motion, value: player.resumedAt != nil)
        .animation(motion, value: tips.showing)
        .animation(motion, value: dock.open)
        .animation(motion, value: dock.dragging)
        .padding(Self.margin)
        .fixedSize()
        .onGeometryChange(for: CGSize.self, of: \.size, action: resized)
        // The window stays larger while something closes, and is briefly smaller while something opens. The player
        // keeps to the window's top and its edge either way: with no minimum, the frame would take the player's size,
        // and the window would center it, shifting it until the window caught up.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity,
               alignment: dock.side == .right ? .topTrailing : .topLeading)
        .fontDesign(.rounded)
        // The panel never takes focus from the app being read, so its controls show no focus ring.
        .focusEffectDisabled()
        .onChange(of: player.state == .idle) { _, idle in if idle { showsSpeed = false } }
        .onChange(of: dock.dragging) { _, dragging in if dragging { showsSpeed = false } }
        .task(id: player.state) {
            // Soft transient notices auto-dismiss instead of lingering at the edge of the screen.
            guard case .failed(let message) = player.state,
                  message == ScreenAreaError.noText.description else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled, case .failed(let current) = player.state, current == message {
                player.stop()
            }
        }
    }

    /// Play and the speed, and while the pointer is over it, the rest.
    private var bar: some View {
        VStack(spacing: 2) {
            Capsule().fill(Otter.hair).frame(width: 16, height: 4).padding(.vertical, 3)
            Button(action: player.playPause) {
                mainIcon.frame(width: 34, height: 34).background(Circle().fill(Otter.orange))
            }
            .accessibilityLabel(player.state == .playing ? "Pause" : "Play")
            Button { withAnimation(motion) { showsSpeed.toggle() } } label: {
                Text(speedLabel(player.speed)).font(Otter.font(12, .semibold)).monospacedDigit().foregroundStyle(Otter.ink)
                    .frame(width: 40, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(showsSpeed ? Otter.hair : .clear))
            }
            .accessibilityLabel("Speed, \(speedLabel(player.speed))")
            .accessibilityAddTraits(showsSpeed ? .isSelected : [])
            if expanded {
                VStack(spacing: 2) {
                    icon("backward.fill", "Previous paragraph") { player.skip(-1) }.disabled(!reading)
                    icon("forward.fill", "Next paragraph") { player.skip(1) }.disabled(!reading)
                    icon("xmark", "Stop", action: player.stop)
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 46)
        .buttonStyle(PlainButtonStyle(radius: 8))
        .floating(corners)
        // The controls that show only under the pointer stay reachable without it.
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Previous paragraph") { player.skip(-1) }
        .accessibilityAction(named: "Next paragraph") { player.skip(1) }
        .accessibilityAction(named: "Start over", player.startOver)
        .accessibilityAction(named: "Stop", player.stop)
    }

    /// Round toward the screen, square against its edge, and round all over while you drag it.
    private var corners: RectangleCornerRadii {
        let r: CGFloat = 14
        if dock.dragging { return RectangleCornerRadii(topLeading: r, bottomLeading: r, bottomTrailing: r, topTrailing: r) }
        return dock.side == .right
            ? RectangleCornerRadii(topLeading: r, bottomLeading: r, bottomTrailing: 0, topTrailing: 0)
            : RectangleCornerRadii(topLeading: 0, bottomLeading: 0, bottomTrailing: r, topTrailing: r)
    }

    /// The speed panel, hover context for files, Start over, OCR status, a problem, and tips, as cards beside the bar.
    @ViewBuilder private var cards: some View {
        let failure: String? = if case .failed(let message) = player.state { message } else { nil }
        let fileContext: Player.ReadingInfo? = if dock.open, reading, let info = player.reading, info.isFile { info } else { nil }
        let recognizing = player.state == .recognizing
        if showsSpeed || fileContext != nil || recognizing || player.resumedAt != nil || failure != nil || tips.showing != nil {
            VStack(alignment: dock.side == .right ? .trailing : .leading, spacing: 8) {
                if showsSpeed {
                    SpeedControls(player: player, shortcuts: shortcuts).padding(12).floating(14).transition(.opacity)
                }
                if let fileContext {
                    contextCard(fileContext).padding(.horizontal, 12).padding(.vertical, 9).floating(14).transition(.opacity)
                }
                if recognizing {
                    Text("Reading screen…")
                        .font(Otter.font(12, .semibold)).foregroundStyle(Otter.ink)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .floating(14)
                }
                if player.resumedAt != nil {
                    Button("Start over", systemImage: "arrow.counterclockwise", action: player.startOver)
                        .buttonStyle(PlainButtonStyle(radius: 6))
                        .font(Otter.font(12, .semibold))
                        .foregroundStyle(Otter.teal)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .floating(14)
                        .transition(.opacity)
                }
                if let failure { self.failure(failure).padding(12).floating(14) }
                if let tip = tips.showing { tipRow(tip).padding(.leading, 12).padding(.vertical, 6).floating(14).transition(.opacity) }
            }
        }
    }

    /// Quiet wayfinding card on hover for files (where no document is open on screen).
    private func contextCard(_ info: Player.ReadingInfo) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(info.title)
                    .font(Otter.font(12, .bold)).foregroundStyle(Otter.ink)
                    .lineLimit(1)
                Text("\(info.percent)%")
                    .font(Otter.font(10.5, .semibold)).monospacedDigit().foregroundStyle(Otter.teal)
                    .lineLimit(1)
            }
            .frame(maxWidth: 158, alignment: .leading)
            if player.resumedAt == nil {
                Button(action: player.startOver) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Otter.teal)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(PlainButtonStyle(radius: 7))
                .help("Start over")
                .accessibilityLabel("Start over")
            }
        }
    }

    private func icon(_ symbol: String, _ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Otter.ink)
                .frame(width: 30, height: 28)
        }
        .accessibilityLabel(name)
    }

    private func tipRow(_ tip: Tip) -> some View {
        HStack(alignment: .center, spacing: 2) {
            Text(tip.text(shortcuts)).font(Otter.font(11.5, .medium)).foregroundStyle(Otter.soft)
                .frame(width: 184, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button { tips.learn(tip) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(Otter.soft)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(PlainButtonStyle(radius: 6))
            .accessibilityLabel("Dismiss tip")
        }
    }

    private var reading: Bool { player.state == .playing || player.state == .paused }

    @ViewBuilder private var mainIcon: some View {
        switch player.state {
        case .downloading: ProgressView(value: player.download ?? 0).progressViewStyle(.circular).controlSize(.small).tint(.white)
        case .loading, .recognizing: ProgressView().controlSize(.small).tint(.white)
        case .playing: Image(systemName: "pause.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
        // Nudged right: a triangle centered by its box looks left of center.
        default: Image(systemName: "play.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white).offset(x: 1)
        }
    }

    @ViewBuilder private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Text(message).font(Otter.font(11.5, .medium)).foregroundStyle(Otter.ink)
                    .frame(width: 192, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                Button(action: player.stop) {
                    Image(systemName: "xmark").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Otter.soft)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(PlainButtonStyle(radius: 6))
                .accessibilityLabel("Dismiss")
            }
            if message == GrabError.notTrusted.description {
                Button("Open Accessibility Settings") {
                    openPrivacy("Privacy_Accessibility")
                }
                .buttonStyle(SoftButtonStyle())
            } else if message.hasSuffix(ScreenAreaError.turnOn) {
                Button("Open Screen Recording Settings") {
                    openPrivacy("Privacy_ScreenCapture")
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
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

/// Where you left the player: a display, the edge it rests on, and its top as a fraction of the display's room from
/// the top. The player's size changes as it shows controls and messages, so the spot leaves it out. The fraction
/// keeps the player on the display when its resolution changes; naming the display keeps it there when displays are
/// rearranged. Spots saved before the player rested on an edge don't read, and the player starts at the right edge.
struct PlayerSpot: Codable {
    let display: String
    let side: Dock.Side
    let y: Double

    init(top: CGFloat, side: Dock.Side, on screen: NSScreen) {
        let room = screen.visibleFrame
        display = screen.displayID
        self.side = side
        y = Double((room.maxY - top) / room.height)
    }

    /// The window origin that puts a player of window `size` at the spot, kept between the menu bar and the Dock.
    func origin(for size: NSSize, in room: NSRect) -> NSPoint {
        let top = room.maxY - y * room.height + PlayerView.margin
        let m = PlayerView.margin
        return NSPoint(x: PlayerPanel.x(for: side, width: size.width, in: room),
                       y: min(max(top, room.minY - m + size.height), room.maxY + m) - size.height)
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
