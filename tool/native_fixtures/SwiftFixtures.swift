import Foundation

// Compile alongside Sources/Confidence from the pinned Swift SDK, not against
// a rewritten copy of its models. This produces serialization fixtures only;
// it does not exercise iOS sandbox paths or simulate an application upgrade.
@main
struct SwiftFixtures {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        let context: ConfidenceStruct = [
            "visitor_id": .init(string: "fixture-visitor"),
            "targeting_key": .init(string: "user-a")
        ]
        let values: ConfidenceStruct = [
            "enabled": .init(boolean: true),
            "count": .init(integer: 7),
            "ratio": .init(double: 0.5),
            "label": .init(string: "hello\nworld"),
            "optional": .init(null: ()),
            "nested": .init(structure: ["items": .init(integerList: [1, 2])]),
            "timestamp": .init(timestamp: time)
        ]
        let flags = FlagResolution(
            context: context,
            flags: [ResolvedValue(
                variant: "flags/example/variants/on",
                value: .init(structure: values),
                flag: "example",
                resolveReason: .match
            )],
            resolveToken: "fixture-token"
        )
        let apply = CacheData(resolveToken: "fixture-token", events: [
            FlagApply(name: "created", applyTime: time, status: .created),
            FlagApply(name: "sending", applyTime: time, status: .sending),
            FlagApply(name: "sent", applyTime: time, status: .sent)
        ])
        // DefaultStorage uses default JSONEncoder settings. Sort object keys
        // only, for reviewable and reproducible fixtures.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let flagBytes = try encoder.encode(flags)
        let applyBytes = try encoder.encode(apply)
        let decodedFlags = try JSONDecoder().decode(FlagResolution.self, from: flagBytes)
        precondition(decodedFlags == flags)
        let decoded = try JSONDecoder().decode(CacheData.self, from: applyBytes)
        precondition(CacheData.convertInTransit(cache: decoded).resolveEvents[0].events[1].status == .created)
        try flagBytes.write(to: output.appendingPathComponent("flags.json"))
        try applyBytes.write(to: output.appendingPathComponent("apply.json"))

        // Keep calendar metadata rather than projecting it through the host's
        // current time zone. Replay conversion is a separate compatibility concern.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let dates: ConfidenceStruct = [
            "leapDay": .init(date: DateComponents(calendar: calendar,
                timeZone: TimeZone(secondsFromGMT: 3600), year: 2024, month: 2, day: 29)),
            "partial": .init(date: DateComponents(year: 2024)),
            "beforeEpoch": .init(timestamp: Date(timeIntervalSinceReferenceDate: -0.25))
        ]
        try encoder.encode(dates).write(to: output.appendingPathComponent("calendar.json"))

        let event = ConfidenceEvent(name: "checkout", payload: context.merging(values) { _, new in new }, eventTime: time)
        let eventBytes = try encoder.encode(event)
        _ = try JSONDecoder().decode(ConfidenceEvent.self, from: eventBytes)
        // EventStorage writes a newline BEFORE each encoded record. Sealing
        // changes only the filename extension, so both states share bytes.
        var batch = Data("\n".utf8)
        batch.append(eventBytes)
        try batch.write(to: output.appendingPathComponent("events.READY"))
        try batch.write(to: output.appendingPathComponent("events-unfinished"))
    }
}
