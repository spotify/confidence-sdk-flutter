import Foundation

// Compile alongside the pinned SDK sources and LegacyCalendar.swift.
@main
struct CalendarParity {
    static func main() throws {
        let encoder = JSONEncoder()
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let values = [
            DateComponents(calendar: gregorian, timeZone: TimeZone(secondsFromGMT: 3600), year: 2024, month: 2, day: 29),
            DateComponents(year: 2024),
            DateComponents(),
            DateComponents(calendar: gregorian, timeZone: TimeZone(identifier: "America/Los_Angeles"), year: 2024, month: 3, day: 10, hour: 2, minute: 30),
            DateComponents(calendar: buddhist, year: 2567, month: 1, day: 1),
            DateComponents(year: 2024, month: 13, day: 32),
            DateComponents(weekOfYear: 1, yearForWeekOfYear: 2024)
        ]
        let encoded = try values.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
        let actual = try LegacyCalendar.convert(encoded)
        for (index, value) in values.enumerated() {
            guard case .string(let expected)? = TypeMapper.convert(value: ConfidenceValue(date: value)) else {
                fatalError("Unexpected native date representation")
            }
            precondition(actual[index] == expected, "Calendar conversion diverged at index \(index)")
        }
        do {
            _ = try LegacyCalendar.convert(["{invalid"])
            fatalError("Invalid calendar input accepted")
        } catch {}
        print("Calendar parity passed: \(values.count) cases, timezone \(TimeZone.current.identifier)")
    }
}
