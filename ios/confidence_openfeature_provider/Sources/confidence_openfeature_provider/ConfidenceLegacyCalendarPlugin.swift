import Flutter

public final class ConfidenceLegacyCalendarPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "confidence_openfeature_provider/legacy_calendar",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(ConfidenceLegacyCalendarPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "convertDates" else {
            result(FlutterMethodNotImplemented)
            return
        }
        guard let dates = call.arguments as? [String] else {
            result(FlutterError(code: "invalid_calendar", message: "Invalid legacy calendar data.", details: nil))
            return
        }
        do {
            result(try LegacyCalendar.convert(dates))
        } catch {
            result(FlutterError(code: "invalid_calendar", message: "Invalid legacy calendar data.", details: nil))
        }
    }
}
