import Foundation
import Testing
@testable import TextGrab

/// Books shows a page as a web area holding one text element per paragraph, with no rendered text.
@Test func readsEachBooksParagraphAsABlock() throws {
    let json = #"""
    {"r": "AXWindow", "c": [{"r": "AXGroup", "s": "iOSContentGroup", "c": [
        {"r": "AXButton", "v": "Page 9"},
        {"r": "AXWebArea", "c": [
            {"r": "AXStaticText", "v": "• Why folk remedies persist"},
            {"r": "AXStaticText", "v": "A few years ago, he started teaching."},
            {"r": "AXStaticText", "v": "We wanted to take apart sticky ideas"}
        ]}
    ]}]}
    """#
    let blocks = read(saved: try JSONDecoder().decode(SavedNode.self, from: Data(json.utf8)))
    #expect(blocks.map(\.text) == ["• Why folk remedies persist", "A few years ago, he started teaching.", "We wanted to take apart sticky ideas"])
}
