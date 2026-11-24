import Foundation

/// The paragraph a page was last read at, kept so a return to the page can continue from it.
public struct SavedPosition: Codable, Equatable, Sendable {
    public let index: Int
    /// The start of the block's text, to find the block again if the page changed above it.
    public let text: String
    public let date: Date
    /// Total blocks in the page or file, when known, to show progress before reopening it.
    public let total: Int?

    public init(_ block: Block, at index: Int, total: Int? = nil, date: Date = .now) {
        self.index = index
        text = String(block.text.prefix(80))
        self.date = date
        self.total = total
    }

    /// Fraction read, from 0 to 1, when `total` is known.
    public var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(max(Double(index) / Double(total), 0), 1)
    }

    /// Percentage read, from 0 to 100, when `total` is known.
    public var percent: Int? { fraction.map { Int(($0 * 100).rounded()) } }

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
