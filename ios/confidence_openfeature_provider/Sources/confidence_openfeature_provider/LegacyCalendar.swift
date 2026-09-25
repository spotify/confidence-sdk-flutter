import Foundation

// Keep this Foundation-only helper testable against the pinned native SDK.
// DateComponents' Codable representation retains calendar, time zone, and
// partial fields that cannot be faithfully reconstructed as a Dart DateTime.
enum LegacyCalendar {
    static func convert(_ encoded: [String]) throws -> [String] {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.formatOptions = [.withFullDate]
        return try encoded.map { text in
            let components = try decoder.decode(DateComponents.self, from: Data(text.utf8))
            // Match the native TypeMapper, including its empty-string fallback.
            guard let date = Calendar.current.date(from: components) else { return "" }
            return formatter.string(from: date)
        }
    }
}
