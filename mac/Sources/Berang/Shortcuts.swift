import AppKit
import Carbon.HIToolbox
import Keys

/// Berang's global shortcuts.
enum ShortcutAction: String, CaseIterable, Identifiable {
    case page, area, faster, slower
    var id: Self { self }

    var title: String {
        switch self {
        case .page: "Read this page"
        case .area: "Read a screen area"
        case .faster: "Read faster"
        case .slower: "Read slower"
        }
    }

    var standard: KeyCombo {
        switch self {
        case .page: .readPage
        case .area: .readArea
        case .faster: .faster
        case .slower: .slower
        }
    }

    /// Whether Berang holds the shortcut only while the player shows, so the rest of the time its keys reach the
    /// app in front.
    var whileReading: Bool { self == .faster || self == .slower }
}

/// The shortcuts, saved and registered, and changing them, as Model/Shortcuts.tla checks:
/// - A change registers the new combination before it lets go of the old one, so a shortcut that works keeps working
///   whether the change succeeds or fails.
/// - Only a registered combination is saved, so the next launch registers the same ones.
/// - A combination another app took while Berang was closed shows as not working, whatever refusal is also shown.
/// - The speed shortcuts are held only while the player shows. One recorded while it doesn't is registered, to learn
///   whether it can be, and let go at once.
/// - While recording, pressing a combination Berang holds records it instead of reading or changing the speed.
/// - macOS lets several apps register one combination and sends its presses to the latest, so registering would
///   take a combination from another app without failing. While recording, Berang watches the keyboard instead: a
///   press seen there that never reaches Berang went to macOS or another app, and is refused.
@MainActor @Observable final class Shortcuts {
    private(set) var combos: [ShortcutAction: KeyCombo]
    private(set) var working: Set<ShortcutAction> = []
    /// Why the last combination offered for a shortcut was refused, or why it doesn't work.
    private(set) var notes: [ShortcutAction: String] = [:]
    private(set) var recording: ShortcutAction?
    @ObservationIgnored private var hotkeys: [ShortcutAction: Hotkey] = [:]
    @ObservationIgnored private let actions: [ShortcutAction: () -> Void]
    /// Watches key presses while recording, to see those that go elsewhere.
    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var tapSource: CFRunLoopSource?
    /// The last combination that reached Berang while recording.
    @ObservationIgnored private var received: (combo: KeyCombo, at: ContinuousClock.Instant)?
    /// Whether the player shows, which holds the speed shortcuts.
    var reading = false {
        didSet {
            guard reading != oldValue else { return }
            for action in ShortcutAction.allCases where action.whileReading {
                if reading { register(action) } else { hotkeys[action] = nil }
            }
        }
    }

