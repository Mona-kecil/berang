import AppKit
import ServiceManagement
import SwiftUI
import TextGrab
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
        makeFirstResponder(nil)  // nothing looks chosen until you press Tab
    }

    override func close() {
        model.shortcuts?.cancelRecording()
        super.close()
    }
}

@MainActor @Observable final class WindowModel {
    enum Page { case home, voices, settings }
    var page = Page.home
    /// macOS shows each permission prompt once; kept on the window model so navigating pages doesn't reset it.
    var askedTrust = false
    var askedScreen = false
    /// Stays false while the user finishes first-time setup, so the checklist doesn't snap away mid-click.
    var setupDismissed = !BerangWindow.setupNeeded
    @ObservationIgnored weak var shortcuts: Shortcuts?
}

struct RootView: View {
    let player: Player
    let shortcuts: Shortcuts
    let updater: Updater
    @Bindable var model: WindowModel
    @State private var dropping = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch model.page {
            case .home: HomePage(player: player, shortcuts: shortcuts, model: model, go: go)
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
        .overlay {
            if dropping {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Otter.orange.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Otter.orange, style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
                        }
                        .padding(8)
                    Text("Drop to open")
                        .font(Otter.font(13, .heavy))
                        .foregroundStyle(Otter.ink)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .raised(18, face: Otter.card, edge: Otter.orange, depth: 2, stroke: Otter.orange, lineWidth: 2)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.14), value: dropping)
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    Task { @MainActor in
                        player.stageFile(url)
                        if model.page != .home { go(.home) }
                    }
                }
            }
            return true
        }
    }

    private func go(_ page: WindowModel.Page) {
        shortcuts.cancelRecording()
        player.stopPreview()
        let anim: Animation? = reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.2)
        withAnimation(anim) { model.page = page }
    }
}

// MARK: - Home

struct HomePage: View {
    let player: Player
    let shortcuts: Shortcuts
    @Bindable var model: WindowModel
    let go: (WindowModel.Page) -> Void

