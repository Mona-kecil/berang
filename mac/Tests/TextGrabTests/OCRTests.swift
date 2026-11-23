import Foundation
import Testing
@testable import TextGrab

/// otters.png is the first page of otters.pdf as an image; see fixtures/otters-png.swift.
@Test func readsTheTextOfAnImage() throws {
    let url = SavedPage.folder.appending(path: "fixtures/otters.png")
    let blocks = try #require(readImage(url))
    #expect(blocks.contains { $0.kind == .heading && $0.text == "Life in the Water" })
    let paragraphs = blocks.filter { $0.kind == .text }.map(\.text)
    #expect(paragraphs.count == 2)
    #expect(paragraphs.first?.hasPrefix("Otters are distinguished by their long, slim bodies") == true)
    #expect(paragraphs.last?.contains("a high metabolic rate") == true)
}

/// canvas.png is fixtures/canvas.html, a page that draws its text on a canvas, rendered by Chrome. Its paragraphs
/// are a third of its lines, and its last line has no descenders, so Vision's box for it is a third shorter.
@Test func readsShortTextDrawnOnACanvas() throws {
    let blocks = try #require(readImage(SavedPage.folder.appending(path: "fixtures/canvas.png")))
    #expect(blocks.map(\.kind) == [.heading, .text, .text])
    #expect(blocks.last?.text == "Budget: about forty percent of last quarter goes to testing devices, and the rest to the voice work.")
}

@Test func typedTextReadsEachLineAsAParagraph() {
    let page = textPage("Dr. Rivera's flight leaves at 7:45.\n\n  Gate   B12,  she said.\n")
    #expect(page.blocks.map(\.text) == ["Dr. Rivera's flight leaves at 7:45.", "Gate B12, she said."])
    #expect(page.address == nil)
}
