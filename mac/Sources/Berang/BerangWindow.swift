import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Berang's one window: Home, with setup until Berang can read, and the Voices and Settings pages. It opens from the
/// menu bar, and at launch while setup isn't done.
final class BerangWindow: NSWindow {
    private let model = WindowModel()

    init(player: Player, shortcuts: Shortcuts, updater: Updater) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 640),
                   styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        title = "Berang"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        backgroundColor = NSColor(Otter.mint)
        contentView = NSHostingView(rootView: RootView(player: player, shortcuts: shortcuts, updater: updater, model: model))
        center()
    }

    /// Whether Berang can't read yet: it lacks Accessibility access or a voice.
    static var setupNeeded: Bool { !AXIsProcessTrusted() || !Engine.allCases.contains(where: \.isInstalled) }

    func show(_ page: WindowModel.Page = .home) {
        model.page = page
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }

    override func close() {
        model.shortcuts?.cancelRecording()
        super.close()
    }
}

@MainActor @Observable final class WindowModel {
    enum Page { case home, voices, settings }
    var page = Page.home
    @ObservationIgnored weak var shortcuts: Shortcuts?
}

struct RootView: View {
    let player: Player
    let shortcuts: Shortcuts
    let updater: Updater
    @Bindable var model: WindowModel

    var body: some View {
        Group {
            switch model.page {
            case .home: HomePage(player: player, shortcuts: shortcuts, go: go)
            case .voices: VoicesPage(player: player) { go(.home) }
            case .settings: SettingsPage(shortcuts: shortcuts, updater: updater) { go(.home) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 34)
        .padding(.bottom, 16)
        .frame(width: 380, height: 640, alignment: .top)
        .background(Otter.mint)
        .fontDesign(.rounded)
        .tint(Otter.teal)
        .onAppear { model.shortcuts = shortcuts }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in player.readFile(url) } }
            }
            return true
        }
    }

    private func go(_ page: WindowModel.Page) {
        shortcuts.cancelRecording()
        withAnimation(.snappy(duration: 0.2)) { model.page = page }
    }
}

// MARK: - Home

struct HomePage: View {
    let player: Player
    let shortcuts: Shortcuts
    let go: (WindowModel.Page) -> Void

