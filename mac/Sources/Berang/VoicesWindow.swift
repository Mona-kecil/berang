import AppKit
import SwiftUI

/// Every voice, to hear and choose. Choosing one plays a sample in it, so the arrow keys walk through them.
final class VoicesWindow: NSWindow {
    init(player: Player) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 520), styleMask: [.titled, .closable, .resizable],
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
    @State private var names = Voice.names

    var body: some View {
        Group {
            if names.isEmpty {
                ContentUnavailableView {
                    Label("No Voice Yet", systemImage: "waveform")
                } actions: {
                    if let fraction = player.download {
                        ProgressView(value: fraction).frame(width: 160)
                    } else {
                        Button("Download Voice (137 MB)", action: player.downloadVoice)
                    }
                }
            } else {
                List(selection: Binding(get: { player.voice }, set: { if let name = $0 { player.choose(name) } })) {
                    ForEach(names, id: \.self) { name in
                        Text(Voice.title(name)).tag(name)
                    }
                }
            }
        }
        .frame(minWidth: 260, minHeight: 300)
        .task {
            // The list appears once the voice finishes downloading.
            while !Task.isCancelled, names.isEmpty {
                try? await Task.sleep(for: .seconds(1))
                names = Voice.names
            }
        }
    }
}

extension Voice {
    /// "Default" for the model's default voice, and otherwise the voice's name.
    static func title(_ name: String) -> String { name == "default" ? "Default" : name }
}
