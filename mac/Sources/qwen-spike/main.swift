// Measures Qwen3-TTS on MLX as Berang would run it: time to first audio, speed, and memory.
// usage: qwen-spike <model folder> <text file> <cache limit MB, or "none"> [voice]
import Foundation
import MLX
import MLXAudioCore
import MLXAudioTTS

func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
    return Double(info.phys_footprint) / 1e6
}
func seconds(_ start: ContinuousClock.Instant) -> Double {
    let d = ContinuousClock.now - start
    return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
}

let args = CommandLine.arguments
let folder = args[1], text = try String(contentsOfFile: args[2], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
if args[3] != "none", let mb = Int(args[3]) { Memory.cacheLimit = mb * 1024 * 1024 }
let voice = args.count > 4 ? args[4] : "indonesian_speaker"
var peak = footprintMB()
let t0 = ContinuousClock.now
let model = try await TTS.loadModel(modelRepo: folder)
print(String(format: "load %.1fs, footprint %.0f MB", seconds(t0), footprintMB()))
// Berang speaks a page sentence by sentence.
let sentences = text.split(whereSeparator: { ".?!".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) + "." }.filter { $0.count > 1 }
var samples: [Float] = []
for run in 1...2 {
    samples = []
    let start = ContinuousClock.now
    var first: Double?
    for s in sentences {
        for try await event in model.generateStream(text: s, voice: voice, refAudio: nil, refText: nil, language: nil,
                                                    generationParameters: model.defaultGenerationParameters, streamingInterval: 0.5) {
            if case .audio(let chunk) = event {
                first = first ?? seconds(start)
                samples += chunk.asArray(Float.self)
                peak = max(peak, footprintMB())
            }
        }
    }
    let gen = seconds(start), audio = Double(samples.count) / Double(model.sampleRate)
    print(String(format: "run %d: first audio %.2fs, %.1fs of audio in %.1fs, %.2f× real time, footprint now %.0f MB, peak %.0f MB, MLX peak %.0f MB",
                 run, first ?? -1, audio, gen, audio / gen, footprintMB(), peak, Double(Memory.peakMemory) / 1e6))
}
try AudioUtils.writeWavFile(samples: samples, sampleRate: model.sampleRate, fileURL: URL(filePath: "/tmp/qwen-id/spike-out.wav"))
