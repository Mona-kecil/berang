import AppKit
import SwiftUI

/// Berang's look: river teal and otter orange on mint, rounded type, and cards that sit on a solid edge.
enum Otter {
    static let mint = dynamic(light: 0xDFF3EF, dark: 0x0F2B2A)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x173B3A)
    static let edge = dynamic(light: 0xB7DCD6, dark: 0x0A1F1E)
    static let ink = dynamic(light: 0x123B3A, dark: 0xE4F3F0)
    static let soft = dynamic(light: 0x4D7C79, dark: 0x9CC4BF)
    static let teal = dynamic(light: 0x0F7D7A, dark: 0x3FB8B2)
    /// Dark enough for white text to stay readable on it.
    static let orange = Color(hex: 0xE0661F)
    static let orangeEdge = Color(hex: 0xA74B16)
    static let alert = dynamic(light: 0xB42318, dark: 0xFF8A80)
    /// The floating player's shadow. Ink would turn it into a pale glow in Dark Mode.
    static let shadow = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .black.withAlphaComponent(0.4) : NSColor(hex: 0x123B3A).withAlphaComponent(0.18)
    })

    static let hair = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .white.withAlphaComponent(0.12) : NSColor(hex: 0x123B3A).withAlphaComponent(0.12)
    })

    /// The app's rounded type at `size`.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }
}

extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Gives the system's keyboard focus ring the control's rounded shape, instead of a plain rectangle.
extension View {
    func focusRing(_ radius: CGFloat) -> some View {
        contentShape(.focusEffect, RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct PlainButtonStyle: ButtonStyle {
    var radius: CGFloat = 10
    func makeBody(configuration: Configuration) -> some View {
        PlainButtonBody(configuration: configuration, radius: radius)
    }
}

private struct PlainButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
            .focusRing(radius)
            .dimmedWhenDisabled()
    }
}

struct KeyButtonStyle: ButtonStyle {
    var radius: CGFloat = 10
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.environment(\.keyPressed, configuration.isPressed).contentShape(Rectangle()).focusRing(radius)
            .dimmedWhenDisabled()
    }
}

extension EnvironmentValues {
    @Entry var keyPressed = false
}

extension View {
    func raised(_ radius: CGFloat, face: Color = Otter.card, edge: Color = Otter.edge, depth: CGFloat = 2,
                stroke: Color? = nil, lineWidth: CGFloat = 0) -> some View {
        raised(in: RoundedRectangle(cornerRadius: radius, style: .continuous), face: face, edge: edge, depth: depth,
               stroke: stroke, lineWidth: lineWidth)
    }

    func raised(in shape: some InsettableShape, face: Color = Otter.card, edge: Color = Otter.edge, depth: CGFloat = 2,
                stroke: Color? = nil, lineWidth: CGFloat = 0) -> some View {
        modifier(Raised(shape: shape, face: face, edge: edge, depth: depth, stroke: stroke, lineWidth: lineWidth))
    }

    func dimmedWhenDisabled() -> some View { modifier(DimmedWhenDisabled()) }

    func card(padding: CGFloat = 12) -> some View { self.padding(padding).raised(16, depth: 3) }
}

private struct Raised<S: InsettableShape>: ViewModifier {
    let shape: S
    let face: Color
    let edge: Color
    let depth: CGFloat
    let stroke: Color?
    let lineWidth: CGFloat
    @Environment(\.keyPressed) private var keyPressed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(
                shape.fill(face)
                    .overlay { if let stroke { shape.strokeBorder(stroke, lineWidth: lineWidth) } }
                    .background(shape.fill(edge).offset(y: keyPressed ? 1 : depth))
            )
            .offset(y: keyPressed ? depth - 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: keyPressed)
    }
}

private struct DimmedWhenDisabled: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    // Flattened first, so a raised face doesn't show its edge through it.
    func body(content: Content) -> some View { content.compositingGroup().opacity(enabled ? 1 : 0.4) }
}

extension View {
    func floating(_ radii: RectangleCornerRadii) -> some View {
        let shape = UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
        return background {
            ZStack {
                shape.fill(.black)
                    .shadow(color: Otter.shadow, radius: 6, y: 3)
                    // Only the shadow outside the shape shows: under the glass it would cloud it.
                    .mask { outside(shape) }
                Glass(radii: radii)
            }
        }
        .overlay { shape.strokeBorder(Otter.hair, lineWidth: 0.5) }
    }

    func floating(_ radius: CGFloat) -> some View {
        floating(RectangleCornerRadii(topLeading: radius, bottomLeading: radius, bottomTrailing: radius, topTrailing: radius))
    }
}

private func outside(_ shape: some Shape) -> some View {
    Rectangle().padding(-24).overlay { shape.blendMode(.destinationOut) }.compositingGroup()
}

private struct Glass: NSViewRepresentable {
    let radii: RectangleCornerRadii

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        // Otherwise the glass turns flat whenever Berang isn't the active app, which is nearly always.
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        // A small image of the shape whose corners stay put while its middle stretches to the view's size.
        let r = radii
        let insets = NSEdgeInsets(top: max(r.topLeading, r.topTrailing), left: max(r.topLeading, r.bottomLeading),
                                  bottom: max(r.bottomLeading, r.bottomTrailing), right: max(r.topTrailing, r.bottomTrailing))
        let size = NSSize(width: insets.left + insets.right + 1, height: insets.top + insets.bottom + 1)
        let mask = NSImage(size: size, flipped: true) { rect in
            NSColor.black.setFill()
            NSBezierPath(cgPath: UnevenRoundedRectangle(cornerRadii: r, style: .continuous).path(in: rect).cgPath).fill()
            return true
        }
        mask.capInsets = insets
        mask.resizingMode = .stretch
        view.maskImage = mask
    }
}

/// A small uppercase heading over a group of cards.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(Otter.font(10.5, .heavy)).tracking(0.7).foregroundStyle(Otter.soft)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The chunky orange button for the one main action on a screen. It sinks onto its edge when pressed.
struct ChunkyButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Otter.font(compact ? 12 : 13.5, .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 11 : 16)
            .padding(.vertical, compact ? 5 : 9)
            .raised(compact ? 10 : 14, face: Otter.orange, edge: Otter.orangeEdge, depth: 3)
            .environment(\.keyPressed, configuration.isPressed)
            .contentShape(Rectangle())
            .focusRing(compact ? 10 : 14)
            .dimmedWhenDisabled()
    }
}

/// A quiet white button on its edge, for secondary actions.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Otter.font(12.5, .bold))
            .foregroundStyle(Otter.teal)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .raised(10)
            .environment(\.keyPressed, configuration.isPressed)
            .contentShape(Rectangle())
            .focusRing(10)
            .dimmedWhenDisabled()
    }
}

/// A key combination shown as a key cap, such as "⌥ ⎋".
struct KeyCap: View {
    let text: String
    var tint: Color? = nil
    var body: some View {
        Text(text)
            .font(Otter.font(13, .heavy))
            .foregroundStyle(tint ?? Otter.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(minWidth: 64)
            .raised(10, stroke: tint ?? Otter.edge, lineWidth: tint == nil ? 1.5 : 2.5)
    }
}

/// One of the mascot's poses, from the app's Brand folder.
struct OtterImage: View {
    enum Pose: String { case floating, peeking, asleep }
    let pose: Pose
    var size: CGFloat = 140
    var body: some View {
        if let url = Bundle.main.resourceURL?.appending(path: "Brand/otter-\(pose.rawValue).png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}
