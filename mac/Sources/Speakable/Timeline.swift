/// When each queued chunk plays: the sample its audio starts at in the playback queue, and its words' starts.
public struct Timeline {
    public struct Entry {
        public let block: Int
        public let chunk: Chunk
        public let start: Int
        /// The queue sample each word starts at, known once the chunk's audio is complete.
        public fileprivate(set) var words: [Int]?
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    /// Adds a chunk whose audio starts at queue sample `start`, after every chunk added before it.
    public mutating func append(block: Int, chunk: Chunk, start: Int) {
        entries.append(Entry(block: block, chunk: chunk, start: start))
    }

    /// Times the last chunk's words from all of its audio.
    public mutating func timeLast(_ samples: [Float], sampleRate: Double) {
        guard let last = entries.indices.last else { return }
        let e = entries[last], starts = wordStarts(e.chunk.text, samples: samples, sampleRate: sampleRate)
        guard starts.count == e.chunk.words.count else { return }
        entries[last].words = starts.map { e.start + Int($0 * sampleRate) }
    }

    /// The chunk heard at queue sample `sample`, and the source span of the word heard, once it is timed.
    public func heard(at sample: Int) -> (block: Int, chunk: Chunk, word: Range<Int>?)? {
        var low = 0, high = entries.count
        while low < high {
            let mid = (low + high) / 2
            if entries[mid].start <= sample { low = mid + 1 } else { high = mid }
        }
        guard low > 0 else { return nil }
        let e = entries[low - 1]
        let word = e.words?.lastIndex { $0 <= sample }.map { e.chunk.words[$0] }
        return (e.block, e.chunk, word)
    }
}
