import AppKit
import SwiftUI

/// Setup: the permissions Berang needs, the voice, and the two shortcuts. It opens at launch until Berang can
/// read, and from the menu bar.
final class SetupWindow: NSWindow {
    init(player: Player, showVoices: @escaping () -> Void) {
        super.init(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "Set Up Berang"
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: SetupView(player: player, showVoices: showVoices) { [weak self] in self?.close() })
        setContentSize(contentView!.fittingSize)
        center()
    }

    /// Whether Berang can't read yet: it lacks Accessibility access or the voice.
    static var isNeeded: Bool { !AXIsProcessTrusted() || !Voice.isInstalled }

    func show() {
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }
}

/// Each step's status is read from the system every second, so it is right after a change in System Settings.
struct SetupView: View {
    let player: Player
    let showVoices: () -> Void
    let close: () -> Void
    @State private var trusted = AXIsProcessTrusted()
    @State private var screen = CGPreflightScreenCaptureAccess()
    @State private var voice = Voice.isInstalled
    /// macOS shows its permission prompt once; after that, the button opens System Settings instead.
    @State private var askedTrust = false
    @State private var askedScreen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            step("Accessibility", icon: "accessibility", detail: "Lets Berang read the text in other apps.") {
                if trusted { done("Allowed") } else { Button("Allow", action: allowAccessibility).buttonStyle(.borderedProminent) }
            }
            step("Voice", icon: "waveform", detail: voiceDetail) { voiceControl }
            step("Screen Recording", icon: "rectangle.dashed",
                 detail: "Optional. Lets Berang read part of the screen, and apps that draw their own text. The text is recognized on this Mac.") {
                if screen { done("Allowed") } else { Button("Allow", action: allowScreenRecording) }
            }
            step("Try It", icon: "keyboard",
                 detail: "Press ⌥⎋ in any app to hear the page, or ⌥⇧⎋ to read part of the screen.") {
                if player.hasRead { done("Done") }
            }
            HStack {
                Spacer()
                if next == nil {
                    Button("Done", action: close).keyboardShortcut(.defaultAction)
                } else {
                    Button("Later", action: close).keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(24)
        .frame(width: 500)
        .task {
            while !Task.isCancelled {
                trusted = AXIsProcessTrusted()
                screen = CGPreflightScreenCaptureAccess()
                voice = Voice.isInstalled
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private enum Step { case accessibility, voice }

    /// The required step to do next, whose button stands out.
    private var next: Step? { !trusted ? .accessibility : !voice ? .voice : nil }

    private var voiceDetail: String {
        if !voice, case .failed(let message) = player.state { return message }
        return voice ? "Reading with \(Voice.title(player.voice))." : "137 MB, downloaded once."
    }

    @ViewBuilder private var voiceControl: some View {
        if voice {
            Button("Choose Voice…", action: showVoices)
        } else if let fraction = player.download {
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: fraction).frame(width: 120)
                Text("\(Int(fraction * Double(Voice.downloadSize) / 1_000_000)) of 137 MB")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        } else if next == .voice {
            Button(player.state.isFailed ? "Try Again" : "Download", action: player.downloadVoice).buttonStyle(.borderedProminent)
        } else {
            Button(player.state.isFailed ? "Try Again" : "Download", action: player.downloadVoice)
        }
    }

    private func step(_ title: String, icon: String, detail: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(.tint).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            control()
        }
    }

    private func done(_ label: String) -> some View {
        Label(label, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
    }

    private func allowAccessibility() {
        if askedTrust {
            openSettings("Privacy_Accessibility")
        } else {
            askedTrust = true
            trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }

    private func allowScreenRecording() {
        if askedScreen {
            openSettings("Privacy_ScreenCapture")
        } else {
            askedScreen = true
            screen = CGRequestScreenCaptureAccess()
        }
    }

    private func openSettings(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
}
