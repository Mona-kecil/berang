import Carbon.HIToolbox

/// A shortcut that works in every app. Carbon hot keys need no permission, and the key never reaches the front app.
@MainActor final class Hotkey {
    private let action: () -> Void
    private nonisolated let id: UInt32
    private var handler: EventHandlerRef?
    private var ref: EventHotKeyRef?
    var isRegistered: Bool { ref != nil }

    /// `id` tells this shortcut's presses from another's; every handler sees every press.
    init(key: Int, modifiers: Int, id: UInt32, action: @escaping () -> Void) {
        self.action = action
        self.id = id
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, hotkey in
            var pressedID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressedID)
            let target = Unmanaged<Hotkey>.fromOpaque(hotkey!).takeUnretainedValue()
            guard pressedID.id == target.id else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { target.action() }
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let status = RegisterEventHotKey(UInt32(key), UInt32(modifiers), EventHotKeyID(signature: 0x6272_6E67, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr { ref = nil }
    }
}
