import SwiftUI

/// Every voice of every engine, to find, hear and choose. Selecting one plays its recorded clip at once. A voice of a
/// downloaded engine also becomes the voice; another plays its clip, and its engine's Download then switches to it.
/// Below, Read reads a sample text, or your own, with the chosen voice.
struct VoicesPage: View {
    let player: Player
    let back: () -> Void

    @State private var search = ""
    @State private var filter = Filter.all
    /// Voices on disk per engine, re-read while an engine downloads.
    @State private var installed = Self.installedVoices()
    /// A voice of an engine not yet downloaded, last previewed.
    @State private var considered: Voice?
    @State private var words = Self.samples[0].text
    @State private var sample = Self.samples[0].name

    struct Voice: Hashable {
        let engine: Engine
        let name: String
        var profile: VoiceProfile? { engine.profile(name) }
        var title: String { Engine.title(name) }
    }

    enum Filter: String, CaseIterable { case all = "All", female = "Female", male = "Male", characters = "Characters", mine = "On this Mac" }

    /// Texts that test what voices often get wrong. Each fills the box, to edit or replace.
    static let samples: [(name: String, text: String)] = [
        ("Everyday", "Dr. Rivera's flight leaves at 7:45 on March 3rd, from gate B12. Is it really $1,299 for two nights? She laughed and said, \"Book it anyway.\""),
        ("Numbers", "Order #48213 ships on 12/03/2026. The total is $2,450.75, about 18% less than last year. Call 1-800-555-0199 before 5:30 PM. The parcel weighs 2.5 kg, about 5.5 lbs."),
        ("Addresses and links", "Send it to 221B Baker Street, London NW1 6XE. The guide is at https://docs.example.com/v2/setup, and questions go to help@example.com."),
        ("Dialogue", "\"Are you coming?\" she asked.\n\nHe paused at the door. \"Only if you promise not to sing.\"\n\n\"No promises,\" she said, grinning."),
        ("News", "The city council voted 7 to 2 on Tuesday to extend the night bus service through March. Officials said ridership rose 23 percent after the trial began in October."),
        ("Technical", "Run npm install, then open localhost:3000. If the build fails with error E404, check that NODE_ENV is set to production and that config.json is valid."),
        ("Story", "The lighthouse keeper climbed the stairs every evening. She trimmed the wick, wound the clockwork, and watched the beam sweep across the dark water, counting the ships."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageHeader(title: "Voices", back: back)
            TextField("Search: deep, british, female…", text: $search)
                .textFieldStyle(.plain)
                .font(Otter.font(13))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Otter.card)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Otter.edge, lineWidth: 2)))
            HStack(spacing: 6) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Button(f.rawValue) { filter = f }.buttonStyle(ChipStyle(on: filter == f))
                }
            }
            ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(groups, id: \.title) { group in
                        SectionLabel(group.title).padding(.top, 8).padding(.leading, 6)
                        ForEach(group.voices, id: \.self) { row($0).id($0) }
                    }
                    if groups.isEmpty {
                        VStack(spacing: 6) {
                            OtterImage(pose: .peeking, size: 90)
                            Text("No voice matches").font(Otter.font(13)).foregroundStyle(Otter.soft)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 20)
                    }
                }
                .padding(.bottom, 6)
            }
            .onAppear { scroller.scrollTo(Voice(engine: player.engine, name: player.voice), anchor: .center) }
            }
            if let considered, !considered.engine.isInstalled { download(considered) }
            tryIt
        }
        .task {
            // An engine's voices appear once it finishes downloading.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let now = Self.installedVoices()
                if now != installed { installed = now }
                if let engine = considered?.engine, engine.isInstalled { considered = nil }
            }
        }
    }

    private static func installedVoices() -> [Engine: [String]] {
        Dictionary(uniqueKeysWithValues: Engine.allCases.map { ($0, $0.voices) })
    }

    private var all: [Voice] {
        Engine.allCases.flatMap { engine in
            let names = installed[engine].flatMap { $0.isEmpty ? nil : $0 } ?? engine.previewVoices
            return names.map { Voice(engine: engine, name: $0) }
        }
    }

    private var matching: [Voice] {
        let words = search.lowercased().split(separator: " ").map(String.init)
        return all.filter { voice in
            let p = voice.profile
            switch filter {
            case .all: break
            case .female: if p?.gender != .female { return false }
            case .male: if p?.gender != .male { return false }
            case .characters: if p?.group != "Characters" { return false }
            case .mine: if !voice.engine.isInstalled { return false }
            }
            let text = [voice.title, p?.group, p?.style, p?.gender?.rawValue, voice.engine.title]
                .compactMap { $0?.lowercased() }.joined(separator: " ")
            return words.allSatisfy { text.contains($0) }
        }
    }

    private static let order = ["American", "British", "Scottish", "Canadian", "Characters"]

    /// The voices by accent; those with no known accent come last.
    private var groups: [(title: String, voices: [Voice])] {
        let byGroup = Dictionary(grouping: matching) { $0.profile?.group ?? "More voices" }
        return byGroup.keys.sorted { a, b in
            (Self.order.firstIndex(of: a) ?? Self.order.count) < (Self.order.firstIndex(of: b) ?? Self.order.count)
        }.map { ($0, byGroup[$0]!.sorted { $0.title < $1.title }) }
    }

    private func isSelected(_ voice: Voice) -> Bool {
        considered.map { $0 == voice } ?? (voice.engine == player.engine && voice.name == player.voice)
    }

    private func row(_ voice: Voice) -> some View {
        let on = isSelected(voice)
        return Button { select(voice) } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "speaker.wave.2.fill" : "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(on ? .white : Otter.teal)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(on ? Otter.orange : Otter.card))
                    .background(Circle().fill(on ? Otter.orangeEdge : Otter.edge).offset(y: 2))
                Text(voice.title).font(Otter.font(13, .bold)).foregroundStyle(Otter.ink)
                Spacer(minLength: 8)
                if !voice.engine.isInstalled {
                    Text("↓ \(megabytes(voice.engine.size)) MB").font(Otter.font(10.5, .heavy)).foregroundStyle(Otter.soft)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Otter.edge.opacity(0.5)))
                } else if let summary = voice.profile?.summary, !summary.isEmpty {
                    Text(summary).font(Otter.font(11.5, .medium)).foregroundStyle(Otter.soft).lineLimit(1)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Otter.card : .clear)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Otter.edge : .clear).offset(y: 3)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle(radius: 12))
        .accessibilityLabel("\(voice.title), \(voice.profile?.summary ?? voice.engine.title)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func select(_ voice: Voice) {
        if voice.engine.isInstalled {
            considered = nil
            player.choose(voice.engine, voice.name)
        } else {
            considered = voice
            player.preview(voice.engine, voice.name)
        }
    }

    private func download(_ voice: Voice) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(voice.title) needs \(voice.engine.title)").font(Otter.font(13, .bold)).foregroundStyle(Otter.ink)
                Text("One download, \(megabytes(voice.engine.size)) MB").font(Otter.font(11.5, .medium)).foregroundStyle(Otter.soft)
            }
            Spacer()
            if player.downloading == voice.engine, let fraction = player.download {
                ProgressView(value: fraction).tint(Otter.orange).frame(width: 90)
            } else {
                Button("Download") { player.downloadVoice(voice.engine, then: voice.name) }
                    .buttonStyle(ChunkyButtonStyle(compact: true))
                    .disabled(player.state == .downloading || player.state == .loading)
            }
        }
        .card()
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $words)
                .font(Otter.font(12.5, .medium))
                .foregroundStyle(Otter.ink)
                .scrollContentBackground(.hidden)
                .frame(height: 54)
                .accessibilityLabel("Text to read")
            HStack {
                Menu(sample) {
                    ForEach(Self.samples, id: \.name) { s in
                        Button(s.name) { sample = s.name; words = s.text }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(Otter.font(12, .bold))
                .accessibilityLabel("Sample text")
                Spacer()
                Button("Read with \(Engine.title(player.voice))") { player.readText(words) }
                    .buttonStyle(ChunkyButtonStyle(compact: true))
                    .disabled(!player.engine.isInstalled || words.allSatisfy(\.isWhitespace))
            }
        }
        .card(padding: 10)
    }
}

/// A rounded filter chip, teal when chosen.
struct ChipStyle: ButtonStyle {
    let on: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Otter.font(11.5, .bold))
            .foregroundStyle(on ? .white : Otter.ink)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .raised(in: Capsule(), face: on ? Otter.teal : Otter.card, edge: on ? Otter.teal.opacity(0.6) : Otter.edge)
            .environment(\.sunk, configuration.isPressed)
            .fixedSize()
            .focusRing(12)
            .dimmedWhenDisabled()
    }
}

/// A page's title, with a back button on pages below Home.
struct PageHeader: View {
    let title: String
    var back: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 0) {
            if let back {
                // The padding makes the arrow easier to hit and keeps the title where it was.
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .heavy))
                        .padding(.vertical, 6).padding(.trailing, 6)
                }
                .buttonStyle(PlainButtonStyle(radius: 6)).foregroundStyle(Otter.ink).accessibilityLabel("Back")
                .keyboardShortcut("[", modifiers: .command)
            }
            Text(title).font(Otter.font(21, .heavy)).foregroundStyle(Otter.ink)
            Spacer()
        }
    }
}
