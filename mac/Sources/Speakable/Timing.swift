import Foundation

/// When each space-separated word of `text` starts in `samples`, the voice's audio for it, in seconds.
///
/// The voice gives no timings, so they are estimated. Speech runs from the first loud frame to the last.
/// Each word is expected to take time in proportion to its letters and syllables, plus a pause after a
/// comma, and a dynamic program places word boundaries near that expectation, preferring quiet frames.
/// Against forced alignment on text the fit never saw, the median error is about 100 ms. See bench/timing.
public func wordStarts(_ text: String, samples: [Float], sampleRate: Double = 24_000) -> [Double] {
    let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
    let n = words.count
    guard n > 0 else { return [] }
    let hop = Int(sampleRate * frameSeconds)
    let loudness = stride(from: 0, to: samples.count, by: hop).map { start in
        let end = min(start + hop, samples.count)
        return sqrt(samples[start..<end].reduce(0) { $0 + $1 * $1 } / Float(end - start))
    }
    let peak = loudness.max() ?? 0
    guard peak > 0, let on = loudness.firstIndex(where: { $0 > peak * silenceRatio }),
          let last = loudness.lastIndex(where: { $0 > peak * silenceRatio }) else { return words.map { _ in 0 } }
    let frames = last + 1 - on

    var expected = words.enumerated().map { i, w in
        weight.base + weight.letter * Double(w.count(where: \.isLetter)) + weight.syllable * syllables(w)
            + (i < n - 1 && endsClause(w) ? weight.comma : 0)
    }
    let total = expected.reduce(0, +)
    expected = expected.map { $0 / total * Double(frames) }
    let time = { (frame: Int) in (Double(on + frame) * frameSeconds) + lead }
    guard n > 1, frames >= n else {
        var t = 0.0
        return expected.map { e in
            defer { t += e }
            return time(Int(t))
        }
    }

    // How much a boundary at each frame is favored: the quieter the frame, the more.
    let top = log(Double(peak) + 1e-5)
    let quiet = (0...frames).map { f in (top - log(Double(loudness[min(on + f, loudness.count - 1)]) + 1e-5)) / quietScale }

    // best[i][t]: the best score with the first i words ending at frame t. from[i][t]: where word i starts.
    var best = [[Double]](repeating: [Double](repeating: -.infinity, count: frames + 1), count: n + 1)
    var from = [[Int]](repeating: [Int](repeating: 0, count: frames + 1), count: n + 1)
    best[0][0] = 0
    for i in 1...n {
        let mean = expected[i - 1], spread = max(lengthSpread * mean, 2), window = Int(3 * mean) + 10
        for t in (i == n ? frames : 1)...frames {
            var top = -Double.infinity, arg = 0
            for length in 1...min(t, window) where best[i - 1][t - length] > -.infinity {
                let z = (Double(length) - mean) / spread
                let score = best[i - 1][t - length] - 0.5 * z * z
                if score > top { top = score; arg = t - length }
            }
            best[i][t] = top + (i < n ? quietWeight * quiet[t] : 0)
            from[i][t] = arg
        }
    }
    var starts = [Int](repeating: 0, count: n), t = frames
    for i in stride(from: n, to: 0, by: -1) {
        t = from[i][t]
        starts[i - 1] = t
    }
    // A word starts when its sound does, so a start inside a pause moves to the pause's end. Only a long,
    // near-silent run counts: a quiet sound like the "s" a word starts with is part of the word.
    let silent = { (f: Int) in loudness[on + f] <= peak * pauseRatio }
    for i in 1..<n where silent(starts[i]) {
        var end = starts[i]
        while end < frames - 1, silent(end) { end += 1 }
        var begin = starts[i]
        while begin > 0, silent(begin - 1) { begin -= 1 }
        if Double(end - begin) * frameSeconds >= minPause { starts[i] = min(end, i < n - 1 ? starts[i + 1] : end) }
    }
    return starts.map(time)
}

private let frameSeconds = 0.01
/// Quieter than this share of the loudest frame counts as silence.
private let silenceRatio: Float = 0.06
/// Seconds per unit, fitted by least squares to forced-aligned word lengths in bench/timing. Only the
/// ratios matter here, since the expected lengths are scaled to fill the speech.
private let weight = (base: 0.0142, letter: 0.0447, syllable: 0.0284, comma: 0.3255)
/// A word's length may stray from expected by about this share of it.
private let lengthSpread = 0.3
/// A run this quiet and at least this long is a pause between words.
private let pauseRatio: Float = 0.02
private let minPause = 0.1
private let quietWeight = 0.5
private let quietScale = 6.0
/// Starts are moved this much later, which halves the median error while keeping the highlight a little early.
private let lead = 0.03

private func endsClause(_ word: String) -> Bool {
    word.last(where: { !"\"')]}”’".contains($0) }).map { ",;:—–".contains($0) } ?? false
}

/// Vowel groups, a rough syllable count.
func syllables(_ word: String) -> Double {
    let letters = word.lowercased().filter(\.isLetter)
    var groups = 0, inVowel = false
    for c in letters {
        let vowel = "aeiouy".contains(c)
        if vowel && !inVowel { groups += 1 }
        inVowel = vowel
    }
    if letters.hasSuffix("e"), !letters.hasSuffix("le"), groups > 1 { groups -= 1 }
    return Double(max(groups, 1))
}
