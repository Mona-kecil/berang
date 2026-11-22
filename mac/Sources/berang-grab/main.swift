// Prints the main text of a window as Markdown: headings as "# ", blocks separated by blank lines.
// usage: berang-grab [--save page.json.lzma] [bundle-id-or-pid [window-title-prefix]]   (default: the frontmost app's focused window)
//        berang-grab --replay page.json.lzma
// --save writes the window's accessibility tree, compressed, and prints the text read back from that copy.
// --replay prints the text read from a saved copy.
import AppKit
import TextGrab

var args = Array(CommandLine.arguments.dropFirst())
if args.first == "--replay", args.count > 1 {
    do {
        let packed = try Data(contentsOf: URL(filePath: args[1]))
        let tree = try JSONDecoder().decode(SavedNode.self, from: (packed as NSData).decompressed(using: .lzma) as Data)
        print(markdown(read(saved: tree)), terminator: "")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
}
var saveTo: URL?
if args.first == "--save", args.count > 1 {
    saveTo = URL(filePath: args[1])
    args.removeFirst(2)
}
let app = args.first.map { pid_t($0).flatMap(NSRunningApplication.init(processIdentifier:)) ?? NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
    ?? NSWorkspace.shared.frontmostApplication
guard let app else {
    FileHandle.standardError.write(Data("\(args[0]) is not running\n".utf8))
    exit(1)
}

do {
    let title = args.count > 1 ? args[1] : nil
    let start = ContinuousClock.now
    let blocks: [Block]
    if let saveTo {
        let tree = try save(app, windowTitle: title)
        try (JSONEncoder().encode(tree) as NSData).compressed(using: .lzma).write(to: saveTo)
        blocks = read(saved: tree)
    } else {
        blocks = try grab(app, windowTitle: title).blocks
    }
    let took = ContinuousClock.now - start
    print(markdown(blocks), terminator: "")
    let chars = blocks.reduce(0) { $0 + $1.text.count }
    FileHandle.standardError.write(Data("\(app.localizedName ?? "") | \(blocks.count) blocks, \(chars) chars, \(Int(took / .milliseconds(1))) ms\n".utf8))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
