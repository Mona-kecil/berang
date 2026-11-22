import Compression
import Foundation

// An EPUB is a zip of XHTML chapters. Its package file lists them in reading order (the spine).

/// The files of a zip archive, by path. Stored and deflated entries only, which is all an EPUB uses.
struct Zip {
    private let data: Data
    private var entries: [String: (method: UInt16, size: Int, unpacked: Int, header: Int)] = [:]

    init?(_ data: Data) {
        self.data = data
        // The end-of-central-directory record is in the last 64 KiB, after the archive comment.
        let bytes = [UInt8](data.suffix(65_557)), base = data.count - bytes.count
        guard let end = stride(from: bytes.count - 22, through: 0, by: -1).first(where: { i in
            bytes[i] == 0x50 && bytes[i + 1] == 0x4B && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06
        }) else { return nil }
        let eocd = base + end
        var at = Int(u32(eocd + 16)), count = Int(u16(eocd + 10))
        while count > 0, at + 46 <= data.count, u32(at) == 0x0201_4B50 {
            let nameLength = Int(u16(at + 28)), extra = Int(u16(at + 30)), comment = Int(u16(at + 32))
            guard at + 46 + nameLength <= data.count else { return nil }
            let name = String(decoding: data[data.startIndex + at + 46 ..< data.startIndex + at + 46 + nameLength], as: UTF8.self)
            entries[name] = (u16(at + 10), Int(u32(at + 20)), Int(u32(at + 24)), Int(u32(at + 42)))
            at += 46 + nameLength + extra + comment
            count -= 1
        }
    }

    func file(_ path: String) -> Data? {
        guard let e = entries[path], u32(e.header) == 0x0403_4B50 else { return nil }
        let start = e.header + 30 + Int(u16(e.header + 26)) + Int(u16(e.header + 28))
        guard start + e.size <= data.count else { return nil }
        let packed = data[data.startIndex + start ..< data.startIndex + start + e.size]
        switch e.method {
        case 0: return Data(packed)
        case 8:
            guard e.unpacked > 0 else { return Data() }
            var out = Data(count: e.unpacked)
            let n = out.withUnsafeMutableBytes { dst in
                packed.withUnsafeBytes { src in
                    compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, e.unpacked,
                                              src.bindMemory(to: UInt8.self).baseAddress!, e.size, nil, COMPRESSION_ZLIB)
                }
            }
            return n == e.unpacked ? out : nil
        default: return nil
        }
    }

    private func u16(_ i: Int) -> UInt16 { UInt16(data[data.startIndex + i]) | UInt16(data[data.startIndex + i + 1]) << 8 }
    private func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 }
}

/// The blocks of the EPUB at `url`, a zip or, as Books keeps them, a folder, and the block the main text starts
/// at. Nil when it is not an EPUB.
public func readEPUB(_ url: URL) -> (blocks: [Block], start: Int)? {
    let file: (String) -> Data?
    if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
        file = { try? Data(contentsOf: url.appending(path: $0)) }
    } else {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), let zip = Zip(data) else { return nil }
        file = zip.file
    }
    guard let container = file("META-INF/container.xml"),
          let package = XML(container).first(where: { $0.name == "rootfile" })?.attributes["full-path"],
          let opf = file(package) else { return nil }
    let folder = (package as NSString).deletingLastPathComponent
    let resolve = { (href: String) in
        ((folder as NSString).appendingPathComponent(String(href.prefix { $0 != "#" })) as NSString).standardizingPath
            .removingPercentEncoding ?? href
    }
    let items = XML(opf)
    var hrefs: [String: String] = [:], nav: String?
    for item in items where item.name == "item" {
        guard let id = item.attributes["id"], let href = item.attributes["href"] else { continue }
        hrefs[id] = resolve(href)
        if item.attributes["properties"]?.split(separator: " ").contains("nav") == true { nav = resolve(href) }
    }
    // Where the main text starts, and the front matter before it, from the EPUB 2 guide or the EPUB 3 landmarks.
    var body: String?, front: Set<String> = []
    for ref in items where ref.name == "reference" {
        guard let type = ref.attributes["type"]?.lowercased(), let href = ref.attributes["href"] else { continue }
        if type == "text" || type == "bodymatter" { body = body ?? resolve(href) }
        if frontMatter.contains(type) { front.insert(resolve(href)) }
    }
    if let nav, let doc = file(nav) {
        let navFolder = (nav as NSString).deletingLastPathComponent
        for a in XML(doc) where a.name == "a" && a.attributes["epub:type"]?.split(separator: " ").contains("bodymatter") == true {
            if let href = a.attributes["href"] {
                body = body ?? ((navFolder as NSString).appendingPathComponent(String(href.prefix { $0 != "#" })) as NSString)
                    .standardizingPath.removingPercentEncoding
            }
        }
    }
    var blocks: [Block] = [], start: Int?
    for ref in items where ref.name == "itemref" && ref.attributes["linear"] != "no" {
        guard let path = ref.attributes["idref"].flatMap({ hrefs[$0] }), path != nav, let chapter = file(path) else { continue }
        let chapterBlocks = chapterBlocks(chapter)
        if body == nil ? start == nil && !front.contains(path) && !chapterBlocks.isEmpty : path == body { start = start ?? blocks.count }
        blocks += chapterBlocks
    }
    return (blocks, start ?? 0)
}

