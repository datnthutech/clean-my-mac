import Foundation

/// Formats byte counts the way Finder does (decimal units: 1 KB = 1000 bytes),
/// using the separators of the given locale so "8,2 GB" (vi) and "8.2 GB" (en) both work.
public enum ByteFormatter {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    public static func string(_ bytes: Int64, locale: Locale = .current) -> String {
        if bytes <= 0 { return "0 B" }
        var value = Double(bytes)
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        // One decimal for GB/TB below 100, none for small units — mirrors Finder.
        formatter.maximumFractionDigits = (index >= 2 && value < 100) ? 1 : 0
        let number = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
        return "\(number) \(units[index])"
    }

    public static let gigabyte: Int64 = 1_000_000_000
    public static let megabyte: Int64 = 1_000_000
}
