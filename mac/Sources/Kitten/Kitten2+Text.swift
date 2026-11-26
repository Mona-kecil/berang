import Foundation
import HuggingFace
import MLXAudioTTS

extension Kitten2 {
    /// Where Berang installs the model. Misaki's lexicons sit in its G2P folder.
    public static let defaultFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Berang/Kitten")

    /// Misaki's lexicons and BART for the model installed in `folder`.
    public static func lexicons(in folder: URL) -> HubCache {
        HubCache(cacheDirectory: folder.appending(path: "G2P"))
    }

    /// Kitten's training text was cut at 350 phonemes.
    private static let longest = 350
    private static let pause = 0.15

    /// Says one chunk of text the way Berang does: its joined words without their hyphen, pieces of at most 350
    /// phonemes, only the first keeping its start, and Kitten's 0.15 s pause after the chunk. Each piece goes to
    /// `emit` as it is made.
    public func say(
        _ text: String, voice: String, misaki: MisakiTextProcessor, emit: ([Float]) throws -> Void
    ) throws {
        // Misaki writes the hyphen in "per-project" or "twenty-one" as a dash, which Kitten pauses at, so a joined
        // word is said as two words in a row instead.
        let words = text.replacing(/(\w)-(?=\w)/) { "\($0.1) " }
        let phonemes = try misaki.process(text: words, language: "en-us")
        for (i, piece) in Self.pieces(phonemes).enumerated() {
            try Task.checkCancellation()
            try emit(speak(piece, voice: voice, keepStart: i == 0))
        }
        try emit([Float](repeating: 0, count: Int(Self.pause * Double(Self.sampleRate))))
    }

    /// Phonemes cut at spaces into pieces Kitten was trained on.
    private static func pieces(_ phonemes: String) -> [String] {
        var pieces: [String] = [], rest = Substring(phonemes)
        while rest.count > longest {
            let cut = rest.prefix(longest).lastIndex(of: " ") ?? rest.index(rest.startIndex, offsetBy: longest)
            pieces.append(String(rest[..<cut]))
            rest = rest[cut...].drop { $0 == " " }
        }
        if !rest.isEmpty { pieces.append(String(rest)) }
        return pieces
    }
}
