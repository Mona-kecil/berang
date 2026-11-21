// Prints the main text of a window as Markdown: headings as "# ", blocks separated by blank lines.
// usage: berang-grab [bundle-id [window-title-prefix]]   (default: the frontmost app's focused window)
import AppKit
import TextGrab

let args = Array(CommandLine.arguments.dropFirst())
let app = args.first.map { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
    ?? NSWorkspace.shared.frontmostApplication
guard let app else {
    FileHandle.standardError.write(Data("\(args[0]) is not running\n".utf8))
    exit(1)
}

do {
    let start = ContinuousClock.now
    let page = try grab(app, windowTitle: args.count > 1 ? args[1] : nil)
    let took = ContinuousClock.now - start
    for block in page.blocks {
        print(block.kind == .heading ? "# \(block.text)\n" : "\(block.text)\n")
    }
    let chars = page.blocks.reduce(0) { $0 + $1.text.count }
    let ms = took.components.attoseconds / 1_000_000_000_000_000 + took.components.seconds * 1000
    FileHandle.standardError.write(Data("\(page.app) | \(page.window) | \(page.blocks.count) blocks, \(chars) chars, \(ms) ms\n".utf8))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
