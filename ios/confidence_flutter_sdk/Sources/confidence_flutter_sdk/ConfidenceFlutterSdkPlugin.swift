import Flutter
import UIKit

/// Replies to a `FlutterResult` exactly once, on the main thread.
///
/// Flutter requires channel replies on the main thread, and a second reply
/// traps. The `Task {}` cases in this plugin resume on an arbitrary executor,
/// so neither guarantee holds at the call site — both are enforced here.
final class MainThreadResult {
    private let delegate: FlutterResult
    private var replied = false
    private let lock = NSLock()

    init(_ delegate: @escaping FlutterResult) {
        self.delegate = delegate
    }

    func reply(_ value: Any?) {
        lock.lock()
        let alreadyReplied = replied
        replied = true
        lock.unlock()
        if alreadyReplied { return }

        if Thread.isMainThread {
            delegate(value)
        } else {
            DispatchQueue.main.async { self.delegate(value) }
        }
    }
}

public class ConfidenceFlutterSdkPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "confidence_flutter_sdk", binaryMessenger: registrar.messenger())
        let instance = ConfidenceFlutterSdkPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    var confidence: Confidence? = nil

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "flush":
            guard let confidence = self.confidence else {
                result("")
                return
            }
            confidence.flush()
            // Confidence.flush() is non-throwing, so there is nothing to catch
            // here — but the reply is still mandatory: without it the Dart
            // future never completes.
            result("")
            break;
        case "readAllFlags":
            guard let flags = try? readAllFlags() else {
                result("{}")
                return
            }
            let map = flags.reduce(into: [String: ConfidenceValue]()) { map, flag in
                map[flag.flag] = flag.value
            }
            let networkMessage = TypeMapper.convert(structure: map)
            let encoder = JSONEncoder()
            let data = try! encoder.encode(networkMessage)
            let str = String(decoding: data, as: UTF8.self)
            result(str)
            break;
        case "setup":
            guard let args = call.arguments as? Dictionary<String, Any> else {
                result("")
                return
            }
            let apiKey = args["apiKey"] as! String
            let logLevel = args["loggingLevel"] as! String
            var builder = Confidence.Builder(clientSecret: apiKey, loggerLevel: loggerLevel(from: logLevel))
            if let resolveBaseUrl = args["resolveBaseUrl"] as? String, !resolveBaseUrl.isEmpty {
                builder = builder.withResolveBaseUrl(resolveBaseUrl: resolveBaseUrl)
            }
            self.confidence = builder.build()
            result("")
            break;
        case "isStorageEmpty":
            guard let confidence = self.confidence else {
                result(true)
                return
            }
            result(confidence.isStorageEmpty())
            break;
        case "fetchAndActivate":
            let fetchReply = MainThreadResult(result)
            Task {
                guard let confidence = self.confidence else {
                    fetchReply.reply("")
                    return
                }
                do {
                    try await confidence.fetchAndActivate()
                    fetchReply.reply("")
                } catch {
                    NSLog("%@", "Confidence SDK: fetchAndActivate failed: \(error)")
                    fetchReply.reply(
                        FlutterError(
                            code: "FETCH_AND_ACTIVATE_FAILED",
                            message: "\(error)",
                            details: nil))
                }
            }
            break;
        case "activateAndFetchAsync":
            let activateReply = MainThreadResult(result)
            Task {
                guard let confidence = self.confidence else {
                    activateReply.reply("")
                    return
                }
                do {
                    try confidence.activate()
                } catch {
                    NSLog("%@", "Confidence SDK: activate failed: \(error)")
                    activateReply.reply(
                        FlutterError(
                            code: "ACTIVATE_AND_FETCH_ASYNC_FAILED",
                            message: "\(error)",
                            details: nil))
                    return
                }
                // Deliberately not awaited: asyncFetch refreshes in the
                // background and its outcome is not part of this reply.
                Task {
                    await confidence.asyncFetch()
                }
                activateReply.reply("")
            }
            break;
        case "putContext":
            guard let args = call.arguments as? Dictionary<String, Any> else {
                result("")
                return
            }
            let key = args["key"] as! String
            let wrappedValue = args["value"] as! Dictionary<String, Any>
            let type = wrappedValue["type"] as! String
            let value = convertValue(type, wrappedValue["value"]!)
            confidence?.putContext(key: key, value: value)
            result("")
            break;
        case "putAllContext":
            guard let args = call.arguments as? Dictionary<String, Dictionary<String, Any>> else {
                result("")
                return
            }
            let context = args["context"] as! Dictionary<String, Dictionary<String, Any>>
            let map: ConfidenceStruct = context.mapValues { wrappedValue in
                let type = wrappedValue["type"] as! String
                return convertValue(type, wrappedValue["value"]!)
            }
            confidence?.putContext(context: map)
            result("")
            break;
        case "track":
            guard let args = call.arguments as? Dictionary<String, Any> else {
                result("")
                return
            }
            let eventName = args["eventName"] as! String
            let data = args["data"] as! Dictionary<String, Dictionary<String, Any>>
            let convertedData = data.convert()
            do {
                try confidence?.track(eventName: eventName, data: convertedData)
                result("")
            } catch {
                NSLog("%@", "Confidence SDK: \(error)")
                result(FlutterError(
                    code: "TRACK_FAILED",
                    message: "Failed to track event '\(eventName)': \(error)",
                    details: nil))
            }
            break;
        case "getBool":
            let arguments = call.arguments as! Dictionary<String, Any>
            let defaultValue = arguments["defaultValue"] as! Bool
            let key = arguments["key"] as! String
            guard let confidence = self.confidence else {
                result(defaultValue)
                return
            }
            let message: Bool = confidence.getValue(key: key, defaultValue: defaultValue)
            result(message)
            break;
        case "getString":
            let arguments = call.arguments as! Dictionary<String, Any>
            let defaultValue = arguments["defaultValue"] as! String
            let key = arguments["key"] as! String
            guard let confidence = self.confidence else {
                result(defaultValue)
                return
            }

            let message: String = confidence.getValue(key: key, defaultValue: defaultValue)
            result(message)
            break;
        case "getDouble":
            let arguments = call.arguments as! Dictionary<String, Any>
            let defaultValue = arguments["defaultValue"] as! Double
            let key = arguments["key"] as! String
            guard let confidence = self.confidence else {
                result(defaultValue)
                return
            }

            let message: Double = confidence.getValue(key: key, defaultValue: defaultValue)
            result(message)
            break;
        case "getInt":
            let arguments = call.arguments as! Dictionary<String, Any>
            let defaultValue = arguments["defaultValue"] as! Int
            let key = arguments["key"] as! String
            guard let confidence = self.confidence else {
                result(defaultValue)
                return
            }

            let message: Int = confidence.getValue(key: key, defaultValue: defaultValue)
            result(message)
            break;
        case "getObject":
            let arguments = call.arguments as! Dictionary<String, Any>
            let defaultValueWrapped = arguments["defaultValue"] as! Dictionary<String, Dictionary<String, Any>>
            let defaultValue = defaultValueWrapped.convert()
            let key = arguments["key"] as! String
            guard let confidence = self.confidence else {
                result([:])
                return
            }

            let message: ConfidenceStruct = confidence.getValue(key: key, defaultValue: defaultValue)
            let networkMessage = TypeMapper.convert(structure: message)
            let encoder = JSONEncoder()
            let data = try! encoder.encode(networkMessage)
            let str = String(decoding: data, as: UTF8.self)
            result(str)
            break;
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func loggerLevel(from string: String) -> LoggerLevel {
        switch string.uppercased() {
        case "VERBOSE":
            return .TRACE
        case "DEBUG":
            return .DEBUG
        case "WARN":
            return .WARN
        case "ERROR":
            return .ERROR
        default:
            return .WARN
        }
    }
}

