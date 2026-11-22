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
