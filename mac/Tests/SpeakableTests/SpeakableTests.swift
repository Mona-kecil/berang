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
