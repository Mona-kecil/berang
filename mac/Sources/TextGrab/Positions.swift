import Foundation

/// The paragraph a page was last read at, kept so a return to the page can continue from it.
public struct SavedPosition: Codable, Equatable, Sendable {
    public let index: Int
    /// The start of the block's text, to find the block again if the page changed above it.
    public let text: String
    public let date: Date

    public init(_ block: Block, at index: Int, date: Date = .now) {
        self.index = index
        text = String(block.text.prefix(80))
        self.date = date
    }

    /// The saved block in `blocks`: the same index if its text still matches, else the matching block nearest to it.
    public func index(in blocks: [Block]) -> Int? {
        if index < blocks.count, blocks[index].text.hasPrefix(text) { return index }
        return blocks.indices.filter { blocks[$0].text.hasPrefix(text) }.min { abs($0 - index) < abs($1 - index) }
    }
}

/// Reading positions by page address, newest `limit` pages only.
public final class Positions {
    private let defaults: UserDefaults
    private let key = "positions"
    private let limit: Int
    private var all: [String: SavedPosition]

    public init(defaults: UserDefaults = .standard, limit: Int = 200) {
        self.defaults = defaults
        self.limit = limit
        all = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: SavedPosition].self, from: $0) } ?? [:]
    }

    public subscript(page: String) -> SavedPosition? {
        get { all[page] }
        set {
            all[page] = newValue
            if all.count > limit {
                for old in all.sorted(by: { $0.value.date > $1.value.date }).dropFirst(limit) { all[old.key] = nil }
            }
            defaults.set(try? JSONEncoder().encode(all), forKey: key)
        }
    }
}
