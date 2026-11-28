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

    /// Brings the window forward after you switch Berang on in System Settings. macOS may not let an app activate
    /// itself while another is in front, so Berang also asks to be opened, which it always honors.
    func comeBack() {
        show()
        let open = NSWorkspace.OpenConfiguration()
        open.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: open)
    }

    override func close() {
        model.shortcuts?.cancelRecording()
        super.close()
    }
}

@MainActor @Observable final class WindowModel {
    enum Page { case home, voices, settings }
    var page = Page.home
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
        .padding(.horizontal, 20)
        .padding(.top, 38)
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
    @State private var voice = Engine.allCases.contains(where: \.isInstalled)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var readyToRead: Bool { trusted && voice }
    private var hasPendingFile: Bool { player.staged != nil || player.stagingTitle != nil || player.fileError != nil }
    private var showingWelcome: Bool { !readyToRead || !model.setupDismissed }

    var body: some View {
        VStack(spacing: 0) {
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
                voice = Engine.allCases.contains(where: \.isInstalled)
                if !trusted || !voice { model.setupDismissed = false }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        // So the row is already ticked when the guide brings Berang back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = AXIsProcessTrusted()
        }
    }

    private var settingsLink: some View {
        Button { go(.settings) } label: {
            HStack(spacing: 6) {
                Text("Settings").font(Otter.font(14, .bold)).foregroundStyle(Otter.soft)
                if shortcuts.needsAttention { Circle().fill(Otter.orange).frame(width: 8, height: 8) }
            }
            .padding(.vertical, 4).padding(.trailing, 8)
        }
        .buttonStyle(PlainButtonStyle(radius: 6))
        .accessibilityLabel(shortcuts.needsAttention ? "Settings, a shortcut needs attention" : "Settings")
        .keyboardShortcut(",", modifiers: .command)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // First open: setup is two steps.
    private var welcome: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Text(readyToRead ? "You're all set." : "Hi, I'm Berang.").pageTitle()
                if readyToRead {
                    readLine
                } else {
                    Text("I read anything on your Mac out loud.")
                        .font(Otter.font(14, .bold)).foregroundStyle(Otter.soft)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 52)
            VStack(spacing: 14) {
                step(1, "Let me read other apps", done: trusted) {
                    Button("Allow") { player.guide.show(.accessibility) }.buttonStyle(ChunkyButtonStyle(compact: true))
                }
                step(2, "Pick my voice", done: voice) {
                    if let fraction = player.download {
                        HStack(spacing: 6) {
                            ProgressView(value: fraction).tint(Otter.orange).frame(width: 64)
                            Text("\(Int((fraction * 100).rounded()))%")
                                .font(Otter.font(12, .heavy)).monospacedDigit().foregroundStyle(Otter.orange)
                        }
                    } else if trusted {
                        Button("Choose") { go(.voices) }.buttonStyle(ChunkyButtonStyle(compact: true))
                    } else {
                        Button("Choose") { go(.voices) }.buttonStyle(LinkButtonStyle())
                    }
                }
            }
            .pageCard(padding: 22)
            .overlay(alignment: .topLeading) { PeekingOtter().offset(x: 28, y: -64) }
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
            } else if case .failed(let failure) = player.state, !voice {
                Text(failure.message).font(Otter.font(12, .medium)).foregroundStyle(Otter.alert)
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

    private func step(_ number: Int, _ title: String, done: Bool, @ViewBuilder action: () -> some View) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(done ? Otter.mint : Otter.teal)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Otter.teal)
                } else {
                    Text("\(number)").font(Otter.font(12, .heavy)).foregroundStyle(.white)
                }
            }
            .frame(width: 22, height: 22)
            .accessibilityLabel(done ? "Done" : "Step \(number)")
            Text(title).font(Otter.rowFont).foregroundStyle(done ? Otter.soft : Otter.ink)
            Spacer(minLength: 8)
            if !done { action() }
        }
        .frame(minHeight: 34)
    }

    private var home: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                if let staged = player.staged {
                    stagedFileCard(staged, canRead: true)
                } else if let title = player.stagingTitle {
                    stagingLoadingCard(title)
                } else {
                    Button("Choose a File…", action: chooseFile).buttonStyle(ChunkyButtonStyle())
                    if let error = player.fileError {
                        Text(error).font(Otter.font(12, .semibold)).foregroundStyle(Otter.alert)
                            .multilineTextAlignment(.center)
                    }
                }
                readLine
            }
            Spacer(minLength: 0)
            voiceCard.padding(.top, 66)
            settingsLink.padding(.top, 14)
        }
    }

    private var readLine: some View {
        Group {
            if let broken = [ShortcutAction.page, .area].first(where: { !shortcuts.working.contains($0) }) {
                HStack(spacing: 8) {
                    Text("\(shortcuts.combos[broken]!.display) isn't working.").foregroundStyle(Otter.alert)
                    Button("Change it") { go(.settings) }.buttonStyle(LinkButtonStyle())
                }
            } else {
                HStack(spacing: 6) {
                    Text("Press")
                    KeyCap(text: shortcuts.combos[.page]!.display, inline: true)
                    Text("in any app to hear it.")
                }
                .foregroundStyle(Otter.soft)
            }
        }
        .font(Otter.font(13.5, .bold))
    }

    private func stagingLoadingCard(_ title: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Opening \(title)…").font(Otter.rowFont).foregroundStyle(Otter.ink).lineLimit(1)
            Spacer()
            closeButton("Cancel")
        }
        .pageCard()
    }

    private func closeButton(_ label: String) -> some View {
        Button { player.clearStaged() } label: {
            Image(systemName: "xmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Otter.soft)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(PlainButtonStyle(radius: 8))
        .accessibilityLabel(label)
    }

    /// Model/Player.tla, StageOnDrop.
    private func stagedFileCard(_ file: Player.StagedFile, canRead: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.title).font(Otter.font(19, .heavy)).foregroundStyle(Otter.ink).lineLimit(2)
                    if file.resumed {
                        Text("Resume at \(file.percent)%")
                            .font(Otter.font(13, .heavy)).monospacedDigit().foregroundStyle(Otter.teal)
                    }
                }
                Spacer(minLength: 4)
                closeButton("Close file")
            }
            if !canRead {
                Text("Pick a voice above to read this file.").font(Otter.font(12, .medium)).foregroundStyle(Otter.soft)
            }
            HStack(spacing: 16) {
                Button {
                    player.readStaged(fromStart: false)
                } label: {
                    Label(file.resumed ? "Resume" : "Read aloud", systemImage: "play.fill")
                }
                .buttonStyle(ChunkyButtonStyle(compact: true))
                .disabled(!canRead)
                if file.resumed {
                    Button("Start over") { player.readStaged(fromStart: true) }
                        .buttonStyle(LinkButtonStyle())
                        .disabled(!canRead)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pageCard()
    }

    private var voiceCard: some View {
        Button { go(.voices) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(Engine.title(player.voice)).font(Otter.font(24, .heavy)).tracking(-0.36).foregroundStyle(Otter.ink)
                Text(player.engine.profile(player.voice)?.summary.nonEmpty ?? player.engine.title)
                    .font(Otter.font(14, .bold)).foregroundStyle(Otter.soft).lineLimit(1)
                Text("Change voice").font(Otter.font(14, .heavy)).foregroundStyle(Otter.teal).padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pageCard(padding: 22)
        }
        .buttonStyle(KeyButtonStyle(radius: 22))
        .overlay(alignment: .topLeading) { PeekingOtter().offset(x: 28, y: -64) }
        .accessibilityLabel("Voice: \(Engine.title(player.voice)). Change")
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .epub, .image, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        player.stageFile(url)
    }
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
            VStack(spacing: 0) {
                ForEach(ShortcutAction.allCases, id: \.self) { ShortcutRecorder(shortcuts: shortcuts, action: $0) }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            .pageCard(padding: 0)
            if shortcuts.isCustomized {
                Button("Reset shortcuts", action: shortcuts.resetToDefaults)
                    .buttonStyle(LinkButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    toggleRow("Open at login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                    if let loginNote {
                        Text(loginNote).font(Otter.font(12, .medium)).foregroundStyle(Otter.alert)
                    }
                }
                .padding(.vertical, 9)
                toggleRow("Check for updates daily", isOn: Binding(get: { daily }, set: { daily = $0; updater.checksDaily = $0 }))
                    .padding(.vertical, 9)
                HStack {
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(Otter.rowFont).foregroundStyle(Otter.ink)
                    Spacer()
                    Button(updater.waiting.map { "Update to \($0)" } ?? "Check now", action: updater.check)
                        .buttonStyle(LinkButtonStyle())
                }
                .padding(.vertical, 9)
            }
            .padding(.horizontal, 4)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { if shortcuts.recording != nil { shortcuts.cancelRecording() } }
        .onAppear {
            daily = updater.checksDaily
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginNote = SMAppService.mainApp.status == .requiresApproval ? "Allow Berang in Login Items." : nil
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(Otter.rowFont).foregroundStyle(Otter.ink)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch)
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
                Text(action.title).font(Otter.rowFont).foregroundStyle(Otter.ink)
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
        .padding(.vertical, 10)
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
