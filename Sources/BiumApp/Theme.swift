import SwiftUI
import BiumCore

/// The palette the design was drawn against, expressed so both appearances
/// resolve from one place.
enum Palette {
    static let safe = Color(nsColor: NSColor(name: nil) { $0.isDark ? #colorLiteral(red: 0.24, green: 0.81, blue: 0.48, alpha: 1) : #colorLiteral(red: 0.12, green: 0.56, blue: 0.31, alpha: 1) })
    static let review = Color(nsColor: NSColor(name: nil) { $0.isDark ? #colorLiteral(red: 0.91, green: 0.64, blue: 0.23, alpha: 1) : #colorLiteral(red: 0.69, green: 0.44, blue: 0.04, alpha: 1) })
    static let caution = Color(nsColor: NSColor(name: nil) { $0.isDark ? #colorLiteral(red: 1.0, green: 0.42, blue: 0.37, alpha: 1) : #colorLiteral(red: 0.76, green: 0.22, blue: 0.17, alpha: 1) })
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

extension SafetyLevel {
    var tint: Color {
        switch self {
        case .safe: return Palette.safe
        case .review: return Palette.review
        case .caution: return Palette.caution
        }
    }
    var symbol: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .review: return "eye.fill"
        case .caution: return "exclamationmark.triangle.fill"
        }
    }
}