    init(actions: [ShortcutAction: () -> Void]) {
        self.actions = actions
        var combos: [ShortcutAction: KeyCombo] = [:]
        for action in ShortcutAction.allCases {
            let saved = UserDefaults.standard.data(forKey: "shortcut.\(action.rawValue)")
                .flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) }
            combos[action] = saved ?? action.standard
        }
        self.combos = combos
        working = Set(ShortcutAction.allCases)
        for action in ShortcutAction.allCases where !action.whileReading { register(action) }
    }

    /// Registers the saved combination, even over another app, as at launch or when reading starts.
    private func register(_ action: ShortcutAction) {
        let combo = combos[action]!
        if let hotkey = Hotkey(combo, pressed: { [weak self] in self?.pressed(action) }) {
            hotkeys[action] = hotkey
            working.insert(action)
        } else {
            hotkeys[action] = nil
            working.remove(action)
            notes[action] = "Another app took \(combo.display). Pick another."
        }
    }

    /// Whether a shortcut doesn't work, which the menu bar icon flags.
    var needsAttention: Bool { working.count < ShortcutAction.allCases.count }

    /// Whether any shortcut differs from its standard default.
    var isCustomized: Bool { ShortcutAction.allCases.contains { combos[$0] != $0.standard } }

    /// Restores each shortcut to its standard default, keeping any working shortcut if a default can't register
    /// (Model/Shortcuts.tla, SafeOrder & Release).
    func resetToDefaults() {
        cancelRecording()
        for action in ShortcutAction.allCases where combos[action] != action.standard {
            let combo = action.standard
            guard let hotkey = Hotkey(combo, pressed: { [weak self] in self?.pressed(action) }) else {
                notes[action] = Refusal.anotherApp.message(combo)
                continue
            }
            hotkeys[action] = action.whileReading && !reading ? nil : hotkey
            combos[action] = combo
            UserDefaults.standard.removeObject(forKey: "shortcut.\(action.rawValue)")
            working.insert(action)
            notes[action] = nil
        }
    }

    func startRecording(_ action: ShortcutAction) {
        recording = action
        if working.contains(action) { notes[action] = nil }
        watchKeyboard()
    }

    func cancelRecording() {
        if let action = recording, working.contains(action) { notes[action] = nil }
        recording = nil
        stopWatching()
    }

    private func finishRecording() {
        recording = nil
        stopWatching()
    }

    /// A press the keyboard watcher saw. If it hasn't reached Berang shortly after, something else took it.
    private func saw(_ combo: KeyCombo) {
        guard recording != nil, NSApp.isActive else { return }
        let seen = ContinuousClock.now
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard let action = recording else { return }
            if let received, received.combo == combo, received.at >= seen - .milliseconds(50) { return }
            let others = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.filter { $0 != action }.map { ($0.title, combos[$0]!) })
            let refused = refusal(for: combo, others: others, system: Hotkey.systemCombos())
            notes[action] = refused.map { $0.message(combo) } ?? "macOS or another app uses \(combo.display)."
        }
    }

    private func watchKeyboard() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, me in
            let shortcuts = Unmanaged<Shortcuts>.fromOpaque(me!).takeUnretainedValue()
            MainActor.assumeIsolated {
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = shortcuts.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                } else if type == .keyDown {
                    shortcuts.saw(Shortcuts.combo(event))
                }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }  // no permission: refusals rest on the other checks
        self.tap = tap
        tapSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopWatching() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
    }

    private func pressed(_ action: ShortcutAction) {
        if recording != nil { offer(combos[action]!) } else { actions[action]?() }
    }

    /// A combination typed, or one of Berang's pressed, while recording.
    func offer(_ combo: KeyCombo) {
        guard let action = recording else { return }
        received = (combo, .now)
        if combo == combos[action], working.contains(action) {
            finishRecording()
            notes[action] = nil
            return
        }
        let others = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.filter { $0 != action }.map { ($0.title, combos[$0]!) })
        if let refused = refusal(for: combo, others: others, system: Hotkey.systemCombos()) {
            notes[action] = refused.message(combo)
            return
        }
        guard let hotkey = Hotkey(combo, pressed: { [weak self] in self?.pressed(action) }) else {
            notes[action] = Refusal.anotherApp.message(combo)
            return
        }
        // The old hot key, now replaced, lets go of its combination. A speed shortcut lets go of the new one too
        // while the player doesn't show.
        hotkeys[action] = action.whileReading && !reading ? nil : hotkey
        combos[action] = combo
        UserDefaults.standard.set(try? JSONEncoder().encode(combo), forKey: "shortcut.\(action.rawValue)")
        working.insert(action)
        notes[action] = nil
        finishRecording()
    }

    /// The combination a key press makes, for recording.
    static func combo(_ event: NSEvent) -> KeyCombo {
        let flags = event.modifierFlags
        var modifiers = 0
        if flags.contains(.command) { modifiers |= cmdKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        return KeyCombo(key: UInt32(event.keyCode), modifiers: UInt32(modifiers))
    }

    nonisolated static func combo(_ event: CGEvent) -> KeyCombo {
        let flags = event.flags
        var modifiers = 0
        if flags.contains(.maskCommand) { modifiers |= cmdKey }
        if flags.contains(.maskAlternate) { modifiers |= optionKey }
        if flags.contains(.maskControl) { modifiers |= controlKey }
        if flags.contains(.maskShift) { modifiers |= shiftKey }
        return KeyCombo(key: UInt32(event.getIntegerValueField(.keyboardEventKeycode)), modifiers: UInt32(modifiers))
    }
}
