import ApplicationServices
import Testing
@testable import TextGrab

private func build(_ pieces: [String], rendered: String?, kind: Block.Kind = .text) -> [Block] {
    var b = BlockBuilder()
    let el = AXUIElementCreateSystemWide()
    for p in pieces { b.append(p, from: el, at: 0) }
    return b.build(kind, rendered: rendered)
}

@Test func restoresSpacesSafariTrimsAroundLinks() {
    let blocks = build(["Otters are in the", "subfamily", "Lutrinae."], rendered: "Otters are in the subfamily Lutrinae.")
    #expect(blocks.map(\.text) == ["Otters are in the subfamily Lutrinae."])
    #expect(blocks[0].runs.map(\.range) == [0..<17, 18..<27, 28..<37])
}

@Test func joinsPiecesWhenRenderedTextIsMissing() {
    #expect(build(["Otters are ", "webbed", " feet."], rendered: nil).map(\.text) == ["Otters are webbed feet."])
}

@Test func fallsBackWhenRenderedTextDisagrees() {
    #expect(build(["Hello ", "world"], rendered: "Something else").map(\.text) == ["Hello world"])
}

@Test func leavesOutAPieceTheBrowserDoesNotShow() {
    let blocks = build(["First", "paragraph.", "Elapsed: 0 seconds", "Second", "paragraph."],
                       rendered: "First paragraph.\nSecond paragraph.")
    #expect(blocks.map(\.text) == ["First paragraph.", "Second paragraph."])
}

@Test func splitsAtLineBreaks() {
    let blocks = build(["July 2023", "If you collected lists.", "Partly my goal."],
                       rendered: "July 2023\n\nIf you collected lists.\n\nPartly my goal.")
    #expect(blocks.map(\.text) == ["July 2023", "If you collected lists.", "Partly my goal."])
    #expect(blocks[1].runs.map(\.range) == [0..<23])
}

@Test func dropsListMarkersAndNestedTextOutsideThePieces() {
    let blocks = build(["Genus ", "Lutra"], rendered: "• Genus Lutra\n• †Lutra euxena – Malta")
    #expect(blocks.map(\.text) == ["Genus Lutra"])
}

@Test func keepsOffsetIntoElementPastLeadingSpace() {
    let blocks = build(["a", "  b"], rendered: nil)
    #expect(blocks[0].text == "a b")
    #expect(blocks[0].runs[1].offset == 2)
}

@Test func skippedTextDoesNotCatchARepeat() {
    var b = BlockBuilder()
    let el = AXUIElementCreateSystemWide()
    b.skip("KAI Commuter", from: el)
    b.append("KAI Commuter", from: el, at: 0)
    b.append(" connects the city.", from: el, at: 0)
    #expect(b.build(.text, rendered: "KAI Commuter\nKAI Commuter connects the city.").map(\.text) == ["KAI Commuter connects the city."])
}

@Test func splitsAtLineBreaksInsideSkippedText() {
    var b = BlockBuilder()
    let el = AXUIElementCreateSystemWide()
    b.append("Before.", from: el, at: 0)
    b.skip("Caption\nline two", from: el)
    b.append("After.", from: el, at: 0)
    #expect(b.build(.text, rendered: "Before.\nCaption\nline two\nAfter.").map(\.text) == ["Before.", "After."])
}

@Test func findsAPieceTheBrowserPutBeforeSkippedText() {
    var b = BlockBuilder()
    let el = AXUIElementCreateSystemWide()
    b.append("Intro.", from: el, at: 0)
    b.skip("Floated caption", from: el)
    b.append("Next.", from: el, at: 0)
    b.append("Last.", from: el, at: 0)
    #expect(b.build(.text, rendered: "Intro.\nNext.\nFloated caption\nLast.").map(\.text) == ["Intro.", "Next.", "Last."])
}

@Test func dropsBlocksWithoutWords() {
    #expect(build(["\u{FFFC}", " | "], rendered: nil).isEmpty)
}
