// Speaks text the way Berang does, chunk by chunk, for measuring word timing against a reference.
// usage: berang-say synth <text-file> <dir>   Paragraphs are separated by blank lines. Writes one 24 kHz WAV per
//                                            chunk, manifest.json, which lists each WAV with its text, and
//                                            first-word.json: per paragraph, the seconds from its text to its
//                                            first word's sound, on a warm voice.
//        berang-say estimate <dir>           Writes estimates.json: each chunk's words with their estimated starts.
//        berang-say previews <dir> [pocket] [kitten]  Writes <dir>/<engine>/<voice>.m4a: each voice saying the
//                                            sample, at one loudness, for the app's preview clips. [pocket] and
//                                            [kitten] are those engines' folders, as Berang installs them.
//        berang-say site <text-file> <dir> [voice ...]  Prints the text's chunks as the voice will say them. With
//                                            voices named, writes <dir>/<voice>.m4a of each reading the text,
//                                            and <dir>/timing.json: the text, each spoken word with its source span
//                                            in UTF-16, and each voice's word starts in seconds, for the website.
//                                            Name a Kitten voice as kitten/<voice>.
//        berang-say kitten <folder> <ref-dir>  Checks the MLX Kitten 2 against kittenml's PyTorch output in
//                                            <ref-dir>/ref.json: the same tokens and style, noise off.
//        berang-say kitten-g2p <g2p-ref.json> <cache>  Compares Misaki's phonemes with kittenml's, sentence by
//                                            sentence; <cache> holds Misaki's downloaded lexicons.
import Foundation
import HuggingFace
import Kitten
import MLX
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
guard args.count >= 3, ["synth", "estimate", "previews", "site", "kitten", "kitten-g2p"].contains(args[1]) else {
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

let dir = URL(filePath: args[["synth", "site", "kitten", "kitten-g2p"].contains(args[1]) ? 3 : 2])
do {
    if args[1] == "kitten-g2p", args.count > 3 {
        struct Line: Decodable { let text: String; let phonemes: String }
        let lines = try JSONDecoder().decode([Line].self, from: Data(contentsOf: URL(filePath: args[2])))
        let misaki = MisakiTextProcessor(cache: HubCache(cacheDirectory: URL(filePath: args[3])))
        try await misaki.prepare()
        var same = 0
        for line in lines {
            let mine = try misaki.process(text: line.text, language: "en-us")
            if mine == line.phonemes { same += 1 } else { print("- \(line.phonemes)\n+ \(mine)") }
        }
        print("\(same) of \(lines.count) sentences identical")
    } else if args[1] == "kitten", args.count > 3 {
        struct Reference: Decodable {
            let phonemes: String, tokens: [Int32], durations: [Int32], style: [Float], wav: [Float], f0: [Float], n: [Float], dur_raw: [Float]
        }
        let ref = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: URL(filePath: args[3]).appending(path: "ref.json")))
        Kitten2.noise = false
        let clock = ContinuousClock.now
        let kitten = try Kitten2.load(folder: URL(filePath: args[2]))
        print("loaded in \(ContinuousClock.now - clock), voices: \(kitten.voices.map(\.name).joined(separator: ", "))")
        let mine = kitten.tokens(ref.phonemes)
        print("tokens \(mine == ref.tokens ? "match" : "differ: \(mine) vs \(ref.tokens)")")
        let start = ContinuousClock.now
        let (audio, durations, f0, energy, raw) = kitten.run(ref.tokens, style: MLXArray(ref.style).reshaped([1, -1]), speed: 1)
        let worst = { (a: [Float], b: [Float]) in zip(a, b).map { abs($0 - $1) }.max() ?? -1 }
        print(String(format: "unrounded durations: max difference %.5f", worst(raw, ref.dur_raw)))
        try JSONEncoder().encode(["f0": f0, "n": energy]).write(to: dir.appending(path: "mlx-prosody.json"))
        print(String(format: "F0 %d vs %d values, max difference %.4f; N max difference %.4f", f0.count, ref.f0.count,
                     worst(f0, ref.f0), worst(energy, ref.n)))
        print("synthesized \(audio.count) samples in \(ContinuousClock.now - start) (first call)")
        for _ in 0 ..< 2 {
            let warm = ContinuousClock.now
            _ = kitten.synthesize(ref.tokens, style: MLXArray(ref.style).reshaped([1, -1]), speed: 1)
            print("warm: \(ContinuousClock.now - warm) for \(Double(audio.count) / 24_000) s of audio")
        }
        print("durations \(durations == ref.durations ? "match" : "differ: \(durations) vs \(ref.durations)")")
        let n = min(audio.count, ref.wav.count)
        let diff = zip(audio.prefix(n), ref.wav.prefix(n)).map { abs($0 - $1) }.max() ?? 0
        let dot = zip(audio.prefix(n), ref.wav.prefix(n)).reduce(0) { $0 + $1.0 * $1.1 }
        let norm = (audio.prefix(n).reduce(0) { $0 + $1 * $1 } * ref.wav.prefix(n).reduce(0) { $0 + $1 * $1 }).squareRoot()
        print(String(format: "samples %d vs %d, max difference %.5f, correlation %.6f", audio.count, ref.wav.count, diff, dot / max(norm, 1e-9)))
        try writeWAV(audio, to: dir.appending(path: "mlx.wav"))
        try writeWAV(ref.wav, to: dir.appending(path: "torch.wav"))
    } else if args[1] == "previews" {
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
        if args.count > 4 {
            let folder = URL(filePath: args[4])
            let kitten = try Kitten2.load(folder: folder)
            let misaki = MisakiTextProcessor(cache: HubCache(cacheDirectory: folder.appending(path: "G2P")))
            try await misaki.prepare()
            let phonemes = try misaki.process(text: voiceSampleText, language: "en-us")
            for voice in kitten.voices {
                try writePreview(kitten.speak(phonemes, voice: voice.key), to: dir.appending(path: "kitten/\(voice.key).m4a"))
            }
            print("kitten: \(kitten.voices.count) voices")
        }
    } else if args[1] == "site" {
        struct Timing: Encodable {
            let text: String
            let say: [String]
            let source: [[Int]]
            var voices: [String: [Double]] = [:]
        }
        let text = try String(contentsOf: URL(filePath: args[2]), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let chunks = prepare(text)
        for chunk in chunks { print("[\(chunk.source.lowerBound):\(chunk.source.upperBound)] \(chunk.text)") }
        var timing = Timing(text: text, say: chunks.flatMap { $0.text.split(whereSeparator: \.isWhitespace).map(String.init) },
                            source: chunks.flatMap { $0.words.map { [$0.lowerBound, $0.upperBound] } })
        let voices = Array(args.dropFirst(4))
        if !voices.isEmpty {
            var phonon: Phonon?, kitten: (model: Kitten2, misaki: MisakiTextProcessor)?
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for name in voices {
                // "kitten/eleanor" is a Kitten voice, as Berang installs Kitten; any other name is a Phonon voice.
                let voice = name.hasPrefix("kitten/") ? String(name.dropFirst("kitten/".count)) : name
                var samples: [Float] = [], starts: [Double] = []
                for chunk in chunks {
                    var part: [Float] = []
                    if name.hasPrefix("kitten/") {
                        if kitten == nil {
                            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                                .appending(path: "Berang/Kitten")
                            let misaki = MisakiTextProcessor(cache: HubCache(cacheDirectory: folder.appending(path: "G2P")))
                            try await misaki.prepare()
                            kitten = (try Kitten2.load(folder: folder), misaki)
                        }
                        // As KittenSpeech does: joined words without their hyphen, pieces of at most 350 phonemes,
                        // and Kitten's 0.15 s pause after the chunk.
                        let text = chunk.text.replacing(/(\w)-(?=\w)/) { "\($0.1) " }
                        var rest = Substring(try kitten!.misaki.process(text: text, language: "en-us")), first = true
                        while !rest.isEmpty {
                            let cut = rest.count <= 350 ? rest.endIndex
                                : rest.prefix(350).lastIndex(of: " ") ?? rest.index(rest.startIndex, offsetBy: 350)
                            part += kitten!.model.speak(String(rest[..<cut]), voice: voice, keepStart: first)
                            rest = rest[cut...].drop { $0 == " " }
                            first = false
                        }
                        part += [Float](repeating: 0, count: Int(0.15 * 24_000))
                    } else {
                        if phonon == nil { phonon = try await Phonon.load(models: PhononModels.defaultDirectory, language: .english) }
                        try await phonon!.setVoice(voice)
                        for try await piece in phonon!.stream(chunk.text) { part += piece }
                    }
                    let offset = Double(samples.count) / 24_000
                    starts += wordStarts(chunk.text, samples: part).map { offset + $0 }
                    samples += part
                }
                timing.voices[voice] = starts.map { ($0 * 1000).rounded() / 1000 }
                try writePreview(samples, to: dir.appending(path: "\(voice).m4a"))
                print("\(voice): \(String(format: "%.1f", Double(samples.count) / 24_000)) s")
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            try encoder.encode(timing).write(to: dir.appending(path: "timing.json"))
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