func readAllFlags() throws -> [ResolvedValue] {
    let storage = DefaultStorage(filePath: "confidence.flags.resolve")
    let savedFlags = try storage.load(defaultValue: FlagResolution.EMPTY)
    return savedFlags.flags
}

extension Dictionary<String, Dictionary<String, Any>> {
    func convert() -> ConfidenceStruct {
        var map: ConfidenceStruct = [:]
        for (key, wrappedValue) in self {
            let type = wrappedValue["type"] as! String
            map[key] = convertValue(type, wrappedValue["value"]!)
        }
        return map
    }
}

func convertValue(_ type: String, _ value: Any) -> ConfidenceValue {
    switch type {
    case "bool":
        return ConfidenceValue.init(boolean: value as! Bool)
    case "double":
        return ConfidenceValue.init(double: value as! Double)
    case "int":
        return ConfidenceValue.init(integer: value as! Int)
    case "map":
        let dataMap = value as! Dictionary<String, Dictionary<String, Any>>
        let map: ConfidenceStruct = dataMap.mapValues { wrappedValue in
            let type = wrappedValue["type"] as! String
            return convertValue(type, wrappedValue["value"]!)
        }
        return ConfidenceValue.init(structure: map)
    case "list":
        let list = value as! [Dictionary<String, Any>]
        return ConfidenceValue.init(list: list.map { wrappedValue in
            let type = wrappedValue["type"] as! String
            return convertValue(type, wrappedValue["value"]!)
        })
    case "string":
        return ConfidenceValue.init(string: value as! String)
    case "unknown":
        // Dart could not map this type (a DateTime, a null, a custom object)
        // and has already sent `value.toString()`. Keep that string: coercing
        // it to a number would publish a wrong value with nothing to show the
        // caller their data was discarded.
        return ConfidenceValue.init(string: value as? String ?? String(describing: value))
    default:
        // An unrecognised type marker means the Dart and native sides have
        // drifted. Preserve the value as a string and make the mismatch
        // visible rather than silently publishing a number.
        NSLog("%@", "Confidence SDK: unsupported value type '\(type)', publishing it as a string")
        return ConfidenceValue.init(string: value as? String ?? String(describing: value))
    }
}
