import Foundation
import CoreFoundation

public struct DemoScript {
    public let title: String
    public let app: String
    public let windowTitle: String?
    public let displayID: UInt32?
    public let scenes: [Scene]

    public static func load(_ url: URL) throws -> DemoScript {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 1_048_576 else { throw Failure("Script exceeds 1 MiB.") }
        return try parse(Data(contentsOf: url))
    }

    public static func parse(_ data: Data) throws -> DemoScript {
        guard data.count <= 1_048_576 else { throw Failure("Script exceeds 1 MiB.") }
        let root = try Fields(JSONSerialization.jsonObject(with: data), keys: ["version", "title", "app", "window", "capture", "scenes"])
        guard try root.number("version") == 1 else { throw Failure("Only script version 1 is supported.") }
        let title = try root.string("title")
        let app = try root.string("app")
        let window = try root.optionalObject("window", keys: ["title"])?.string("title")
        var displayID: UInt32?
        if let capture = try root.optionalObject("capture", keys: ["display"]) {
            let display = try capture.number("display")
            guard display >= 1, display <= Double(UInt32.max), display.rounded() == display else {
                throw Failure("capture.display must be a display ID from agent-desktop list-displays.")
            }
            displayID = UInt32(display)
        }
        let values = try root.array("scenes")
        guard !values.isEmpty, values.count <= 100 else { throw Failure("Use 1 to 100 scenes.") }
        let scenes = try values.enumerated().map { index, value -> Scene in
            let fields = try Fields(value, keys: ["say", "actions", "expect", "absent", "app", "window"])
            let sceneApp = try fields.optionalString("app")
            let sceneWindow = try fields.optionalObject("window", keys: ["title"])?.string("title")
            guard displayID != nil || (sceneApp == nil && sceneWindow == nil) else {
                throw Failure("Scene app/window switching requires explicit capture.display.")
            }
            let say = try fields.optionalString("say", max: 5000)
            let actions = try fields.array("actions", default: []).map(Action.parse)
            guard actions.count <= 100 else { throw Failure("Scene \(index + 1) exceeds 100 actions.") }
            let expect = try fields.values["expect"].map(Expected.parse)
            let absent = try fields.values["absent"].map(Expected.parse)
            guard say != nil || !actions.isEmpty || expect != nil || absent != nil else { throw Failure("Scene \(index + 1) is empty.") }
            return Scene(say: say, actions: actions, expect: expect, absent: absent, app: sceneApp, windowTitle: sceneWindow)
        }
        return DemoScript(title: title, app: app, windowTitle: window, displayID: displayID, scenes: scenes)
    }
}

public struct Scene {
    public let say: String?
    public let actions: [Action]
    public let expect: Expected?
    public let absent: Expected?
    public let app: String?
    public let windowTitle: String?
    init(say: String?, actions: [Action], expect: Expected?, absent: Expected? = nil, app: String? = nil, windowTitle: String? = nil) {
        self.say = say; self.actions = actions; self.expect = expect; self.absent = absent; self.app = app; self.windowTitle = windowTitle
    }
}

public struct Selector: Equatable {
    let role: String?
    let name: String?
    let text: String?
    let nativeID: String?
    static let keys: Set<String> = ["role", "name", "text", "nativeID"]

    static func parse(_ fields: Fields) throws -> Selector {
        let selector = try Selector(role: fields.optionalString("role"), name: fields.optionalString("name"),
                                    text: fields.optionalString("text"), nativeID: fields.optionalString("nativeID"))
        guard selector.role != nil || selector.name != nil || selector.text != nil || selector.nativeID != nil else {
            throw Failure("A target must specify role, name, text, or nativeID.")
        }
        return selector
    }

    static func parse(_ value: Any) throws -> Selector { try parse(Fields(value, keys: keys)) }
}

