import AppKit
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers
import Vision

/// The lines of text Vision recognizes in `image`, in pixels with the origin at the bottom left, as PDF lines are.
func ocrLines(_ image: CGImage) -> [PDFLine] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.automaticallyDetectsLanguage = true
    try? VNImageRequestHandler(cgImage: image).perform([request])
    let size = CGSize(width: image.width, height: image.height)
    return (request.results ?? []).compactMap { line in
        guard let text = line.topCandidates(1).first?.string else { return nil }
        let b = line.boundingBox
        return PDFLine(text: text, bounds: CGRect(x: b.minX * size.width, y: b.minY * size.height,
                                                  width: b.width * size.width, height: b.height * size.height))
    }
}

/// The paragraphs Vision recognizes in `image`, joined the way a PDF's lines are.
func ocrParagraphs(_ image: CGImage) -> [PDFParagraph] {
    pdfParagraphs([ocrLines(image)], heights: [CGFloat(image.height)], sizedLines: false)
}

/// The blocks of the image at `url`, or nil when it is not an image.
public func readImage(_ url: URL) -> [Block]? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    return ocrParagraphs(image).map(\.block)
}

/// An image that Preview shows from a file, read by recognizing its text. Nil for other windows.
func readImageFile(in window: AXUIElement, app: NSRunningApplication) -> Page? {
    guard let address = address(window, window), let url = URL(string: address), url.isFileURL,
          UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true,
          let blocks = readImage(url) else { return nil }
    return Page(app: app.localizedName ?? "", window: window.string(kAXTitleAttribute) ?? "", blocks: blocks,
                viewport: window, clip: nil, start: 0, startPoint: .screen, address: address)
}

/// The text of a part of the screen the user chose, saved as an image at `url`. Nil when it is not an image.
public func readScreenArea(_ url: URL) -> Page? {
    readImage(url).map {
        Page(app: "", window: "", blocks: $0, viewport: AXUIElementCreateSystemWide(), clip: nil, start: 0,
             startPoint: .selection, address: nil)
    }
}

/// The text on screen inside `frame`, in accessibility coordinates, read by recognizing it, for apps that draw
/// their text without putting it in the accessibility tree. Leaves out this app's own windows, such as the
/// player. Needs Screen Recording access.
@MainActor public func readScreen(_ frame: CGRect) async throws -> [Block] {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let area = { (d: SCDisplay) in d.frame.intersection(frame) }
    guard let display = content.displays.max(by: { area($0).width * area($0).height < area($1).width * area($1).height }),
          !area(display).isEmpty else { return [] }
    let filter = SCContentFilter(display: display, excludingApplications: content.applications.filter { $0.processID == getpid() },
                                 exceptingWindows: [])
    let config = SCStreamConfiguration()
    let shown = area(display)
    config.sourceRect = shown.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
    config.width = Int(shown.width * CGFloat(filter.pointPixelScale))
    config.height = Int(shown.height * CGFloat(filter.pointPixelScale))
    config.showsCursor = false
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    return ocrParagraphs(image).map(\.block)
}

extension Page {
    /// The same page with other blocks, read from the top.
    public func with(_ blocks: [Block]) -> Page {
        Page(app: app, window: window, blocks: blocks, viewport: viewport, clip: clip, start: 0, startPoint: .screen, address: address)
    }
}

/// The blocks of a file: a PDF, an EPUB, an image, or plain text. Nil for other files.
public func readFile(_ url: URL) -> [Block]? {
    let type = UTType(filenameExtension: url.pathExtension)
    if type?.conforms(to: .pdf) == true { return readPDF(url) }
    if type?.conforms(to: .epub) == true || url.pathExtension.lowercased() == "epub" { return readEPUB(url)?.blocks }
    if type?.conforms(to: .image) == true { return readImage(url) }
    if type?.conforms(to: .plainText) == true, let text = try? String(contentsOf: url, encoding: .utf8) {
        return text.components(separatedBy: "\n\n").compactMap { p in
            let t = p.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return t.isEmpty ? nil : Block(kind: .text, text: t, runs: [])
        }
    }
    return nil
}

/// Text typed or pasted to listen to, one paragraph per line. It keeps no reading position.
public func textPage(_ text: String) -> Page {
    let blocks = text.components(separatedBy: .newlines).compactMap { line in
        let t = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return t.isEmpty ? nil : Block(kind: .text, text: t, runs: [])
    }
    return Page(app: "", window: "", blocks: blocks, viewport: AXUIElementCreateSystemWide(), clip: nil, start: 0,
                startPoint: .screen, address: nil)
}

/// A file read whole, to listen to without a window: reading positions are kept by its address.
public func readFilePage(_ url: URL) -> Page? {
    let book = url.pathExtension.lowercased() == "epub" ? readEPUB(url) : readFile(url).map { ($0, 0) }
    return book.map {
        Page(app: "", window: url.deletingPathExtension().lastPathComponent, blocks: $0.0, viewport: AXUIElementCreateSystemWide(),
             clip: nil, start: $0.1, startPoint: .screen, address: url.absoluteString)
    }
}
