import Foundation
import Testing
@testable import TextGrab

private func blocks(_ texts: String...) -> [Block] { texts.map { Block(kind: .text, text: $0, runs: []) } }

@Test func findsTheSameBlock() {
    let page = blocks("Title", "First paragraph.", "Second paragraph.")
    #expect(SavedPosition(page[2], at: 2).index(in: page) == 2)
}

@Test func findsTheBlockAfterTextWasAddedAbove() {
    let before = blocks("Title", "Second paragraph.")
    let after = blocks("Title", "A new notice.", "Second paragraph.")
    #expect(SavedPosition(before[1], at: 1).index(in: after) == 2)
}

@Test func picksTheRepeatNearestTheSavedIndex() {
    let page = blocks("edit", "One.", "edit", "Two.", "Three.", "edit")
    #expect(SavedPosition(page[0], at: 4).index(in: page) == 5)
}

@Test func givesUpWhenTheBlockIsGone() {
    #expect(SavedPosition(blocks("Removed.")[0], at: 0).index(in: blocks("Title", "Other.")) == nil)
}

@Test func keepsTheNewestPagesOnly() {
    let defaults = UserDefaults(suiteName: "berang-tests-\(UUID())")!
    let positions = Positions(defaults: defaults, limit: 2)
    let block = blocks("Text.")[0]
    for (i, page) in ["a", "b", "c"].enumerated() {
        positions[page] = SavedPosition(block, at: i, date: Date(timeIntervalSince1970: Double(i)))
    }
    #expect(positions["a"] == nil)
    let reloaded = Positions(defaults: defaults, limit: 2)
    #expect(reloaded["b"]?.index == 1 && reloaded["c"]?.index == 2)
}

@Test func decodesPositionsSavedWithATotal() throws {
    let saved = #"{"index":5,"text":"Hello","date":0,"total":100}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(SavedPosition.self, from: saved)
    #expect(decoded.index == 5 && decoded.text == "Hello")
}
