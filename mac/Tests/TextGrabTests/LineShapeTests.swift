import CoreGraphics
import Testing
@testable import TextGrab

// Lines 20 high from y 100, text from x 10 to x 410.
private func line(_ n: Int, _ from: CGFloat, _ to: CGFloat) -> CGRect {
    CGRect(x: from, y: 100 + CGFloat(n) * 20, width: to - from, height: 20)
}

@Test func oneLineIsOneRect() {
    #expect(lineShape(bounds: line(0, 50, 300), first: line(0, 50, 90), last: line(0, 250, 300)) == [line(0, 50, 300)])
}

@Test func twoLinesRunToTheEdges() {
    let bounds = line(0, 10, 410).union(line(1, 10, 410))
    #expect(lineShape(bounds: bounds, first: line(0, 200, 240), last: line(1, 60, 120))
        == [line(0, 200, 410), line(1, 10, 120)])
}

@Test func linesBetweenAreFull() {
    let bounds = line(0, 10, 410).union(line(3, 10, 410))
    let shape = lineShape(bounds: bounds, first: line(0, 200, 240), last: line(3, 60, 120))
    #expect(shape == [line(0, 200, 410), CGRect(x: 10, y: 120, width: 400, height: 40), line(3, 10, 120)])
}
