import Foundation

public enum RunStatus: String { case preparing, running, completed, failed, cancelled }

public final class RunBundle {
    public let root: URL
    private let title: String
    private let recording: Bool
    private var result: [String: Any]
    private var events: [[String: Any]] = []

    public init(root: URL, script: URL, title: String, recording: Bool) throws {
        self.root = root
        self.title = title; self.recording = recording
        result = ["version": 1, "title": title, "status": RunStatus.preparing.rawValue,
                  "recording": recording, "createdAt": ISO8601DateFormatter().string(from: Date())]
        let fm = FileManager.default
        guard !fm.fileExists(atPath: root.path) else { throw Failure("Bundle already exists: \(root.path)") }
        try fm.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        try fm.copyItem(at: script, to: root.appendingPathComponent("script.json"))
        try fm.createDirectory(at: root.appendingPathComponent("narration"), withIntermediateDirectories: false)
        if recording {
            try fm.createDirectory(at: root.appendingPathComponent("frames"), withIntermediateDirectories: false)
            try Data().write(to: root.appendingPathComponent(".incomplete"))
        }
        try save()
    }

    func start(target: [String: Any], epoch: Double) throws {
        result["status"] = RunStatus.running.rawValue
        result["target"] = target
        result["clockEpoch"] = epoch
        try save()
    }

    func record(_ kind: String, at time: Double, scene: Int? = nil, data: Any? = nil) throws {
        var event: [String: Any] = ["kind": kind, "time": max(0, time)]
        if let scene { event["scene"] = scene }
        if let data { event["data"] = data }
        events.append(event)
        try save()
    }

    func media(pointer: PointerTimeline, narration: [NarrationSegment]) throws {
        result["pointer"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(pointer))
        result["narration"] = narration.map { ["path": $0.url.path.replacingOccurrences(of: root.path + "/", with: ""),
                                               "start": $0.start, "duration": $0.duration] as [String: Any] }
        try save()
    }

    public func finish(_ status: RunStatus, error: String?, mediaReady: Bool) throws {
        guard [.completed, .failed, .cancelled].contains(status) else { throw Failure("Invalid final run status.") }
        let video = root.appendingPathComponent("demo.mp4")
        if status == .completed, recording, !mediaReady { throw Failure("A recorded run cannot succeed without a finalized MP4.") }
        if mediaReady {
            guard FileManager.default.fileExists(atPath: video.path),
                  (try video.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else { throw Failure("The finalized MP4 is missing.") }
        }
        result["status"] = status.rawValue
        result["mediaReady"] = mediaReady
        if let error { result["error"] = error }
        try save()
        var summary = "# \(title)\n\nStatus: \(status.rawValue)\n"
        if let error { summary += "\n\(error)\n" }
        if mediaReady { summary += "\nVideo: \(video.path)\n" }
        summary += "\nRun details: \(root.appendingPathComponent("run.json").path)\n"
        for event in events where event["kind"] as? String == "checked" {
            summary += "\n- Scene \(event["scene"] ?? "?"): expected state observed at \(event["time"] ?? 0) seconds."
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
