import Carbon.HIToolbox
import Testing
@testable import Keys

private let spotlight = KeyCombo(key: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
private let unnamedSystem = KeyCombo(key: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey))

@Test func refusesWhatMacOSKeepsAndNamesKnownFeatures() {
    let system: Set = [spotlight, unnamedSystem]
    #expect(refusal(for: spotlight, others: [:], system: system)?.message(spotlight) == "macOS uses ⌘ Space for Spotlight.")
    #expect(refusal(for: unnamedSystem, others: [:], system: system)?.message(unnamedSystem) == "macOS uses ⌃ ⌥ K.")
}

@Test func refusesTheOtherShortcutAndEveryAppsCommands() {
    let copy = KeyCombo(key: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey))
    #expect(refusal(for: .readArea, others: ["Read a screen area": .readArea], system: [])?.message(.readArea)
        == "Read a screen area already uses ⌥ ⇧ ⎋.")
    #expect(refusal(for: copy, others: [:], system: [])?.message(copy) == "Every app uses ⌘ C for Copy.")
}

@Test func needsAModifierExceptOnFunctionKeys() {
    let r = KeyCombo(key: UInt32(kVK_ANSI_R), modifiers: UInt32(shiftKey))
    #expect(refusal(for: r, others: [:], system: []) == .needsModifier)
    #expect(refusal(for: KeyCombo(key: UInt32(kVK_F13), modifiers: 0), others: [:], system: []) == nil)
    #expect(refusal(for: .readPage, others: [:], system: []) == nil)
}

@Test func theStandardShortcutsAreAllAllowedTogether() {
    let standard: [String: KeyCombo] = ["page": .readPage, "area": .readArea, "faster": .faster, "slower": .slower]
    for (name, combo) in standard {
        #expect(refusal(for: combo, others: standard.filter { $0.key != name }, system: []) == nil)
    }
    #expect(KeyCombo.faster.display == "⌥ ⇧ .")
}

@Test func showsCombinationsAsMenusDo() {
    #expect(KeyCombo.readArea.display == "⌥ ⇧ ⎋")
    #expect(KeyCombo(key: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey | controlKey)).display == "⌃ ⌘ R")
}
