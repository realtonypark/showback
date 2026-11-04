import AppKit

@MainActor public enum Application {
    /// - Throws: `Failure` for usage errors or missing assets.
    public static func launch(_ arguments: [String]) throws -> Never {
        if arguments == ["run", "--help"] || arguments == ["run", "-h"] { print(CLI.help); exit(0) }
        let route = try LaunchRoute.parse(arguments)
        let app = NSApplication.shared
        app.setActivationPolicy(route.activationPolicy)
        let delegate = ApplicationDelegate(route: route)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(0)
    }
}

/// One interpretation of the command line, parsed before the app loop starts.
enum LaunchRoute {
    case run(options: RunOptions, assets: Assets)
    case settings(assets: Assets)
    case cli(arguments: [String])

    static func parse(_ arguments: [String], appBundle: Bool = Bundle.main.bundleURL.pathExtension == "app") throws -> LaunchRoute {
        if arguments.first == "run" {
            return .run(options: try RunOptions.parse(Array(arguments.dropFirst())), assets: try Paths.assets())
        }
        if arguments.first == "settings" || (arguments.isEmpty && appBundle) {
            guard arguments.count <= 1 else { throw Failure("Usage: showback settings") }
            return .settings(assets: try Paths.assets())
        }
        return .cli(arguments: arguments)
    }

    var activationPolicy: NSApplication.ActivationPolicy {
        switch self {
        case .settings: return .regular
        case .run, .cli: return .accessory
        }
    }
}

@MainActor private final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    let route: LaunchRoute
    var settings: SettingsWindow?
    var task: Task<Void, Never>?
    var signals: [DispatchSourceSignal] = []
    var stopSignals: UInt = 0
    init(route: LaunchRoute) {
        self.route = route
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch route {
        case .settings(let assets):
            if focusExistingSettings() { exit(0) }
            do { settings = try SettingsWindow(assets: assets); settings?.show() } catch { report(error); exit(1) }
        case .run(let options, let assets):
            for sig in [SIGINT, SIGTERM] {
                signal(sig, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
                source.setEventHandler { [weak self, weak source] in
                    guard let self, let source else { return }
                    self.stopSignals += source.data
                    if self.stopSignals >= 2 { _exit(130) }
                    self.task?.cancel()
                }
                source.resume(); signals.append(source)
            }
            task = Task { @MainActor in
                do {
                    let status = try await Runner(assets: assets).run(options) { [weak self] in self?.task?.cancel() }
                    exit(status == .completed ? 0 : status == .cancelled ? 130 : 1)
                } catch { report(error); exit(1) }
            }
        case .cli(let arguments):
            task = Task { @MainActor in
                do {
                    try await CLI.dispatch(arguments)
                    exit(0)
                } catch let status as ExitStatus {
                    exit(status.code)
                } catch {
                    report(error); exit(1)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if case .settings = route { return true }
        return false
    }

    private func focusExistingSettings() -> Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        let current = ProcessInfo.processInfo.processIdentifier
        guard let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first(where: { $0.processIdentifier != current && $0.activationPolicy == .regular }) else { return false }
        existing.activate(options: [.activateAllWindows])
        return true
    }

    private func report(_ error: Error) { FileHandle.standardError.write(Data(("showback: \(error.localizedDescription)\n").utf8)) }
}