    @State private var trusted = AXIsProcessTrusted()
    @State private var screen = CGPreflightScreenCaptureAccess()
    @State private var voice = Engine.allCases.contains(where: \.isInstalled)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var readyToRead: Bool { trusted && voice }
    private var hasPendingFile: Bool { player.staged != nil || player.stagingTitle != nil || player.fileError != nil }
    private var showingWelcome: Bool { !readyToRead || !model.setupDismissed }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showingWelcome {
                welcome
            } else {
                home
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.22), value: showingWelcome)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.2), value: player.staged != nil)
        .task {
            while !Task.isCancelled {
                trusted = AXIsProcessTrusted()
                screen = CGPreflightScreenCaptureAccess()
                voice = Engine.allCases.contains(where: \.isInstalled)
                if !trusted || !voice { model.setupDismissed = false }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var settingsButton: some View {
        Button { go(.settings) } label: {
            Image(systemName: "gearshape.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Otter.teal)
                .frame(width: 30, height: 30)
                .overlay(alignment: .topTrailing) {
                    if shortcuts.needsAttention { Circle().fill(Otter.orange).frame(width: 9, height: 9).offset(x: 3, y: -3) }
                }
                .raised(10)
        }
        .buttonStyle(KeyButtonStyle(radius: 10))
        .accessibilityLabel(shortcuts.needsAttention ? "Settings, a shortcut needs attention" : "Settings")
        .keyboardShortcut(",", modifiers: .command)
    }

    // First open: the otter says hello, and setup is a checklist.
    private var welcome: some View {
        VStack(spacing: 12) {
            OtterImage(pose: .floating, size: 144).padding(.top, 6)
            VStack(spacing: 3) {
                Text(readyToRead ? "You're all set!" : "Hi, I'm Berang")
                    .font(Otter.font(22, .heavy)).foregroundStyle(Otter.ink)
                if readyToRead {
                    (Text("Press ") + keys(.page) + Text(" in any app to hear it read."))
                        .font(Otter.font(13, .medium)).foregroundStyle(Otter.soft)
                } else {
                    Text("I read anything on your Mac out loud.")
                        .font(Otter.font(13, .medium)).foregroundStyle(Otter.soft)
                }
            }
            .multilineTextAlignment(.center)
            VStack(spacing: 0) {
                check("Let me read other apps", done: trusted) {
                    Button("Allow", action: allowAccessibility).buttonStyle(ChunkyButtonStyle(compact: true))
                }
                Divider().overlay(Otter.edge)
                check("Pick my voice", done: voice) {
                    if let fraction = player.download {
                        HStack(spacing: 6) {
                            ProgressView(value: fraction).tint(Otter.orange).frame(width: 64)
                            Text("\(Int((fraction * 100).rounded()))%")
                                .font(Otter.font(11, .heavy)).monospacedDigit().foregroundStyle(Otter.orange)
                        }
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
            // Files need a voice, not Accessibility, so a dropped file stays usable even during setup.
            if let staged = player.staged {
                stagedFileCard(staged, canRead: voice)
            } else if let title = player.stagingTitle {
                stagingLoadingCard(title)
            } else if let error = player.fileError {
                Text(error).font(Otter.font(12, .medium)).foregroundStyle(Otter.alert).multilineTextAlignment(.center)
            } else if let failure = player.downloadError, !voice {
                Text(failure.message).font(Otter.font(12, .medium)).foregroundStyle(Otter.alert)
                    .multilineTextAlignment(.center)
            } else if case .failed(let message) = player.state, !voice {
                Text(message).font(Otter.font(12, .medium)).foregroundStyle(Otter.alert)
                    .multilineTextAlignment(.center)
            }
            if readyToRead, !hasPendingFile {
                Button("Start using Berang") {
                    let anim: Animation? = reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.22)
                    withAnimation(anim) { model.setupDismissed = true }
                }
                .buttonStyle(ChunkyButtonStyle())
                .padding(.top, 4)
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

    // Home: the one shortcut that reads any app, a file, and the voice.
    private var home: some View {
        VStack(spacing: 0) {
            HStack { Spacer(); settingsButton }
            Spacer(minLength: 0)
            if let staged = player.staged {
                stagedFileCard(staged, canRead: true)
            } else if let title = player.stagingTitle {
                stagingLoadingCard(title)
            } else {
                idleCenter
            }
            Spacer(minLength: 0)
            if !screen { screenTip.padding(.bottom, 12) }
            voiceCard
        }
    }

    private var idleCenter: some View {
        VStack(spacing: 4) {
            OtterImage(pose: player.state == .playing ? .floating : .asleep, size: 128).padding(.bottom, 10)
            (Text("Press ") + keys(.page) + Text(" in any app")).font(Otter.font(18, .bold)).foregroundStyle(Otter.ink)
            if let broken = [ShortcutAction.page, .area].first(where: { !shortcuts.working.contains($0) }) {
                HStack(spacing: 8) {
                    Text("\(shortcuts.combos[broken]!.display) isn't working.").foregroundStyle(Otter.alert)
                    Button("Change it") { go(.settings) }.buttonStyle(SoftButtonStyle())
                }
                .font(Otter.font(12, .semibold))
                .padding(.top, 2)
            } else {
                (Text("or ") + keys(.area) + Text(" for part of the screen")).font(Otter.font(12, .medium)).foregroundStyle(Otter.soft)
            }
            VStack(spacing: 7) {
                Button("Choose a File…", action: chooseFile).buttonStyle(ChunkyButtonStyle())
                Text("or drop one on this window").font(Otter.font(12, .medium)).foregroundStyle(Otter.soft)
                if let error = player.fileError {
                    Text(error)
                        .font(Otter.font(11.5, .semibold))
                        .foregroundStyle(Otter.alert)
                        .padding(.top, 2)
                }
            }
            .padding(.top, 22)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func stagingLoadingCard(_ title: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Opening \(title)…").font(Otter.font(13.5, .bold)).foregroundStyle(Otter.ink).lineLimit(1)
            Spacer()
            Button { player.clearStaged() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Otter.soft)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(PlainButtonStyle(radius: 8))
            .accessibilityLabel("Cancel")
        }
        .card(padding: 14)
    }

    /// Slim confirmation card for a dropped or chosen file (Model/Player.tla, StageOnDrop).
    private func stagedFileCard(_ file: Player.StagedFile, canRead: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.title).font(Otter.font(15, .heavy)).foregroundStyle(Otter.ink).lineLimit(2)
                    if file.resumed {
                        Text("Resume at \(file.percent)%")
                            .font(Otter.font(12, .bold)).monospacedDigit().foregroundStyle(Otter.teal)
                    }
                }
                Spacer(minLength: 4)
                Button { player.clearStaged() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Otter.soft)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(PlainButtonStyle(radius: 8))
                .accessibilityLabel("Close file")
            }
            if !canRead {
                Text("Pick a voice above to read this file.").font(Otter.font(11.5, .medium)).foregroundStyle(Otter.soft)
            }
            HStack(spacing: 8) {
                Button {
                    player.readStaged(fromStart: false)
                } label: {
                    Label(file.resumed ? "Resume" : "Read aloud", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ChunkyButtonStyle(compact: true))
                .disabled(!canRead)
                if file.resumed {
                    Button("Start over") { player.readStaged(fromStart: true) }
                        .buttonStyle(SoftButtonStyle())
                        .disabled(!canRead)
                }
            }
        }
        .card(padding: 14)
    }

    /// A shortcut inside a sentence, in teal, or in red while it isn't working.
    private func keys(_ action: ShortcutAction) -> Text {
        Text(shortcuts.combos[action]!.display).fontWeight(.heavy)
            .foregroundStyle(shortcuts.working.contains(action) ? Otter.teal : Otter.alert)
    }

    private var voiceCard: some View {
        Button { go(.voices) } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform").font(.system(size: 16, weight: .semibold)).foregroundStyle(Otter.teal)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Engine.title(player.voice)).font(Otter.font(14, .bold)).foregroundStyle(Otter.ink)
                    Text(player.engine.profile(player.voice)?.summary.nonEmpty ?? player.engine.title)
                        .font(Otter.font(11.5, .medium)).foregroundStyle(Otter.soft).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Otter.soft)
            }
            .card(padding: 12)
        }
        .buttonStyle(KeyButtonStyle(radius: 16))
        .accessibilityLabel("Voice: \(Engine.title(player.voice)). Change")
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
        player.stageFile(url)
    }

    private func allowAccessibility() {
        if model.askedTrust {
            openPrivacy("Privacy_Accessibility")
        } else {
            model.askedTrust = true
            trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }

    private func allowScreenRecording() {
        if model.askedScreen {
            openPrivacy("Privacy_ScreenCapture")
        } else {
            model.askedScreen = true
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
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: "Settings", back: back)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    SectionLabel("Shortcuts")
                    Spacer()
                    if shortcuts.isCustomized {
                        Button("Reset", action: shortcuts.resetToDefaults)
                            .buttonStyle(PlainButtonStyle(radius: 6))
                            .font(Otter.font(11.5, .bold))
                            .foregroundStyle(Otter.teal)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(ShortcutAction.allCases.enumerated()), id: \.element) { i, action in
                        if i > 0 { Divider().overlay(Otter.edge) }
                        ShortcutRecorder(shortcuts: shortcuts, action: action)
                    }
                }
                .card(padding: 12)
            }
            VStack(alignment: .leading, spacing: 7) {
                SectionLabel("App")
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) })) {
                            Text("Open at login").font(Otter.font(13.5, .bold)).foregroundStyle(Otter.ink)
                        }
                        .toggleStyle(.switch)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if let loginNote {
                            Text(loginNote).font(Otter.font(11.5, .medium)).foregroundStyle(Otter.alert)
                        }
                    }
                    .padding(.vertical, 8)
                    Divider().overlay(Otter.edge)
                    Toggle(isOn: Binding(get: { daily }, set: { daily = $0; updater.checksDaily = $0 })) {
                        Text("Check for updates daily").font(Otter.font(13.5, .bold)).foregroundStyle(Otter.ink)
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
        .contentShape(Rectangle())
        .onTapGesture { if shortcuts.recording != nil { shortcuts.cancelRecording() } }
        .onAppear {
            daily = updater.checksDaily
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginNote = SMAppService.mainApp.status == .requiresApproval ? "Allow Berang in Login Items." : nil
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginNote = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginNote = error.localizedDescription
        }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            loginNote = "Allow Berang in Login Items."
            SMAppService.openSystemSettingsLoginItems()
        }
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
            .buttonStyle(KeyButtonStyle(radius: 10))
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
