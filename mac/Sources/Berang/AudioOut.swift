import AVFoundation

/// Plays streamed 24 kHz mono audio at an adjustable speed without changing pitch.
@MainActor final class AudioOut {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let pitch = AVAudioUnitTimePitch()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    private(set) var isPaused = false

    init() {
        engine.attach(node)
        engine.attach(pitch)
        engine.connect(node, to: pitch, format: format)
        engine.connect(pitch, to: engine.mainMixerNode, format: format)
    }

    var rate: Float {
        get { pitch.rate }
        set { pitch.rate = newValue }
    }

    /// Returns once the last chunk has been heard, not just generated. Throws when the task is cancelled.
    func play(_ chunks: AsyncThrowingStream<[Float], Error>) async throws {
        if !engine.isRunning { try engine.start() }
        if !isPaused { node.play() }
        for try await chunk in chunks {
            try Task.checkCancellation()
            node.scheduleBuffer(buffer(chunk), completionHandler: nil)
        }
        try Task.checkCancellation()
        // Completes after every buffer before it has played, or when stop() clears the queue.
        let last = buffer([0])
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            node.scheduleBuffer(last, completionCallbackType: .dataPlayedBack) { _ in done.resume() }
        }
        try Task.checkCancellation()
    }

    func pause() {
        isPaused = true
        node.pause()
    }

    func resume() {
        isPaused = false
        node.play()
    }

    /// Drops all queued audio. Cancel the task inside play() first, so it does not queue more.
    func stop() {
        isPaused = false
        node.stop()
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        b.frameLength = b.frameCapacity
        samples.withUnsafeBufferPointer { b.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        return b
    }
}
