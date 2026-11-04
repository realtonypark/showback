import Foundation

enum RunStatus: String { case preparing, running, completed, failed, cancelled }

enum RunEvent: String {
    case scene, point, action, checked
    case absentChecked = "absent-checked"
    case narrationStart = "narration-start"
}

final class RunBundle {
    let root: URL
    private let title: String
    private let recording: Bool
    private var result: [String: Any]
    private var events: [[String: Any]] = []
    var video: URL? {
        (result["video"] as? String).map { URL(fileURLWithPath: $0) }
    }

    /// - Throws: `Failure` when the bundle already exists; file errors when the bundle cannot be created.
    init(root: URL, script: URL, title: String, recording: Bool) throws {
        self.root = root
        self.title = title; self.recording = recording
        result = ["version": 1, "title": title, "status": RunStatus.preparing.rawValue,
                  "recording": recording, "createdAt": ISO8601DateFormatter().string(from: Date())]
        guard !FileManager.default.fileExists(atPath: root.path) else { throw Failure("Bundle already exists: \(root.path)") }
        try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        do {
            try FileManager.default.copyItem(at: script, to: root.appendingPathComponent("script.json"))
            try FileManager.default.createDirectory(at: root.appendingPathComponent("narration"), withIntermediateDirectories: false)
            if recording {
                try FileManager.default.createDirectory(at: root.appendingPathComponent("frames"), withIntermediateDirectories: false)
                try Data().write(to: root.appendingPathComponent(".incomplete"))
            }
            try save()
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    /// - Throws: `Failure` when the target is not JSON-serializable.
    func start(target: [String: Any], epoch: Double) throws {
        guard JSONSerialization.isValidJSONObject(["target": target]) else {
            throw Failure("Cannot start run: target is not JSON-serializable.")
        }
        result["status"] = RunStatus.running.rawValue
        result["target"] = target
        result["clockEpoch"] = epoch
        try save()
    }

    /// - Throws: `Failure` when data is not JSON-serializable.
    func record(_ kind: RunEvent, at time: Double, scene: Int? = nil, data: Any? = nil) throws {
        var event: [String: Any] = ["kind": kind.rawValue, "time": max(0, time)]
        if let scene { event["scene"] = scene }
        if let data {
            guard JSONSerialization.isValidJSONObject(["data": data]) else {
                throw Failure("Cannot record \(kind.rawValue) event\(scene.map { " for scene \($0)" } ?? ""): payload is not JSON-serializable.")
            }
            event["data"] = data
        }
        events.append(event)
        try save()
    }

    func attachMedia(pointer: PointerTimeline, narration: [NarrationSegment]) throws {
        result["pointer"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(pointer))
        result["narration"] = narration.map { ["path": $0.url.path.replacingOccurrences(of: root.path + "/", with: ""),
                                               "start": $0.start, "duration": $0.duration] as [String: Any] }
        try save()
    }

    /// - Throws: `Failure` for an invalid final status or a missing MP4; file errors when the summary cannot be written.
    func finish(_ status: RunStatus, error: String?, mediaReady: Bool) throws {
        guard [.completed, .failed, .cancelled].contains(status) else { throw Failure("Invalid final run status.") }
        let video = root.appendingPathComponent("demo.mp4")
        if status == .completed, recording, !mediaReady { throw Failure("A recorded run cannot succeed without a finalized MP4.") }
        if mediaReady {
            guard FileManager.default.fileExists(atPath: video.path),
                  (try video.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else { throw Failure("The finalized MP4 is missing.") }
        }
        result["status"] = status.rawValue
        result["mediaReady"] = mediaReady
        result["video"] = mediaReady ? video.path : nil
        if let error { result["error"] = error }
        try save()
        var summary = "# \(title)\n\nStatus: \(status.rawValue)\n"
        if let error { summary += "\n\(error)\n" }
        if let video = self.video { summary += "\n\(status == .completed ? "Video" : "Partial video"): \(video.path)\n" }
        summary += "\nRun details: \(root.appendingPathComponent("run.json").path)\n"
        for event in events {
            guard let kindString = event["kind"] as? String, let kind = RunEvent(rawValue: kindString),
                  kind == .checked || kind == .absentChecked else { continue }
            let time = String(format: "%.2f", event["time"] as? Double ?? 0)
            let label = kind == .absentChecked ? "expected state absent" : "expected state observed"
            summary += "\n- Scene \(event["scene"] ?? "?"): \(label) at \(time)s."
        }
        try (summary + "\n").write(to: root.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
        if mediaReady || !recording {
            let marker = root.appendingPathComponent(".incomplete")
            if FileManager.default.fileExists(atPath: marker.path) { try FileManager.default.removeItem(at: marker) }
        }
    }

    private func save() throws {
        result["events"] = events
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: root.appendingPathComponent("run.json"), options: .atomic)
    }
}
