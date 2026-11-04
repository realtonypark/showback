import Foundation
import ShowbackCore

@main struct ShowbackMain {
    @MainActor static func main() {
        do { try Application.launch(Array(CommandLine.arguments.dropFirst())) } catch {
            FileHandle.standardError.write(Data(("showback: \(error.localizedDescription)\n").utf8))
            exit(1)
        }
    }
}
