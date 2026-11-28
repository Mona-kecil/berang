import SwiftUI

/// Every voice of every engine in one list, yours first. Pressing a row chooses the voice if its engine is on this
/// Mac, or selects it, with its download in the row, if not. A row's play button speaks a sample line with an
/// installed voice, so you hear how Berang says numbers and names, or plays a recorded clip of one you don't have.
struct VoicesPage: View {
    let player: Player
    let back: () -> Void

    @State private var search = ""
    /// Voices on disk per engine, re-read while an engine downloads.
    @State private var installed = Self.installedVoices()
    /// A voice of an engine not yet downloaded, last selected.
    @State private var considered: Voice?
    /// The installed voice whose sample was last started.
    @State private var sampled: Voice?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Voice: Hashable {
        let engine: Engine
        let name: String
        var profile: VoiceProfile? { engine.profile(name) }
        var title: String { Engine.title(name) }
    }

    /// A line that tests what voices often get wrong, which Berang cleans up before speaking it.
    static let sample = "Dr. Rivera's flight leaves at 7:45 on March 3rd, from gate B12."

    private var hasInstalledEngine: Bool { Engine.allCases.contains(where: \.isInstalled) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "Voices", back: back)
            searchField
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups, id: \.title) { group in
                            SectionLabel(group.title).padding(.top, 16).padding(.bottom, 4).padding(.leading, 4)
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
                    .padding(.horizontal, 2).padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .mask(fade)
                .onAppear { scroller.scrollTo(considered ?? Voice(engine: player.engine, name: player.voice), anchor: .center) }
            }
        }
        .onDisappear {
            player.stopPreview()
            if sampleSpoken { player.stop() }
        }
        .onChange(of: sampleSpoken) { was, now in if was && !now { sampled = nil } }
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

    private var searchField: some View {
        TextField("", text: $search)
            .textFieldStyle(.plain)
            .font(Otter.font(14, .bold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .raised(12, depth: 3)
            .accessibilityLabel("Search voices")
            .overlay(alignment: .leading) {
                if search.isEmpty {
                    Text("Search: deep, british, female…").font(Otter.font(14, .bold)).foregroundStyle(Otter.soft.opacity(0.7))
                        .padding(.leading, 14).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .overlay(alignment: .trailing) {
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(Otter.soft)
                            .padding(.trailing, 10)
                    }
                    .buttonStyle(PlainButtonStyle(radius: 6))
                    .accessibilityLabel("Clear search")
                }
            }
    }

    /// Lets the list fade out under the search box and at the window's foot instead of cutting off.
    private var fade: some View {
        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.02),
                               .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                       startPoint: .top, endPoint: .bottom)
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
            let text = [voice.title, p?.group, p?.style, p?.gender?.rawValue, voice.engine.title]
                .compactMap { $0?.lowercased() }.joined(separator: " ")
            return words.allSatisfy { text.contains($0) }
        }
    }

    private static let order = ["American", "British", "Scottish", "Canadian", "Characters"]

    /// The voices on this Mac, then the rest by accent; those with no known accent come last.
    private var groups: [(title: String, voices: [Voice])] {
        let mine = matching.filter { $0.engine.isInstalled }.sorted { $0.title < $1.title }
        let byGroup = Dictionary(grouping: matching.filter { !$0.engine.isInstalled }) { $0.profile?.group ?? "More voices" }
        let rest = byGroup.keys.sorted { a, b in
            (Self.order.firstIndex(of: a) ?? Self.order.count) < (Self.order.firstIndex(of: b) ?? Self.order.count)
        }.map { ($0, byGroup[$0]!.sorted { $0.title < $1.title }) }
        return (mine.isEmpty ? [] : [("On this Mac", mine)]) + rest
    }

    private func isCurrent(_ voice: Voice) -> Bool {
        voice.engine == player.engine && voice.name == player.voice && voice.engine.isInstalled
    }

    private func isSelected(_ voice: Voice) -> Bool {
        considered.map { $0 == voice } ?? (voice.engine == player.engine && voice.name == player.voice)
    }

    private var sampleSpoken: Bool {
        sampled != nil && player.isReadingVoicesText && (player.state == .playing || player.state == .paused)
    }

    private func isHearing(_ voice: Voice) -> Bool {
        if voice.engine.isInstalled { return sampled == voice && (sampleSpoken || player.state == .loading) }
        return player.previewing == Player.PreviewVoice(engine: voice.engine, name: voice.name)
    }

    private func row(_ voice: Voice) -> some View {
        let on = isSelected(voice)
        let hearing = isHearing(voice)
        let summary = voice.profile?.summary ?? ""
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Button { hear(voice) } label: {
                    Image(systemName: hearing ? "waveform" : "play.fill")
                        .font(.system(size: hearing ? 12 : 9, weight: .bold))
                        .foregroundStyle(hearing ? .white : Otter.teal)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(hearing ? Otter.orange : on ? Otter.mint : Otter.card))
                        .background(Circle().fill(hearing ? Otter.orangeEdge : on ? .clear : Otter.edge).offset(y: 2))
                }
                .buttonStyle(PlainButtonStyle(radius: 13))
                .accessibilityLabel(hearing ? "Stop" : "Hear \(voice.title)")
                Button { select(voice) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(voice.title).font(Otter.font(14, .heavy)).foregroundStyle(Otter.ink).fixedSize()
                        Text(summary).font(Otter.font(12.5, .bold)).foregroundStyle(Otter.soft).lineLimit(1)
                        Spacer(minLength: 0)
                        if isCurrent(voice) {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Otter.teal)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle(radius: 8))
                .accessibilityLabel("\(voice.title), \(summary.nonEmpty ?? voice.engine.title)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            .padding(.leading, 5).padding(.trailing, 10).padding(.vertical, 4)
            if hearing, voice.engine.isInstalled {
                Text(Self.sample).font(Otter.font(12.5, .bold)).foregroundStyle(Otter.ink)
                    .padding(.leading, 40).padding(.trailing, 12).padding(.bottom, 11)
                    .transition(.opacity)
            } else if on, !voice.engine.isInstalled {
                download(voice).padding(.leading, 40).padding(.trailing, 12).padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .background {
            if on { Color.clear.raised(14, depth: 3) }
        }
        .padding(.vertical, on ? 4 : 0)
    }

    private func select(_ voice: Voice) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.2)) {
            if voice.engine.isInstalled {
                considered = nil
                player.choose(voice.engine, voice.name)
            } else {
                considered = voice
            }
        }
        if !voice.engine.isInstalled { player.preview(voice.engine, voice.name) }
    }

    /// An installed voice speaks the sample, and becomes the voice, since reading starts from the chosen one.
    private func hear(_ voice: Voice) {
        if isHearing(voice) {
            if voice.engine.isInstalled { player.stop() } else { player.stopPreview() }
            sampled = nil
        } else if voice.engine.isInstalled {
            considered = nil
            sampled = voice
            player.choose(voice.engine, voice.name)
            player.readText(Self.sample)
        } else {
            select(voice)
        }
    }

    private func download(_ voice: Voice) -> some View {
        let more = all.filter { $0.engine == voice.engine }.count - 1
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(more > 0 ? "\(megabytes(voice.engine.size)) MB, with \(more) more voices" : "\(megabytes(voice.engine.size)) MB")
                    .font(Otter.font(12.5, .bold)).foregroundStyle(Otter.soft)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if player.downloading == voice.engine, let fraction = player.download {
                    HStack(spacing: 8) {
                        ProgressView(value: fraction).tint(Otter.orange).frame(width: 68)
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(Otter.font(12, .heavy)).monospacedDigit().foregroundStyle(Otter.orange)
                    }
                } else {
                    let failed = player.downloadError?.engine == voice.engine
                    Button(failed ? "Retry" : "Download") {
                        player.downloadVoice(voice.engine, then: voice.name)
                    }
                    .buttonStyle(ChunkyButtonStyle(compact: true))
                    .disabled(player.state == .downloading || player.state == .loading)
                }
            }
            if let failure = player.downloadError, failure.engine == voice.engine, player.downloading == nil {
                Text(failure.message).font(Otter.font(12, .medium)).foregroundStyle(Otter.alert)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
