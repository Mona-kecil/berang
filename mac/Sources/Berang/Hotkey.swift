import Carbon.HIToolbox
import Keys

/// A key combination that works in every app. Carbon hot keys need no permission, and the key never reaches the front
/// app. The combination is held from creation until this is released.
@MainActor final class Hotkey {
    let combo: KeyCombo
    private let pressed: () -> Void
    private nonisolated let id: UInt32
    private nonisolated(unsafe) var handler: EventHandlerRef?
    private nonisolated(unsafe) var ref: EventHotKeyRef?
    private static var nextID: UInt32 = 1

    /// Registers `combo`, or returns nil if the system refuses it, as it does when another app holds it.
    init?(_ combo: KeyCombo, pressed: @escaping () -> Void) {
        self.combo = combo
        self.pressed = pressed
        id = Self.nextID
        Self.nextID += 1
        let status = RegisterEventHotKey(combo.key, combo.modifiers, EventHotKeyID(signature: 0x6272_6E67, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, ref != nil else { return nil }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // Every handler sees every press, so each passes on presses of other hot keys.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, hotkey in
            var pressedID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressedID)
            let target = Unmanaged<Hotkey>.fromOpaque(hotkey!).takeUnretainedValue()
            guard pressedID.id == target.id else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { target.pressed() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// The combinations macOS keeps for itself and has turned on, such as ⌘ Space for Spotlight.
    static func systemCombos() -> Set<KeyCombo> {
        var list: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&list) == noErr, let keys = list?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return Set(keys.compactMap { key in
            guard (key[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let code = key[kHISymbolicHotKeyCode as String] as? Int,
                  let modifiers = key[kHISymbolicHotKeyModifiers as String] as? Int else { return nil }
            return KeyCombo(key: UInt32(code), modifiers: UInt32(modifiers))
        })
    }
}