    @State private var trusted = AXIsProcessTrusted()
    @State private var screen = CGPreflightScreenCaptureAccess()
    @State private var voice = Engine.allCases.contains(where: \.isInstalled)
    /// macOS shows each permission prompt once; after that, Allow opens System Settings instead.
    @State private var askedTrust = false
    @State private var askedScreen = false
    @State private var dropping = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !trusted || !voice {
                welcome
            } else {
                HStack {
                    Text("Berang").font(Otter.font(22, .heavy)).foregroundStyle(Otter.ink)
                    Spacer()
                    settingsButton
                }
                howTo
                dropZone
                voiceCard
                Spacer(minLength: 0)
                if !screen { screenTip } else { OtterImage(pose: .asleep, size: 120).frame(maxWidth: .infinity) }
            }
        }
        .task {
            while !Task.isCancelled {
                trusted = AXIsProcessTrusted()
                screen = CGPreflightScreenCaptureAccess()
                voice = Engine.allCases.contains(where: \.isInstalled)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var settingsButton: some View {
        Button { go(.settings) } label: {
            Image(systemName: "gearshape.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Otter.teal)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Otter.card)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Otter.edge).offset(y: 2)))
                .overlay(alignment: .topTrailing) {
                    if shortcuts.needsAttention { Circle().fill(Otter.orange).frame(width: 9, height: 9).offset(x: 3, y: -3) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shortcuts.needsAttention ? "Settings, a shortcut needs attention" : "Settings")
        .keyboardShortcut(",", modifiers: .command)
    }

    // First open: the otter says hello, and setup is a checklist.
    private var welcome: some View {
        VStack(spacing: 12) {
            OtterImage(pose: .floating, size: 150).padding(.top, 6)
            VStack(spacing: 3) {
                Text("Hi, I'm Berang").font(Otter.font(22, .heavy)).foregroundStyle(Otter.ink)
                Text("I read anything on your Mac out loud.").font(Otter.font(13, .medium)).foregroundStyle(Otter.soft)
            }
            VStack(spacing: 0) {
                check("Let me read other apps", done: trusted) {
                    Button("Allow", action: allowAccessibility).buttonStyle(ChunkyButtonStyle(compact: true))
                }
                Divider().overlay(Otter.edge)
                check("Pick my voice", done: voice) {
                    if let fraction = player.download {
                        ProgressView(value: fraction).tint(Otter.orange).frame(width: 80)
                    } else if trusted {
                        Button("Choose") { go(.voices) }.buttonStyle(ChunkyButtonStyle(compact: true))
                    } else {
                        Button("Choose") { go(.voices) }.buttonStyle(SoftButtonStyle())
                    }
                }
                Divider().overlay(Otter.edge)
                check("Read screen areas", note: "Optional", done: screen) {
                    Button("Allow", action: allowScreenRecording).buttonStyle(SoftButtonStyle())
                }
            }
            .card(padding: 12)
            if case .failed(let message) = player.state, !voice {
                Text(message).font(Otter.font(12, .medium)).foregroundStyle(Otter.alert)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func check(_ title: String, note: String? = nil, done: Bool, @ViewBuilder action: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(done ? Otter.teal : Otter.edge)
                .accessibilityLabel(done ? "Done" : "To do")
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Otter.font(13.5, .bold)).foregroundStyle(Otter.ink)
                if let note { Text(note).font(Otter.font(11, .medium)).foregroundStyle(Otter.soft) }
            }
            Spacer()
            if !done { action() }
        }
        .padding(.vertical, 8)
    }

    // Home: how to start reading in any app.
    private var howTo: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel("Read anything")
            VStack(spacing: 0) {
                shortcutRow(.page, title: "The page you're on", detail: "In any app, press")
                Divider().overlay(Otter.edge)
                shortcutRow(.area, title: "Part of the screen", detail: "Press, then drag over it")
            }
            .card(padding: 12)
        }
    }

    private func shortcutRow(_ action: ShortcutAction, title: String, detail: String) -> some View {
        let working = shortcuts.working.contains(action)
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Otter.font(13.5, .bold)).foregroundStyle(Otter.ink)
                Text(working ? detail : "This shortcut isn't working. Change it in Settings.")
                    .font(Otter.font(11.5, .medium)).foregroundStyle(working ? Otter.soft : Otter.alert)
            }
            Spacer()
            KeyCap(text: shortcuts.combos[action]!.display, tint: working ? nil : Otter.alert)
        }
        .padding(.vertical, 6)
    }

    private var dropZone: some View {
        VStack(spacing: 2) {
            Text("Drop a PDF or EPUB here").font(Otter.font(13.5, .bold)).foregroundStyle(Otter.ink)
            HStack(spacing: 3) {
                Text("or").foregroundStyle(Otter.soft)
                Button("choose a file", action: chooseFile).buttonStyle(.plain).foregroundStyle(Otter.teal)
            }
            .font(Otter.font(12, .bold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Otter.card.opacity(dropping ? 0.9 : 0.45))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(dropping ? Otter.orange : Otter.edge, style: StrokeStyle(lineWidth: 2.5, dash: [6, 5]))))
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in player.readFile(url) } }
            }
            return true
        }
    }

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel("Voice")
            Button { go(.voices) } label: {
                HStack(spacing: 10) {
                    Text(String(Engine.title(player.voice).prefix(2)))
                        .font(Otter.font(13, .heavy)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Circle().fill(Otter.teal))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Engine.title(player.voice)).font(Otter.font(14, .bold)).foregroundStyle(Otter.ink)
                        Text(player.engine.profile(player.voice)?.summary.nonEmpty ?? player.engine.title)
                            .font(Otter.font(11.5, .medium)).foregroundStyle(Otter.soft)
                    }
                    Spacer()
                    Text("Change").font(Otter.font(13, .heavy)).foregroundStyle(Otter.teal)
                }
                .card(padding: 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voice: \(Engine.title(player.voice)). Change")
        }
    }

    private var screenTip: some View {
        HStack(spacing: 8) {
            Text("Reading part of the screen needs Screen Recording.").font(Otter.font(11.5, .medium)).foregroundStyle(Otter.soft)
            Spacer()
            Button("Allow", action: allowScreenRecording).buttonStyle(SoftButtonStyle())
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .epub, .image, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        player.readFile(url)
    }

    private func allowAccessibility() {
        if askedTrust {
            openPrivacy("Privacy_Accessibility")
        } else {
            askedTrust = true
            trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }

    private func allowScreenRecording() {
        if askedScreen {
            openPrivacy("Privacy_ScreenCapture")
        } else {
            askedScreen = true
            screen = CGRequestScreenCaptureAccess()
        }
    }
}

func openPrivacy(_ pane: String) {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
}

func megabytes(_ bytes: Int64) -> Int64 { bytes / 1_000_000 }

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Settings

struct SettingsPage: View {
    let shortcuts: Shortcuts
    let updater: Updater
    let back: () -> Void
    @State private var daily = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: "Settings", back: back)
            VStack(alignment: .leading, spacing: 7) {
                SectionLabel("Shortcuts")
                VStack(spacing: 0) {
                    ForEach(Array(ShortcutAction.allCases.enumerated()), id: \.element) { i, action in
                        if i > 0 { Divider().overlay(Otter.edge) }
                        ShortcutRecorder(shortcuts: shortcuts, action: action)
                    }
                }
                .card(padding: 12)
            }
            VStack(alignment: .leading, spacing: 7) {
                SectionLabel("Updates")
                VStack(spacing: 0) {
                    Toggle(isOn: Binding(get: { daily }, set: { daily = $0; updater.checksDaily = $0 })) {
                        Text("Check every day").font(Otter.font(13.5, .bold)).foregroundStyle(Otter.ink)
                    }
                    .toggleStyle(.switch)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    Divider().overlay(Otter.edge)
                    HStack {
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                            .font(Otter.font(13.5, .bold)).foregroundStyle(Otter.ink)
                        Spacer()
                        Button(updater.waiting.map { "Update to \($0)" } ?? "Check now", action: updater.check)
                            .buttonStyle(SoftButtonStyle())
                    }
                    .padding(.vertical, 8)
                }
                .card(padding: 12)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Quit Berang") { NSApp.terminate(nil) }.buttonStyle(SoftButtonStyle())
            }
        }
        .onAppear { daily = updater.checksDaily }
    }
}

