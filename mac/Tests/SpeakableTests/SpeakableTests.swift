import Foundation
import Testing
@testable import Speakable

/// The cases the Python reference passes, in bench/clean/cases.json.
private struct Cases: Decodable {
    struct Text: Decodable, CustomTestStringConvertible {
        let `in`: String
        let out: String
        var testDescription: String { `in` }
    }

    struct Split: Decodable, CustomTestStringConvertible {
        let `in`: String
        let out: [String]
        var testDescription: String { `in` }
    }

    struct Spans: Decodable {
        let `in`: String
        let out: [[String]]
    }

    let text: [Text]
    let chunks: [Split]
    let spans: Spans

    static let all: Cases = {
        let url = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../bench/clean/cases.json").standardized
        return try! JSONDecoder().decode(Cases.self, from: Data(contentsOf: url))
    }()
}

@Test(arguments: Cases.all.text)
private func speaks(_ c: Cases.Text) {
    #expect(prepare(c.in).map(\.text).joined(separator: " ") == c.out)
}

@Test(arguments: Cases.all.chunks)
private func splits(_ c: Cases.Split) {
    #expect(prepare(c.in).map(\.text) == c.out)
}

@Test func chunksMapBackToTheirSource() {
    let src = Cases.all.spans.in as NSString
    let got = prepare(src as String).map { [$0.text, src.substring(with: NSRange($0.source))] }
    #expect(got == Cases.all.spans.out)
}

@Test func spansCountUTF16() {
    let src = "Built with ❤️ by us. Then $5."
    let chunk = prepare(src).last!
    #expect((src as NSString).substring(with: NSRange(chunk.source)) == "Then $5.")
}

@Test func skipsURLsWhenAsked() {
    #expect(prepare("See https://example.com now.", urls: .skip).map(\.text) == ["See now."])
}

@Test func numberWords() {
    #expect(intWords(1_000_001) == "one million one")
    #expect(intWords(-42) == "minus forty-two")
    #expect(intWords(999_999_999_999_999_999) == "nine nine nine nine nine nine nine nine nine nine nine nine nine nine nine nine nine nine")
}

@Test func wordsMapBackToTheirSource() {
    let src = "In 1969, Apollo 11 landed. It was July 20, 1969."
    let got = prepare(src).map { c in c.words.map { (src as NSString).substring(with: NSRange($0)) } }
    // "In nineteen sixty-nine, Apollo eleven landed." and "It was July twentieth, nineteen sixty-nine."
    #expect(got == [["In", "1969", "1969,", "Apollo", "11", "landed."], ["It", "was", "July 20", "July 20,", "1969", "1969."]])
}

@Test(arguments: Cases.all.text.map(\.in) + Cases.all.chunks.map(\.in))
private func everyWordHasASource(_ src: String) {
    for c in prepare(src) {
        #expect(c.words.count == c.text.split(whereSeparator: \.isWhitespace).count, "\(c.text)")
        #expect(c.words.allSatisfy { c.source.contains($0.lowerBound) || $0.isEmpty }, "\(c.text)")
    }
}

/// Bursts of tone with silence between, one burst per word, each starting at `starts` seconds.
private func bursts(_ starts: [Double], length: Double, total: Double) -> [Float] {
    (0..<Int(total * 24_000)).map { i in
        let t = Double(i) / 24_000
        return starts.contains { t >= $0 && t < $0 + length } ? Float(sin(2 * .pi * 220 * t)) * 0.5 : 0
    }
}

@Test func findsWordsAtTheStartsOfSpeech() {
    let truth = [0.2, 0.7, 1.2]
    let got = wordStarts("one two three", samples: bursts(truth, length: 0.35, total: 1.8))
    #expect(got.count == 3)
    for (g, t) in zip(got, truth) { #expect(abs(g - t) < 0.06, "\(got)") }
}

@Test func startsSilenceAtZero() {
    #expect(wordStarts("quiet words", samples: [Float](repeating: 0, count: 24_000)) == [0, 0])
    #expect(wordStarts("", samples: []).isEmpty)
}
