import Foundation
import Testing
@testable import TextGrab

/// otters.epub comes from fixtures/otters-epub.sh.
private let book = SavedPage.folder.appending(path: "fixtures/otters.epub")
private let expected = [
    "Field Notes on Otters", "Copyright 2026", "# Life in the Water",
    "Otters are distinguished by their long, slim bodies, powerful webbed feet for swimming, and their dense fur, which keeps them warm and buoyant.",
    "Some species are adapted to cold waters and need a high metabolic rate to stay warm.", "# How Otters Hunt",
    "Otters find prey with their whiskers, which sense movement in murky water.", "Sea otters use stones as tools.",
    "River otters hunt at night.",
]

@Test func readsAnEPUBInSpineOrderFromWhereItsTextStarts() throws {
    let epub = try #require(readEPUB(book))
    #expect(epub.blocks.map { $0.kind == .heading ? "# \($0.text)" : $0.text } == expected)
    #expect(epub.start == 2)
}

/// Books keeps an EPUB unzipped, as a folder.
@Test func readsAnUnzippedEPUB() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "otters-\(UUID()).epub")
    defer { try? FileManager.default.removeItem(at: folder) }
    let unzip = Process()
    unzip.executableURL = URL(filePath: "/usr/bin/unzip")
    unzip.arguments = ["-q", book.path, "-d", folder.path]
    try unzip.run()
    unzip.waitUntilExit()
    let epub = try #require(readEPUB(folder))
    #expect(epub.blocks.count == expected.count)
    #expect(epub.start == 2)
}
