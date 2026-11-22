import AppKit
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
    pdfParagraphs([ocrLines(image)], heights: [CGFloat(image.height)])
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
