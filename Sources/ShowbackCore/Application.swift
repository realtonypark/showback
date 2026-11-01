import AppKit

@MainActor public enum Application {
    public static func launch(_ arguments: [String]) throws -> Never {
        let options: RunOptions?
        let isSettings = arguments.first == "settings" || (arguments.isEmpty && Bundle.main.bundleURL.pathExtension == "app")
        if arguments.first == "run" { options = try RunOptions.parse(Array(arguments.dropFirst())) }
        else if isSettings {
            guard arguments.count <= 1 else { throw Failure("Usage: showback settings") }
            options = nil
        } else { options = nil }
        let assets = options != nil || isSettings ? try Paths.assets() : nil
        let app = NSApplication.shared
        app.setActivationPolicy(isSettings ? .regular : .accessory)
        let delegate = ApplicationDelegate(assets: assets, options: options, arguments: arguments, isSettings: isSettings)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(0)
    }
}

@MainActor private final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    let assets: Assets?
    let options: RunOptions?
    let arguments: [String]
    let isSettings: Bool
    var settings: SettingsWindow?
    var task: Task<Void, Never>?
    var signals: [DispatchSourceSignal] = []
    var stopSignals: UInt = 0
    init(assets: Assets?, options: RunOptions?, arguments: [String], isSettings: Bool) {
        self.assets = assets; self.options = options; self.arguments = arguments; self.isSettings = isSettings
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isSettings, let assets {
            do { settings = try SettingsWindow(assets: assets); settings?.show() }
            catch { report(error); exit(1) }
            return
        }
        guard let options, let assets else {
            task = Task { @MainActor in
                do {
                    guard try await CLI.perform(arguments) else { throw Failure("Unknown command. Run showback --help.") }
                    exit(0)
                } catch { report(error); exit(1) }
            }
            return
        }
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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { isSettings }
    private func report(_ error: Error) { FileHandle.standardError.write(Data(("showback: \(error.localizedDescription)\n").utf8)) }
}
