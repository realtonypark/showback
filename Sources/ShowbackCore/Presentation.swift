import AppKit

public struct PointerFrame: Equatable {
    let x: Double
    let y: Double
    let target: CGRect
    let scale: Double
}

public struct PointerMark: Codable, Sendable {
    let time: Double
    let box: Box
    let fromX: Double
    let fromY: Double
    let unit: Double
    let travel: Double
}

public struct PointerTimeline: Codable, Sendable {
    public private(set) var marks: [PointerMark] = []
    public init() {}

    mutating func point(at time: Double, target: Box, viewport: Box, travel: Double = 0.32) throws {
        let x = (target.x + target.width / 2 - viewport.x) / viewport.width
        let y = (target.y + target.height / 2 - viewport.y) / viewport.height
        guard [x, y].allSatisfy(\.isFinite), (0...1).contains(x), (0...1).contains(y) else {
            throw Failure("The action target is outside the selected capture. Reveal offscreen content with scroll-to or a tested scroll action, then point or click. Check the selected window; do not widen capture to reach offscreen page content.")
        }
        let previous = frame(at: time, width: 1, height: 1)
        let box = Box(x: (target.x - viewport.x) / viewport.width, y: (target.y - viewport.y) / viewport.height,
                      width: target.width / viewport.width, height: target.height / viewport.height)
        marks.append(PointerMark(time: time, box: box, fromX: previous?.x ?? 0.5, fromY: previous?.y ?? 0.7,
                                 unit: 1 / viewport.width, travel: travel))
    }

    func frame(at time: Double, width: Double, height: Double) -> PointerFrame? {
        guard let mark = marks.last(where: { $0.time <= time }) else { return nil }
        let progress = mark.travel == 0 ? 1 : min(1, max(0, (time - mark.time) / mark.travel))
        let eased = progress * progress * (3 - 2 * progress)
        let x = mark.fromX + (mark.box.x + mark.box.width / 2 - mark.fromX) * eased
        let y = mark.fromY + (mark.box.y + mark.box.height / 2 - mark.fromY) * eased
        return PointerFrame(x: x * width, y: y * height,
                            target: CGRect(x: mark.box.x * width, y: mark.box.y * height,
                                           width: mark.box.width * width, height: mark.box.height * height),
                            scale: width * mark.unit)
    }

    func draw(in context: CGContext, size: CGSize, at time: Double) {
        guard let frame = frame(at: time, width: size.width, height: size.height) else { return }
        context.saveGState()
        defer { context.restoreGState() }
        let accent = CGColor(red: 0.1, green: 0.65, blue: 1, alpha: 0.85)
        context.setStrokeColor(accent)
        context.setLineWidth(2 * frame.scale)
        let rect = frame.target.insetBy(dx: -4 * frame.scale, dy: -4 * frame.scale)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 7 * frame.scale, cornerHeight: 7 * frame.scale, transform: nil))
        context.strokePath()
        context.translateBy(x: frame.x, y: frame.y)
        context.scaleBy(x: frame.scale, y: frame.scale)
        context.move(to: .zero)
        for point in [CGPoint(x: 0, y: 25), CGPoint(x: 7, y: 19), CGPoint(x: 13, y: 31),
                      CGPoint(x: 18, y: 28), CGPoint(x: 12, y: 17), CGPoint(x: 23, y: 17)] { context.addLine(to: point) }
        context.closePath()
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.setStrokeColor(CGColor(gray: 0.07, alpha: 1))
        context.setLineWidth(1.6)
        context.drawPath(using: .fillStroke)
    }

    func image(size: CGSize, at time: Double) -> CGImage? {
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: Int(size.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        draw(in: context, size: size, at: time)
        return context.makeImage()
    }
}

final class PointerImageCache: @unchecked Sendable {
    private let lock = NSLock()
    private let timeline: PointerTimeline
    private let size: CGSize
    private var frame: PointerFrame?
    private var bitmap: CGImage?

    init(timeline: PointerTimeline, size: CGSize) { self.timeline = timeline; self.size = size }

    func image(at time: Double) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        let current = timeline.frame(at: time, width: size.width, height: size.height)
        if current == frame { return bitmap }
        frame = current
        bitmap = current == nil ? nil : timeline.image(size: size, at: time)
        return bitmap
    }
}

@MainActor final class Presentation {
    private let panel: NSPanel
    private let view: PointerView
    private var timer: Timer?
    private var epoch: Double
    var timeline: PointerTimeline { view.timeline }

    init(viewport: Box, epoch: Double) {
        self.epoch = epoch
        panel = NSPanel(contentRect: Self.appKitFrame(viewport), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.level = .statusBar; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        view = PointerView(frame: CGRect(x: 0, y: 0, width: viewport.width, height: viewport.height))
        panel.contentView = view
        panel.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.view.time = ProcessInfo.processInfo.systemUptime - self.epoch
                self.view.needsDisplay = true
            }
        }
    }

    func point(target: Box, viewport: Box) async throws {
        panel.setFrame(Self.appKitFrame(viewport), display: true)
        let travel = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.0 : 0.32
        try view.timeline.point(at: ProcessInfo.processInfo.systemUptime - epoch, target: target, viewport: viewport, travel: travel)
        if travel > 0 { try await Task.sleep(nanoseconds: UInt64(travel * 1_000_000_000)) }
    }
    func begin(at epoch: Double) { self.epoch = epoch }
    func close() { timer?.invalidate(); timer = nil; panel.close() }

    static func appKitFrame(_ box: Box) -> CGRect {
        let primary = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID() }
        return CGRect(x: box.x, y: (primary?.frame.maxY ?? 0) - box.y - box.height, width: box.width, height: box.height)
    }
}

@MainActor private final class PointerView: NSView {
    var timeline = PointerTimeline()
    var time: Double = 0
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        timeline.draw(in: context, size: bounds.size, at: time)
    }
}
