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
        pitch.bypass = true
    }

    /// At normal speed the time-pitch unit is bypassed: it would only delay the voice, by up to about 0.1 s.
    var rate: Float {
        get { pitch.rate }
        set {
            pitch.rate = newValue
            pitch.bypass = newValue == 1
        }
    }

    /// Where the next queued sample goes on the queue's timeline, which counts voice samples from the last stop().
    private var end = 0
    /// The last sample rendered; the player reports none while paused.
    private var rendered = 0
    /// Seconds from the mixer to the speaker. Asking the device costs about 2 ms, so it is asked when the engine starts,
    /// which it does again after the output device changes.
    private var outputDelay = 0.0

    /// The sample being heard now, on the queue's timeline. Speed changes count voice samples, not output time.
    var position: Int {
        let delay = outputDelay + (pitch.bypass ? 0 : pitch.latency)
        return render() - Int(delay * format.sampleRate * Double(rate))
    }

    /// Samples queued but not yet played.
    var queued: Int { max(end - render(), 0) }

    /// Queues `samples` and returns the timeline sample they start at.
    func enqueue(_ samples: [Float]) throws -> Int {
        if !engine.isRunning {
            try engine.start()
            outputDelay = engine.outputNode.presentationLatency
        }
        if !isPaused { node.play() }
        // The timeline runs on while the queue is empty, so audio queued after a gap starts at the current sample.
        let start = max(end, render())
        end = start + samples.count
        node.scheduleBuffer(buffer(samples), completionHandler: nil)
        return start
    }

    /// Returns once everything queued has been heard, or the queue was stopped.
    func drain() async {
        guard engine.isRunning else { return }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            node.scheduleBuffer(buffer([0]), completionCallbackType: .dataPlayedBack) { _ in done.resume() }
        }
    }

    private func render() -> Int {
        if let t = node.lastRenderTime, let p = node.playerTime(forNodeTime: t) { rendered = Int(p.sampleTime) }
        return rendered
    }

    func pause() {
        isPaused = true
        node.pause()
    }

    func resume() {
        isPaused = false
        node.play()
    }

    /// Drops all queued audio and restarts the timeline. Cancel the task that queues audio first.
    func stop() {
        isPaused = false
        node.stop()
        end = 0
        rendered = 0
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        b.frameLength = b.frameCapacity
        samples.withUnsafeBufferPointer { b.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        return b
    }
}