public struct Expected {
    let target: Selector
    let timeout: Double
    static func parse(_ value: Any) throws -> Expected {
        let fields = try Fields(value, keys: Selector.keys.union(["timeout"]))
        let timeout = try fields.optionalNumber("timeout") ?? 15
        guard timeout > 0, timeout <= 300 else { throw Failure("timeout must be greater than 0 and at most 300 seconds.") }
        return try Expected(target: Selector.parse(fields), timeout: timeout)
    }
}

public enum Action {
    case point(Selector)
    case click(Selector)
    case type(Selector, String)
    case select(Selector, String)
    case press(String)
    case scroll(Selector, String, Int)
    case wait(Expected)
    case setValue(Selector, String)
    case verb(String, Selector)

    static func parse(_ value: Any) throws -> Action {
        let fields = try Fields(value, keys: ["point", "click", "type", "select", "press", "scroll", "wait",
                                              "set-value", "clear", "focus", "check", "uncheck", "toggle", "expand", "collapse", "scroll-to"])
        guard fields.values.count == 1, let (key, value) = fields.values.first else { throw Failure("An action must contain exactly one command.") }
        switch key {
        case "point": return try .point(Selector.parse(value))
        case "click": return try .click(Selector.parse(value))
        case "press": return try .press(fields.string("press", max: 128))
        case "wait": return try .wait(Expected.parse(value))
        case "set-value":
            let input = try Fields(value, keys: ["target", "text"])
            return try .setValue(Selector.parse(input.required("target")), input.string("text", max: 10_000))
        case "clear", "focus", "check", "uncheck", "toggle", "expand", "collapse", "scroll-to":
            return try .verb(key, Selector.parse(value))
        case "type":
            let input = try Fields(value, keys: ["target", "text"])
            return try .type(Selector.parse(input.required("target")), input.string("text", max: 10_000))
        case "select":
            let input = try Fields(value, keys: ["target", "option"])
            return try .select(Selector.parse(input.required("target")), input.string("option"))
        case "scroll":
            let input = try Fields(value, keys: ["target", "direction", "amount"])
            let direction = try input.string("direction")
            let amount = try input.optionalNumber("amount") ?? 3
            guard ["up", "down", "left", "right"].contains(direction), amount >= 1, amount <= 1000, amount.rounded() == amount else {
                throw Failure("scroll needs a valid direction and an integer amount from 1 to 1000.")
            }
            return try .scroll(Selector.parse(input.required("target")), direction, Int(amount))
        default: throw Failure("Unsupported action: \(key)")
        }
    }
}

struct Fields {
    let values: [String: Any]
    init(_ value: Any, keys: Set<String>) throws {
        guard let object = value as? [String: Any] else { throw Failure("Expected a JSON object.") }
        let unknown = Set(object.keys).subtracting(keys)
        guard unknown.isEmpty else { throw Failure("Unknown field(s): \(unknown.sorted().joined(separator: ", ")).") }
        values = object
    }
    func required(_ key: String) throws -> Any {
        guard let value = values[key] else { throw Failure("Missing field: \(key).") }
        return value
    }
    func string(_ key: String, max: Int = 1000) throws -> String {
        guard let value = try required(key) as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.count <= max, !value.contains("\0") else { throw Failure("\(key) must be nonempty text of at most \(max) characters.") }
        return value
    }
    func optionalString(_ key: String, max: Int = 1000) throws -> String? {
        values[key] == nil ? nil : try string(key, max: max)
    }
    func number(_ key: String) throws -> Double {
        guard let value = try required(key) as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else {
            throw Failure("\(key) must be a finite number.")
        }
        return value.doubleValue
    }
    func optionalNumber(_ key: String) throws -> Double? { values[key] == nil ? nil : try number(key) }
    func optionalObject(_ key: String, keys: Set<String>) throws -> Fields? {
        try values[key].map { try Fields($0, keys: keys) }
    }
    func array(_ key: String, default fallback: [Any]? = nil) throws -> [Any] {
        if values[key] == nil, let fallback { return fallback }
        guard let value = try required(key) as? [Any] else { throw Failure("\(key) must be an array.") }
        return value
    }
}
