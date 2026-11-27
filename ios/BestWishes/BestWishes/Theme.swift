import SwiftUI
import UIKit

enum Theme {
    /// Warm table-top, not a consumer AAC clone.
    static let board = Color(red: 0.91, green: 0.86, blue: 0.76)
    static let ink = Color(red: 0.11, green: 0.10, blue: 0.09)
    static let cardFill = Color(red: 1.00, green: 0.99, blue: 0.97)
    static let cardStroke = Color(red: 0.11, green: 0.10, blue: 0.09)
    static let labelWell = Color(red: 0.11, green: 0.10, blue: 0.09)
    static let cream = Color(red: 0.98, green: 0.95, blue: 0.90)
    static let coral = Color(red: 0.89, green: 0.35, blue: 0.27)
    static let slate = Color(red: 0.12, green: 0.16, blue: 0.22)
    static let muted = Color(red: 0.42, green: 0.38, blue: 0.33)
}


extension Color {
    init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
        let resolved = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "000000" }
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
