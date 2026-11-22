import CoreGraphics
import Foundation
import Testing
@testable import TextGrab

@Test(arguments: ["12", " 7 ", "xiv", "- 12 -", "Page 3", "page 3 of 10", "3 / 10"])
func knowsPageNumbers(_ text: String) {
    #expect(isPageNumber(text))
}

@Test(arguments: ["12 otters", "Introduction", "Chapter 3"])
func knowsTextFromPageNumbers(_ text: String) {
    #expect(!isPageNumber(text))
}

@Test func dropsHeadersAndFootersThatRepeat() {
    let pages = [["Field Notes · 1", "Otters swim.", "Otters eat.", "1"], ["Field Notes · 2", "Otters sleep.", "2"]]
    #expect(runningLines(pages) == [[0, 0], [0, 3], [1, 0], [1, 2]])
}

@Test func joinsWordsHyphenatedAtLineEnds() {
    #expect(joinLines(["a high metab-", "olic rate and an otter-", "Human bond"]) == "a high metabolic rate and an otter- Human bond")
}

@Test func startsAParagraphAtEachListItem() {
    let texts = ["Action items:", "- Write the notes.", "2. Test the player.", "(a) Measure memory.", "Budget follows."]
    let lines = texts.enumerated().map { i, t in PDFLine(text: t, bounds: CGRect(x: 72, y: 700 - CGFloat(i) * 16, width: 300, height: 13)) }
    #expect(pdfParagraphs([lines], heights: [792]).map(\.text) == ["Action items:", "- Write the notes.", "2. Test the player.", "(a) Measure memory. Budget follows."])
}

@Test func readsChromesPDFPagesByLine() throws {
    // A Chrome PDF page: lines end in "\r\n", and a link splits the second line.
    let json = #"""
    {"r": "AXGroup", "s": "AXLandmarkRegion", "c": [
        {"r": "AXStaticText", "v": "Life in the Water\r\nOtters have long webbed feet that help them swim (see\r\nthe work of "},
        {"r": "AXLink", "c": [{"r": "AXStaticText", "v": "Kruuk"}]},
        {"r": "AXStaticText", "v": "). They need a high metab-\r\nolic rate.\r\n"}
    ]}
    """#
    let page = Node(saved: try JSONDecoder().decode(SavedNode.self, from: Data(json.utf8)))
    var reader = Reader()
    reader.readPages([page], chrome: true)
    #expect(reader.blocks.map(\.text) == ["Life in the Water",
                                         "Otters have long webbed feet that help them swim (see the work of Kruuk ). They need a high metabolic rate."])
}
