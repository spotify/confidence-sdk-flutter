import Flutter
import UIKit

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
            self.confidence = Confidence.Builder(clientSecret: apiKey, loggerLevel: loggerLevel(from: logLevel))
                .build()
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
            Task {
                guard let confidence = self.confidence else {
                    result("")
                    return
                }
                do {
                    try await confidence.fetchAndActivate()
                } catch {
                    NSLog("%@", "Confidence SDK: \(error)")
                }
                result("")
                return
            }
            break;
        case "activateAndFetchAsync":
            Task {
                guard let confidence = self.confidence else {
                    result("")
                    return
                }
                do {
                    try confidence.activate()
                } catch {
                    NSLog("%@", "Confidence SDK: \(error)")
                }
                Task {
                    confidence.asyncFetch()
                }
                result("")
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
                return
            }
            let eventName = args["eventName"] as! String
            let data = args["data"] as! Dictionary<String, Dictionary<String, Any>>
            let convertedData = data.convert()
            try? confidence?.track(eventName: eventName, data: convertedData)
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
    default:
        return ConfidenceValue.init(integer: 0)
    }
}
