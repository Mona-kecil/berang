import AppKit
import SwiftUI

/// Every voice of every engine, to hear and choose. Selecting one plays it, so the arrow keys walk through them:
/// a voice of a downloaded engine becomes the voice and speaks a sample; any other plays its recorded preview, and
/// its engine's Download button then reads with it.
final class VoicesWindow: NSWindow {
    init(player: Player) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 560), styleMask: [.titled, .closable, .resizable],
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
                ForEach(installed.isEmpty ? tab.previewVoices : installed, id: \.self) { name in
                    Text(Engine.title(name)).tag("\(tab.rawValue)/\(name)")
                }
            }
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