/// A shortcut, and changing it: click, then press the new keys. Esc cancels.
struct ShortcutRecorder: View {
    let shortcuts: Shortcuts
    let action: ShortcutAction
    @State private var monitor: Any?

    var body: some View {
        let recording = shortcuts.recording == action
        let working = shortcuts.working.contains(action)
        let note = shortcuts.notes[action]
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title).font(Otter.font(13.5, .bold)).foregroundStyle(Otter.ink)
                if recording {
                    Text(note ?? "Press the new keys. Esc cancels.").font(Otter.font(11.5, .medium))
                        .foregroundStyle(note == nil ? Otter.soft : Otter.alert)
                } else if let note {
                    Text(note).font(Otter.font(11.5, .medium)).foregroundStyle(Otter.alert)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { shortcuts.startRecording(action) } label: {
                KeyCap(text: recording ? "…" : shortcuts.combos[action]!.display,
                       tint: recording ? Otter.orange : working ? nil : Otter.alert)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(action.title): \(shortcuts.combos[action]!.display). Change")
        }
        .padding(.vertical, 8)
        .onChange(of: recording) { _, now in now ? listen() : stopListening() }
        .onDisappear(perform: stopListening)
    }

    private func listen() {
        stopListening()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard shortcuts.recording == action else { return event }
            let combo = Shortcuts.combo(event)
            if combo.modifiers == 0, event.keyCode == 53 { shortcuts.cancelRecording() } else { shortcuts.offer(combo) }
            return nil
        }
    }

    private func stopListening() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
