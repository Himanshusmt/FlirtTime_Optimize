import Foundation

struct EmojiItem: Codable, Equatable {
    let c: String
    let n: String
    let cat: String
    let s: [String]
    let k: [String]
    let idx: String

    var char: String { c }
    var name: String { n }
    var category: String { cat }
}

final class EmojiCatalog {

    static let shared = EmojiCatalog()

    let all: [EmojiItem]
    let byCategory: [(name: String, icon: String, items: [EmojiItem])]

    private static let categoryOrder: [(name: String, icon: String)] = [
        ("Smileys & People",   "😀"),
        ("Animals & Nature",   "🐻"),
        ("Food & Drink",       "🍔"),
        ("Activities",         "⚽"),
        ("Travel & Places",    "🚗"),
        ("Objects",            "💡"),
        ("Symbols",            "#️⃣"),
        ("Flags",              "🏁")
    ]

    private init() {
        let parsed: [EmojiItem]
        if let url = Bundle.main.url(forResource: "emoji", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([EmojiItem].self, from: data) {
            parsed = decoded
        } else {
            parsed = []
        }
        self.all = parsed

        var grouped: [(String, String, [EmojiItem])] = []
        for entry in Self.categoryOrder {
            let items = parsed.filter { $0.cat == entry.name }
            if !items.isEmpty {
                grouped.append((entry.name, entry.icon, items))
            }
        }
        self.byCategory = grouped
    }

    func search(_ query: String) -> [EmojiItem] {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        let capped = String(raw.prefix(50))
        let tokens = capped.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        return all.filter { item in
            tokens.allSatisfy { token in
                item.idx.contains(token) || item.char.contains(token)
            }
        }
    }
}
