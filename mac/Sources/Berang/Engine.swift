import Foundation
import PhononTTS

/// What the player reads with: an engine's model, conditioned on one of its voices.
protocol Speech: AnyObject, Sendable {
    func setVoice(_ name: String) async throws
    /// Speaks `text`, yielding mono audio at `Engine.sampleRate` as it is generated.
    func stream(_ text: String) -> AsyncThrowingStream<[Float], Error>
}

extension Phonon: Speech {}

/// The voice engines Berang speaks with, each downloaded on first use.
enum Engine: String, CaseIterable, Sendable {
    case phonon, pocket

    /// Every engine speaks mono audio at this rate.
    static let sampleRate = 24_000.0

    var title: String {
        switch self {
        case .phonon: "Phonon"
        case .pocket: "Pocket"
        }
    }

    /// The download, in bytes.
    var size: Int64 {
        switch self {
        case .phonon: 137_000_000
        case .pocket: 240_000_000
        }
    }

    var isInstalled: Bool {
        switch self {
        case .phonon: PhononVoice.isInstalled
        case .pocket: PocketVoice.isInstalled
        }
    }

    /// The installed voices, read from disk without loading the model, the default first.
    var voices: [String] {
        switch self {
        case .phonon: PhononVoice.names
        case .pocket: PocketVoice.names
        }
    }

    /// The voice to read with when none was chosen.
    var defaultVoice: String {
        switch self {
        case .phonon: "default"
        case .pocket: "alba"
        }
    }

    /// Downloads the engine. `progress` gets the fraction downloaded, in steps of a hundredth, on the main actor.
    func install(progress: @escaping @MainActor (Double) -> Void) async throws {
        switch self {
        case .phonon: try await PhononVoice.install(progress: progress)
        case .pocket: try await PocketVoice.install(progress: progress)
        }
    }

    func load() async throws -> any Speech {
        switch self {
        case .phonon: try await PhononVoice.load()
        case .pocket: try await PocketVoice.load()
        }
    }
}

extension Engine {
    /// "Default" for a model's default voice; otherwise the voice's name, capitalized as a name.
    static func title(_ name: String) -> String {
        name == "default" ? "Default" : name.prefix(1).uppercased() + name.dropFirst()
    }
}
