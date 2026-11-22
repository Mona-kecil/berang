// Speaks text the way Berang does, chunk by chunk, for measuring word timing against a reference.
// usage: berang-say synth <text-file> <dir>   Paragraphs are separated by blank lines. Writes one 24 kHz WAV per
//                                            chunk, manifest.json, which lists each WAV with its text, and
//                                            first-word.json: per paragraph, the seconds from its text to its
//                                            first word's sound, on a warm voice.
//        berang-say estimate <dir>           Writes estimates.json: each chunk's words with their estimated starts.
//        berang-say previews <dir> [pocket]  Writes <dir>/<engine>/<voice>.m4a: each voice saying the sample, at
//                                            one loudness, for the app's preview clips. [pocket] is Pocket's model
//                                            folder, as Berang installs it.
import Foundation
import MLXAudioTTS
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
guard args.count >= 3, ["synth", "estimate", "previews"].contains(args[1]) else {
    FileHandle.standardError.write(Data("usage: berang-say synth <text-file> <dir> | estimate <dir> | previews <dir> [pocket]\n".utf8))
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

/// Writes `samples` as a small AAC clip at -20 dBFS RMS, its peaks held under -1 dBFS, so voices compare by sound
/// and not by loudness.
func writePreview(_ samples: [Float], to url: URL) throws {
    let rms = (samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1))).squareRoot()
    let peak = samples.map(abs).max() ?? 1
    let gain = min(0.1 / max(rms, 1e-6), 0.89 / max(peak, 1e-6))
    let wav = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".wav")
    defer { try? FileManager.default.removeItem(at: wav) }
    try writeWAV(samples.map { $0 * gain }, to: wav)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let convert = Process()
    convert.executableURL = URL(filePath: "/usr/bin/afconvert")
    convert.arguments = ["-f", "m4af", "-d", "aac", "-b", "32000", wav.path, url.path]
    try convert.run()
    convert.waitUntilExit()
    guard convert.terminationStatus == 0 else { throw PhononError(description: "afconvert failed for \(url.lastPathComponent)") }
}

let dir = URL(filePath: args[args[1] == "synth" ? 3 : 2])
do {
    if args[1] == "previews" {
        // Phonon's voices, then Pocket's when its model folder is given.
        let phonon = try await Phonon.load(models: PhononModels.defaultDirectory, language: .english)
        for voice in phonon.voices {
            try await phonon.setVoice(voice)
            var samples: [Float] = []
            for chunk in prepare(voiceSampleText) { for try await part in phonon.stream(chunk.text) { samples += part } }
            try writePreview(samples, to: dir.appending(path: "phonon/\(voice).m4a"))
        }
        print("phonon: \(phonon.voices.count) voices")
        if args.count > 3 {
            let folder = URL(filePath: args[3])
            let pocket = try await TTS.loadModel(modelRepo: folder.path)
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "embeddings").path)
                .filter { $0.hasSuffix(".safetensors") }.map { String($0.dropLast(".safetensors".count)) }.sorted()
            for voice in names {
                var samples: [Float] = []
                for try await event in pocket.generateStream(
                    text: voiceSampleText, voice: voice, refAudio: nil, refText: nil, language: nil,
                    generationParameters: pocket.defaultGenerationParameters, streamingInterval: 0.32
                ) {
                    if case .audio(let chunk) = event { samples += chunk.asArray(Float.self) }
                }
                try writePreview(samples, to: dir.appending(path: "pocket/\(voice).m4a"))
            }
            print("pocket: \(names.count) voices")
        }
    } else if args[1] == "synth" {
        let text = try String(contentsOf: URL(filePath: args[2]), encoding: .utf8)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tts = try await Phonon.load(models: PhononModels.defaultDirectory, language: .english)
        // The app keeps the voice loaded, so the first utterance's setup is not part of a reading.
        _ = try await tts.synthesize("This sentence warms the voice up.")
        var entries: [Entry] = [], firstWords: [Double] = []
        for (p, paragraph) in text.components(separatedBy: "\n\n").enumerated() where !paragraph.isEmpty {
            let clock = ContinuousClock.now
            for (c, chunk) in prepare(paragraph).enumerated() {
                var samples: [Float] = [], firstAudio: Duration?
                for try await part in tts.stream(chunk.text) {
                    firstAudio = firstAudio ?? ContinuousClock.now - clock
                    samples += part
                }
                if c == 0, let firstAudio, let start = wordStarts(chunk.text, samples: samples).first {
                    firstWords.append(firstAudio / .seconds(1) + start)
                }
                let name = "p\(p)c\(c).wav"
                try writeWAV(samples, to: dir.appending(path: name))
                entries.append(Entry(wav: name, text: chunk.text))
            }
        }
        try JSONEncoder().encode(entries).write(to: dir.appending(path: "manifest.json"))
        try JSONEncoder().encode(firstWords).write(to: dir.appending(path: "first-word.json"))
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
