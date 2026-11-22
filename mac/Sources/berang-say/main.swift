// Speaks text the way Berang does, chunk by chunk, for measuring word timing against a reference.
// usage: berang-say synth <text-file> <dir>   Paragraphs are separated by blank lines. Writes one 24 kHz WAV per
//                                            chunk and manifest.json, which lists each WAV with its text.
//        berang-say estimate <dir>           Writes estimates.json: each chunk's words with their estimated starts.
import Foundation
import PhononTTS
import Speakable

struct Entry: Codable {
    let wav: String
    let text: String
}

struct Estimate: Codable {
    let wav: String
    let words: [String]
    let starts: [Double]
    let seconds: Double
}

let args = CommandLine.arguments
guard args.count >= 3, ["synth", "estimate"].contains(args[1]) else {
    FileHandle.standardError.write(Data("usage: berang-say synth <text-file> <dir> | estimate <dir>\n".utf8))
    exit(2)
}

func writeWAV(_ samples: [Float], to url: URL, rate: Int = 24_000) throws {
    var d = Data()
    func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    d.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + samples.count * 2))
    d.append(contentsOf: Array("WAVEfmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
    put(UInt32(rate)); put(UInt32(rate * 2)); put(UInt16(2)); put(UInt16(16))
    d.append(contentsOf: Array("data".utf8)); put(UInt32(samples.count * 2))
    for s in samples { put(Int16(max(-1, min(1, s)) * 32767)) }
    try d.write(to: url)
}

func readWAV(_ url: URL) throws -> [Float] {
    let d = try Data(contentsOf: url)
    return stride(from: 44, to: d.count - 1, by: 2).map { i in
        Float(Int16(bitPattern: UInt16(d[i]) | UInt16(d[i + 1]) << 8)) / 32767
    }
}

let dir = URL(filePath: args[args[1] == "synth" ? 3 : 2])
do {
    if args[1] == "synth" {
        let text = try String(contentsOf: URL(filePath: args[2]), encoding: .utf8)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tts = try await Phonon.load(models: PhononModels.defaultDirectory, language: .english)
        var entries: [Entry] = []
        for (p, paragraph) in text.components(separatedBy: "\n\n").enumerated() where !paragraph.isEmpty {
            for (c, chunk) in prepare(paragraph).enumerated() {
                let name = "p\(p)c\(c).wav"
                try writeWAV(try await tts.synthesize(chunk.text), to: dir.appending(path: name))
                entries.append(Entry(wav: name, text: chunk.text))
            }
        }
        try JSONEncoder().encode(entries).write(to: dir.appending(path: "manifest.json"))
        print("\(entries.count) chunks")
    } else {
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: dir.appending(path: "manifest.json")))
        let clock = ContinuousClock.now
        let estimates = try entries.map { e in
            let samples = try readWAV(dir.appending(path: e.wav))
            return Estimate(wav: e.wav, words: e.text.split(whereSeparator: \.isWhitespace).map(String.init),
                            starts: wordStarts(e.text, samples: samples), seconds: Double(samples.count) / 24_000)
        }
        let took = ContinuousClock.now - clock
        try JSONEncoder().encode(estimates).write(to: dir.appending(path: "estimates.json"))
        print("\(estimates.count) chunks in \(Int(took / .milliseconds(1))) ms")
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
