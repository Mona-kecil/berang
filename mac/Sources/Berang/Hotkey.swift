import Carbon.HIToolbox

/// A shortcut that works in every app. Carbon hot keys need no permission, and the key never reaches the front app.
@MainActor final class Hotkey {
    private let action: () -> Void
    private var handler: EventHandlerRef?
    private var ref: EventHotKeyRef?
    var isRegistered: Bool { ref != nil }

    init(key: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, hotkey in
            MainActor.assumeIsolated { Unmanaged<Hotkey>.fromOpaque(hotkey!).takeUnretainedValue().action() }
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let status = RegisterEventHotKey(UInt32(key), UInt32(modifiers), EventHotKeyID(signature: 0x6272_6E67, id: 1),
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr { ref = nil }
    }
}
