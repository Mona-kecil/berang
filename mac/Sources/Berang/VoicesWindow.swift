import AppKit
import SwiftUI

/// Every voice of every engine, to hear and choose. Selecting one plays its recorded clip, so the arrow keys walk
/// through them. A voice of a downloaded engine also becomes the voice, and Read reads your own text with it; the
/// Download button of any other voice's engine switches to that voice once downloaded.
final class VoicesWindow: NSWindow {
    init(player: Player) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 680), styleMask: [.titled, .closable, .resizable],
                   backing: .buffered, defer: false)
        title = "Voices"
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: VoicesView(player: player))
        center()
    }

    func show() {
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }
}

struct VoicesView: View {
    let player: Player

    init(player: Player) {
        self.player = player
        _tab = State(initialValue: player.engine)
    }
    @State private var voices = Self.installed()
    /// The engine whose voices show, the one reading at first.
    @State private var tab: Engine
    /// A voice of an engine not yet downloaded, last previewed.
    @State private var considered: (engine: Engine, name: String)?
    /// Your own words to hear the chosen voice read, starting from a sample.
    @State private var words = Self.samples[0].text
    @State private var sample = Self.samples[0].name

    /// Texts that test what voices often get wrong. Each fills the box, to edit or replace.
    private static let samples: [(name: String, text: String)] = [
        ("Everyday", "Dr. Rivera's flight leaves at 7:45 on March 3rd, from gate B12. Is it really $1,299 for two nights? She laughed and said, \"Book it anyway.\""),
        ("Numbers", "Order #48213 ships on 12/03/2026. The total is $2,450.75, about 18% less than last year. Call 1-800-555-0199 before 5:30 PM. The parcel weighs 2.5 kg, about 5.5 lbs."),
        ("Addresses and links", "Send it to 221B Baker Street, London NW1 6XE. The guide is at https://docs.example.com/v2/setup, and questions go to help@example.com."),
        ("Dialogue", "\"Are you coming?\" she asked.\n\nHe paused at the door. \"Only if you promise not to sing.\"\n\n\"No promises,\" she said, grinning."),
        ("News", "The city council voted 7 to 2 on Tuesday to extend the night bus service through March. Officials said ridership rose 23 percent after the trial began in October."),
        ("Technical", "Run npm install, then open localhost:3000. If the build fails with error E404, check that NODE_ENV is set to production and that config.json is valid."),
        ("Story", "The lighthouse keeper climbed the stairs every evening. She trimmed the wick, wound the clockwork, and watched the beam sweep across the dark water, counting the ships."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Engine", selection: $tab) {
                ForEach(Engine.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            let installed = voices[tab] ?? []
            List(selection: Binding(get: { selected }, set: { select($0) })) {
                ForEach(groups(installed.isEmpty ? tab.previewVoices : installed), id: \.title) { group in
                    if let title = group.title {
                        Section(title) { rows(group.names) }
                    } else {
                        Section { rows(group.names) }
                    }
                }
            }
            Divider()
            VStack(alignment: .trailing, spacing: 8) {
                TextEditor(text: $words)
                    .font(.body)
                    .frame(height: 72)
                    .accessibilityLabel("Text to read")
                HStack {
                    Picker("Sample text", selection: $sample) {
                        ForEach(Self.samples, id: \.name) { Text($0.name).tag($0.name) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: sample) { _, name in
                        if let text = Self.samples.first(where: { $0.name == name })?.text { words = text }
                    }
                    Spacer()
                    Button("Read with \(Engine.title(player.voice))") { player.readText(words) }
                        .disabled(!player.engine.isInstalled || words.allSatisfy(\.isWhitespace))
                }
            }
            .padding(12)
            if installed.isEmpty {
                Divider()
                download(tab).padding(12)
            }
        }
        .frame(minWidth: 260, minHeight: 300)
        .task {
            // An engine's voices appear once it finishes downloading.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if voices.values.contains(where: \.isEmpty) {
                    voices = Self.installed()
                    if let engine = considered?.engine, voices[engine]?.isEmpty == false { considered = nil }
                }
            }
        }
    }

    private static let order = ["American", "British", "Scottish", "Canadian", "Characters"]

    /// The voices by accent, in their listed order: first those whose accent is unknown, under no heading.
    private func groups(_ names: [String]) -> [(title: String?, names: [String])] {
        let byGroup = Dictionary(grouping: names) { tab.profile($0)?.group }
        let titles = byGroup.keys.sorted { a, b in
            let i = a.map { Self.order.firstIndex(of: $0) ?? Self.order.count } ?? -1
            let j = b.map { Self.order.firstIndex(of: $0) ?? Self.order.count } ?? -1
            return i != j ? i < j : (a ?? "") < (b ?? "")
        }
        return titles.map { ($0, byGroup[$0] ?? []) }
    }

    private func rows(_ names: [String]) -> some View {
        ForEach(names, id: \.self) { name in
            HStack {
                Text(Engine.title(name))
                Spacer()
                Text(tab.profile(name)?.summary ?? "").foregroundStyle(.secondary)
            }
            .tag("\(tab.rawValue)/\(name)")
        }
    }

    private static func installed() -> [Engine: [String]] {
        Dictionary(uniqueKeysWithValues: Engine.allCases.map { ($0, $0.voices) })
    }

    private var selected: String {
        if let considered { return "\(considered.engine.rawValue)/\(considered.name)" }
        return "\(player.engine.rawValue)/\(player.voice)"
    }

    private func select(_ tag: String?) {
        guard let tag, let slash = tag.firstIndex(of: "/"), let engine = Engine(rawValue: String(tag[..<slash])) else { return }
        let name = String(tag[tag.index(after: slash)...])
        if engine.isInstalled {
            considered = nil
            player.choose(engine, name)
        } else {
            considered = (engine, name)
            player.preview(engine, name)
        }
    }

    @ViewBuilder private func download(_ engine: Engine) -> some View {
        HStack {
            Text("\(megabytes(engine.size)) MB").foregroundStyle(.secondary)
            Spacer()
            if player.downloading == engine, let fraction = player.download {
                ProgressView(value: fraction).frame(width: 100)
            } else {
                Button("Download") {
                    player.downloadVoice(engine, then: considered?.engine == engine ? considered?.name : nil)
                }
                    .disabled(player.state == .downloading || player.state == .loading)
            }
        }
    }
}
