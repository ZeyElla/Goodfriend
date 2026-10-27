import SwiftUI
import NaturalLanguage

// MARK: – Alias-aware search

/// On-device, alias-aware search. Expands the query with semantically related
/// words (so "husband" also finds "fiancé"/"spouse") using Apple's word
/// embeddings — no network, no LLM in the hot path.
enum AliasSearch {

    private static let embedding = NLEmbedding.wordEmbedding(for: .english)

    /// Related terms for a single query word, plus the word itself.
    private static func expand(_ word: String) -> [String] {
        let lower = word.lowercased()
        guard lower.count > 2, let embedding else { return [lower] }
        // Distance grows with dissimilarity; keep only close neighbours.
        let neighbours = embedding.neighbors(for: lower, maximumCount: 6)
            .filter { $0.1 < 0.85 }
            .map { $0.0 }
        return [lower] + neighbours
    }

    /// Does `haystack` match `query`, allowing alias matches on each query word?
    static func matches(query: String, haystack: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return true }
        let hay = haystack.lowercased()

        // Every query word must match (directly or via an alias) somewhere.
        let words = trimmed.split(separator: " ").map(String.init)
        return words.allSatisfy { word in
            if hay.contains(word) { return true }
            return expand(word).contains { hay.contains($0) }
        }
    }
}

// MARK: – Color from hex string

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6 else { return nil }
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8)  & 0xFF) / 255,
            blue:  Double(rgb         & 0xFF) / 255
        )
    }

    func toHex() -> String {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
        #else
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        ns.getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
        #endif
    }
}

// MARK: – Date formatting

extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var shortFormatted: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: self)
    }
}

// MARK: – View modifiers

extension View {
    func cardStyle() -> some View {
        self
            .background(Color.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

// MARK: – Color helpers

extension Color {
    #if canImport(UIKit)
    static let secondaryBackground = Color(UIColor.secondarySystemGroupedBackground)
    static let systemBackground = Color(UIColor.systemBackground)
    #else
    static let secondaryBackground = Color(NSColor.controlBackgroundColor)
    static let systemBackground = Color(NSColor.windowBackgroundColor)
    #endif
}
