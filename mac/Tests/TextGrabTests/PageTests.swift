import Foundation
import Testing
import TextGrab

/// A page saved by Pages/record.sh: its accessibility tree and the text the grabber read from it.
struct SavedPage: CustomTestStringConvertible, Sendable {
    let name: String
    var testDescription: String { name }

    static let folder = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Pages")
    static let all: [SavedPage] = {
        let tsv = try! String(contentsOf: folder.appending(path: "pages.tsv"), encoding: .utf8)
        return tsv.split(separator: "\n").dropFirst().map { SavedPage(name: String($0.split(separator: "\t")[0])) }
    }()
}

@Test(arguments: SavedPage.all)
func readsSavedPage(_ page: SavedPage) throws {
    let packed = try Data(contentsOf: SavedPage.folder.appending(path: "\(page.name).json.lzma"))
    let tree = try JSONDecoder().decode(SavedNode.self, from: (packed as NSData).decompressed(using: .lzma) as Data)
    let got = markdown(read(saved: tree))
    let want = try String(contentsOf: SavedPage.folder.appending(path: "\(page.name).md"), encoding: .utf8)
    guard got != want else { return }
    let (g, w) = (got.split(separator: "\n", omittingEmptySubsequences: false), want.split(separator: "\n", omittingEmptySubsequences: false))
    let line = zip(g, w).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(g.count, w.count)
    Issue.record("""
        \(page.name).md differs at line \(line + 1). Rerun Pages/record.sh \(page.name) or fix the grabber.
          want: \(line < w.count ? w[line] : "<end>")
          got:  \(line < g.count ? g[line] : "<end>")
        """)
}