/// Guide types of front matter, which reading skips when the book does not say where its text starts.
private let frontMatter: Set = ["cover", "toc", "title-page", "copyright-page", "dedication", "epigraph", "loi", "lot", "colophon"]

/// The paragraphs, headings, and list items of an XHTML chapter. Navigation, tables, code, figures, footnotes,
/// and note references are left out.
func chapterBlocks(_ xhtml: Data) -> [Block] {
    let reader = ChapterReader()
    let parser = XMLParser(data: withoutHTMLEntities(xhtml))
    parser.delegate = reader
    parser.shouldResolveExternalEntities = false
    parser.parse()
    reader.flush()
    return reader.blocks
}

/// XHTML from EPUB 2 books can use HTML's named entities, like "&nbsp;", which an XML parser stops at.
private func withoutHTMLEntities(_ data: Data) -> Data {
    guard data.contains(UInt8(ascii: "&")) else { return data }
    let s = String(decoding: data, as: UTF8.self) as NSString
    let out = NSMutableString(string: s)
    for m in namedEntity.matches(in: s as String, range: NSRange(location: 0, length: s.length)).reversed() {
        let name = s.substring(with: m.range(at: 1))
        guard !["amp", "lt", "gt", "quot", "apos"].contains(name) else { continue }
        out.replaceCharacters(in: m.range, with: htmlEntities[name] ?? " ")
    }
    return Data((out as String).utf8)
}

private let namedEntity = try! NSRegularExpression(pattern: "&([A-Za-z][A-Za-z0-9]*);")
private let htmlEntities = [
    "nbsp": " ", "ensp": " ", "emsp": " ", "thinsp": " ", "shy": "", "mdash": "—", "ndash": "–", "hellip": "…",
    "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "laquo": "«", "raquo": "»", "copy": "©", "reg": "®",
    "trade": "™", "deg": "°", "times": "×", "middot": "·", "bull": "•", "eacute": "é", "egrave": "è", "aacute": "á",
    "agrave": "à", "iacute": "í", "oacute": "ó", "uacute": "ú", "ntilde": "ñ", "ccedil": "ç", "uuml": "ü", "ouml": "ö",
    "auml": "ä", "szlig": "ß", "pound": "£", "euro": "€", "sect": "§", "para": "¶", "dagger": "†", "frac12": "½",
]

private final class ChapterReader: NSObject, XMLParserDelegate {
    var blocks: [Block] = []
    private var text = "", kind = Block.Kind.text, skipping = 0
    private var open: [(name: String, skips: Bool)] = []

    private static let blockNames: Set = ["p", "div", "li", "blockquote", "dd", "dt", "h1", "h2", "h3", "h4", "h5", "h6", "br", "section", "article", "body"]
    private static let skipped: Set = ["nav", "table", "pre", "figure", "figcaption", "script", "style", "aside", "head", "title", "sup", "rt"]
    private static let skippedTypes: Set = ["footnote", "endnote", "rearnote", "note", "noteref", "pagebreak", "toc", "landmarks", "page-list"]

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let local = name.split(separator: ":").last.map(String.init)?.lowercased() ?? name
        let types = Set((attributes["epub:type"] ?? attributes["type"] ?? "").split(separator: " ").map(String.init))
        let skips = Self.skipped.contains(local) || !types.isDisjoint(with: Self.skippedTypes)
            || attributes["role"].map { $0.hasPrefix("doc-") && ["doc-footnote", "doc-endnote", "doc-noteref", "doc-pagebreak"].contains($0) } == true
        open.append((local, skips))
        if skips { skipping += 1; return }
        if skipping == 0, Self.blockNames.contains(local) {
            flush()
            if local.count == 2, local.first == "h", local.last?.isNumber == true { kind = .heading }
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard let element = open.popLast() else { return }
        if element.skips { skipping -= 1; return }
        if skipping == 0, Self.blockNames.contains(element.name) { flush() }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if skipping == 0 { text += string }
    }

    func flush() {
        let squashed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if squashed.contains(where: { $0.isLetter || $0.isNumber }) {
            blocks.append(Block(kind: kind, text: squashed, runs: []))
        }
        text = ""
        kind = .text
    }
}

/// The elements of an XML document, in order, with their attributes. Enough for an EPUB's container and package.
private func XML(_ data: Data) -> [(name: String, attributes: [String: String])] {
    final class Collector: NSObject, XMLParserDelegate {
        var elements: [(name: String, attributes: [String: String])] = []
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            elements.append((name.split(separator: ":").last.map(String.init) ?? name, attributes))
        }
    }
    let collector = Collector(), parser = XMLParser(data: data)
    parser.delegate = collector
    parser.parse()
    return collector.elements
}
