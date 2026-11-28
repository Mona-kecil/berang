import Foundation
import Observation

/// What the player teaches, one line at a time, while you read.
enum Tip: String, CaseIterable {
    case jump, area, speed, move, more

    @MainActor func text(_ shortcuts: Shortcuts) -> String {
        // A shortcut never breaks across lines.
        let keys = { (action: ShortcutAction) in shortcuts.combos[action]!.display.replacingOccurrences(of: " ", with: "\u{00A0}") }
        return switch self {
        case .jump: "To read from somewhere else, select it and press \(keys(.page))"
        case .area: "To read part of the screen, press \(keys(.area)) and drag over it"
        case .speed: "Scroll over the player to change the speed, or press \(keys(.faster)) to go faster and \(keys(.slower)) to go slower"
        case .move: "Drag the player to either side of the screen. It stays there."
        case .more: "Point at the player to skip or stop"
        }
    }
}

/// The tips, kept across launches. As reading starts, the player shows the first tip you haven't learned that fits
/// the reading, for a few seconds. A tip is learned when you use what it teaches or dismiss it, and retires after a few showings anyway.
@MainActor @Observable final class Tips {
    /// The tip the player shows now.
    private(set) var showing: Tip?
    @ObservationIgnored private var learned = Set(UserDefaults.standard.stringArray(forKey: "tips.learned") ?? [])
    @ObservationIgnored private var shown = UserDefaults.standard.dictionary(forKey: "tips.shown") as? [String: Int] ?? [:]
    @ObservationIgnored private var hide: Task<Void, Never>?
    private static let showings = 3

    /// `app`: whether the reading is of an app's page, where text can be selected to jump to.
    func readingStarted(app: Bool) {
        guard let tip = Tip.allCases.first(where: {
            ($0 != .jump || app) && !learned.contains($0.rawValue) && shown[$0.rawValue, default: 0] < Self.showings
        }) else { return }
        shown[tip.rawValue, default: 0] += 1
        UserDefaults.standard.set(shown, forKey: "tips.shown")
        showing = tip
        hide?.cancel()
        hide = Task {
            try? await Task.sleep(for: .seconds(12))
            if !Task.isCancelled { showing = nil }
        }
    }

    func readingStopped() { showing = nil }

    /// You used what `tip` teaches, or dismissed it.
    func learn(_ tip: Tip) {
        if showing == tip { showing = nil }
        guard learned.insert(tip.rawValue).inserted else { return }
        UserDefaults.standard.set(Array(learned), forKey: "tips.learned")
    }
}
