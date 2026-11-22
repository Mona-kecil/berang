// Prints the main text of a window as Markdown: headings as "# ", blocks separated by blank lines.
// usage: berang-grab [--save page.json.lzma] [bundle-id-or-pid [window-title-prefix]]   (default: the frontmost app's focused window)
//        berang-grab --replay page.json.lzma
//        berang-grab --pdf file.pdf [--save lines.json.lzma]
//        berang-grab --image file.png
//        berang-grab --file book.epub   (a PDF, EPUB, image, or text file)
// --save writes the window's accessibility tree, compressed, and prints the text read back from that copy.
// --replay prints the text read from a saved copy. --pdf prints the text read from a PDF file, and with --save also writes its lines for the tests.
// The summary on stderr ends with the block that reading starts at (the selection, a visible click, or the top of
// the screen) and the page address that reading positions are kept under. A window with no text in the
// accessibility tree is read by recognizing the text on screen, when the terminal may record the screen.
import AppKit
import TextGrab

var args = Array(CommandLine.arguments.dropFirst())
if args.first == "--replay", args.count > 1 {
    do {
        let packed = try Data(contentsOf: URL(filePath: args[1]))
        let data = try (packed as NSData).decompressed(using: .lzma) as Data
        let blocks = try (try? JSONDecoder().decode(SavedPDF.self, from: data))?.read()
            ?? read(saved: JSONDecoder().decode(SavedNode.self, from: data))
        print(markdown(blocks), terminator: "")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
}
if args.first == "--pdf", args.count > 1 {
    let url = URL(filePath: args[1])
    let clock = ContinuousClock.now
    guard let pdf = SavedPDF(url: url) else {
        FileHandle.standardError.write(Data("\(args[1]) is not a PDF\n".utf8))
        exit(1)
    }
    let blocks = pdf.read()
    FileHandle.standardError.write(Data("\(blocks.count) blocks, \((ContinuousClock.now - clock) / .milliseconds(1)) ms\n".utf8))
    if args.count > 3, args[2] == "--save" {
        try! (try! JSONEncoder().encode(pdf) as NSData).compressed(using: .lzma).write(to: URL(filePath: args[3]))
    }
    print(markdown(blocks), terminator: "")
    exit(0)
}
if args.first == "--image" || args.first == "--file", args.count > 1 {
    let clock = ContinuousClock.now
    guard let page = readFilePage(URL(filePath: args[1])) else {
        FileHandle.standardError.write(Data("\(args[1]) is not a file Berang reads\n".utf8))
        exit(1)
    }
    FileHandle.standardError.write(Data("\(page.blocks.count) blocks, \((ContinuousClock.now - clock) / .milliseconds(1)) ms, starts at block \(page.start)\n".utf8))
    print(markdown(page.blocks), terminator: "")
    exit(0)
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
    var startAt = ""
    if let saveTo {
        let tree = try save(app, windowTitle: title)
        try (JSONEncoder().encode(tree) as NSData).compressed(using: .lzma).write(to: saveTo)
        blocks = read(saved: tree)
    } else {
        var page = try grab(app, windowTitle: title)
        // An app that draws its text without the accessibility tree is read off the screen, as Berang does.
        if page.blocks.isEmpty, CGPreflightScreenCaptureAccess(), let frame = page.viewportFrame {
            page = page.with(try await readScreen(frame))
            startAt = ", recognized on screen"
        }
        blocks = page.blocks
        startAt += ", starts at block \(page.start) (\(page.startPoint)), \(page.address ?? "no address")"
    }
    let took = ContinuousClock.now - start
    print(markdown(blocks), terminator: "")
    let chars = blocks.reduce(0) { $0 + $1.text.count }
    FileHandle.standardError.write(Data("\(app.localizedName ?? "") | \(blocks.count) blocks, \(chars) chars, \(Int(took / .milliseconds(1))) ms\(startAt)\n".utf8))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
