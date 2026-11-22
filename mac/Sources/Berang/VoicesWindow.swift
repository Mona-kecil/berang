import AppKit
import SwiftUI

/// Every voice of every engine, to hear and choose. Choosing one plays a sample in it, so the arrow keys walk
/// through them. An engine not yet downloaded offers its download.
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
    @State private var voices = Self.installed()

    var body: some View {
        List(selection: Binding(get: { "\(player.engine.rawValue)/\(player.voice)" }, set: { choose($0) })) {
            ForEach(Engine.allCases, id: \.self) { engine in
                Section(engine.title) {
                    let names = voices[engine] ?? []
                    if names.isEmpty {
                        download(engine)
                    } else {
                        ForEach(names, id: \.self) { name in
                            Text(Engine.title(name)).tag("\(engine.rawValue)/\(name)")
                        }
                    }
                }
            }
        }
        .frame(minWidth: 260, minHeight: 300)
        .task {
            // An engine's voices appear once it finishes downloading.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if voices.values.contains(where: \.isEmpty) { voices = Self.installed() }
            }
        }
    }

    private static func installed() -> [Engine: [String]] {
        Dictionary(uniqueKeysWithValues: Engine.allCases.map { ($0, $0.voices) })
    }

    private func choose(_ tag: String?) {
        guard let tag, let slash = tag.firstIndex(of: "/"), let engine = Engine(rawValue: String(tag[..<slash])) else { return }
        player.choose(engine, String(tag[tag.index(after: slash)...]))
    }

    @ViewBuilder private func download(_ engine: Engine) -> some View {
        HStack {
            Text("\(megabytes(engine.size)) MB").foregroundStyle(.secondary)
            Spacer()
            if player.downloading == engine, let fraction = player.download {
                ProgressView(value: fraction).frame(width: 100)
            } else {
                Button("Download") { player.downloadVoice(engine) }
                    .disabled(player.state == .downloading || player.state == .loading)
            }
        }
    }
}
