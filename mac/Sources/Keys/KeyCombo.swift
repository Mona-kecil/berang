import Carbon.HIToolbox

/// A key and its modifiers, in Carbon's terms, as global shortcuts are registered.
public struct KeyCombo: Codable, Hashable, Sendable {
    /// A virtual key code, such as kVK_Escape.
    public var key: UInt32
    /// Carbon modifier bits: cmdKey, optionKey, controlKey, shiftKey.
    public var modifiers: UInt32

    public init(key: UInt32, modifiers: UInt32) {
        self.key = key
        self.modifiers = modifiers & Self.allModifiers
    }

    public static let allModifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)
    public static let readPage = KeyCombo(key: UInt32(kVK_Escape), modifiers: UInt32(optionKey))
    public static let readArea = KeyCombo(key: UInt32(kVK_Escape), modifiers: UInt32(optionKey | shiftKey))

    /// As macOS menus show it, such as "⌥ ⇧ ⎋".
    public var display: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyName)
        return parts.joined(separator: " ")
    }

    var isFunctionKey: Bool { Self.functionKeys.keys.contains(Int(key)) }

    /// The key's name: a symbol for special keys, otherwise its character on a US layout.
    public var keyName: String {
        if let name = Self.special[Int(key)] ?? Self.functionKeys[Int(key)] { return name }
        return Self.characters[Int(key)] ?? "Key \(key)"
    }

    static let special: [Int: String] = [
        kVK_Escape: "⎋", kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]
    static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]
    static let characters: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
        kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
        kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
    ]
}

/// Why a combination can't be a shortcut, as Settings shows it.
public enum Refusal: Equatable, Sendable {
    case needsModifier
    case otherShortcut(String)
    case macOS(String?)
    case everyApp(String)
    case anotherApp

    public func message(_ combo: KeyCombo) -> String {
        switch self {
        case .needsModifier: "Add ⌘, ⌥ or ⌃ to the key."
        case .otherShortcut(let name): "\(name) already uses \(combo.display)."
        case .macOS(let feature?): "macOS uses \(combo.display) for \(feature)."
        case .macOS(nil): "macOS uses \(combo.display)."
        case .everyApp(let command): "Every app uses \(combo.display) for \(command)."
        case .anotherApp: "Another app uses \(combo.display)."
        }
    }
}

/// The checks made before asking the system for a combination (Model/Shortcuts.tla, Check). `system` is the
/// combinations macOS keeps, from its symbolic hot keys; `others` is Berang's other shortcuts, by name.
public func refusal(for combo: KeyCombo, others: [String: KeyCombo], system: Set<KeyCombo>) -> Refusal? {
    let strong = UInt32(cmdKey | optionKey | controlKey)
    if combo.modifiers & strong == 0, !combo.isFunctionKey { return .needsModifier }
    if let name = others.first(where: { $0.value == combo })?.key { return .otherShortcut(name) }
    if system.contains(combo) { return .macOS(systemFeatures[combo]) }
    if let command = appCommands[combo] { return .everyApp(command) }
    return nil
}

private func cmd(_ key: Int, _ extra: Int = 0) -> KeyCombo { KeyCombo(key: UInt32(key), modifiers: UInt32(cmdKey | extra)) }

/// What macOS uses its best-known shortcuts for, to name in a refusal.
let systemFeatures: [KeyCombo: String] = [
    cmd(kVK_Space): "Spotlight",
    KeyCombo(key: UInt32(kVK_Space), modifiers: UInt32(controlKey)): "switching input sources",
    cmd(kVK_ANSI_3, shiftKey): "screenshots", cmd(kVK_ANSI_4, shiftKey): "screenshots", cmd(kVK_ANSI_5, shiftKey): "screenshots",
    KeyCombo(key: UInt32(kVK_UpArrow), modifiers: UInt32(controlKey)): "Mission Control",
    KeyCombo(key: UInt32(kVK_DownArrow), modifiers: UInt32(controlKey)): "App Exposé",
    KeyCombo(key: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey)): "moving between spaces",
    KeyCombo(key: UInt32(kVK_RightArrow), modifiers: UInt32(controlKey)): "moving between spaces",
]

/// Commands every app's menus take, which a global shortcut would take away from them.
let appCommands: [KeyCombo: String] = [
    cmd(kVK_ANSI_C): "Copy", cmd(kVK_ANSI_V): "Paste", cmd(kVK_ANSI_X): "Cut", cmd(kVK_ANSI_Z): "Undo",
    cmd(kVK_ANSI_Z, shiftKey): "Redo", cmd(kVK_ANSI_A): "Select All", cmd(kVK_ANSI_S): "Save", cmd(kVK_ANSI_Q): "Quit",
    cmd(kVK_ANSI_W): "Close", cmd(kVK_ANSI_F): "Find", cmd(kVK_ANSI_N): "New", cmd(kVK_ANSI_O): "Open",
    cmd(kVK_ANSI_P): "Print", cmd(kVK_ANSI_T): "New Tab", cmd(kVK_ANSI_H): "Hide", cmd(kVK_ANSI_M): "Minimize",
    cmd(kVK_ANSI_Comma): "Settings", cmd(kVK_Tab): "switching apps", cmd(kVK_ANSI_Grave): "switching windows",
]
