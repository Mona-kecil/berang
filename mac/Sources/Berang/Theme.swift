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
    static let orange = Color(hex: 0xFF8A3D)
    static let orangeEdge = Color(hex: 0xD9661F)
    static let alert = dynamic(light: 0xB42318, dark: 0xFF8A80)

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

/// A button that draws only its label, dimmed while pressed, with the rounded focus ring.
struct PlainButtonStyle: ButtonStyle {
    var radius: CGFloat = 10
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1).contentShape(Rectangle()).focusRing(radius)
    }
}

/// A white card resting on a solid edge.
struct Card: ViewModifier {
    var padding: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Otter.card)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Otter.edge).offset(y: 3))
            )
    }
}

extension View {
    func card(padding: CGFloat = 12) -> some View { modifier(Card(padding: padding)) }
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
        let pressed = configuration.isPressed
        configuration.label
            .font(Otter.font(compact ? 12 : 13.5, .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 11 : 16)
            .padding(.vertical, compact ? 5 : 9)
            .background(
                RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous).fill(Otter.orange)
                    .background(RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                        .fill(Otter.orangeEdge).offset(y: pressed ? 1 : 3))
            )
            .offset(y: pressed ? 2 : 0)
            .contentShape(Rectangle())
            .focusRing(compact ? 10 : 14)
    }
}

/// A quiet white button on its edge, for secondary actions.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(Otter.font(12.5, .bold))
            .foregroundStyle(Otter.teal)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Otter.card)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Otter.edge).offset(y: pressed ? 1 : 2))
            )
            .offset(y: pressed ? 1 : 0)
            .contentShape(Rectangle())
            .focusRing(10)
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
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Otter.card)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(tint ?? Otter.edge, lineWidth: tint == nil ? 1.5 : 2.5))
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Otter.edge).offset(y: 2))
            )
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
