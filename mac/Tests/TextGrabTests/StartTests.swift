import Testing
@testable import TextGrab

@Test func startsAtTheSelectedText() {
    #expect(startBlock(.range(block: 7), firstVisible: { 3 }, isVisible: { _ in false }) == (7, .selection))
}

@Test func startsAtAClickOnScreen() {
    #expect(startBlock(.caret(block: 5), firstVisible: { 3 }, isVisible: { $0 == 5 }) == (5, .click))
}

@Test func ignoresAClickScrolledOffScreen() {
    #expect(startBlock(.caret(block: 1), firstVisible: { 3 }, isVisible: { $0 >= 3 }) == (3, .screen))
}

@Test func startsAtTheTopOfTheScreenWithoutASelection() {
    #expect(startBlock(nil, firstVisible: { 3 }, isVisible: { _ in true }) == (3, .screen))
}

@Test(arguments: [0, 1, 5, 9, 10])
func findsTheFirstBlockBelowTheTop(top: Int) {
    #expect(firstIndex(10) { $0 < top } == top)
}
