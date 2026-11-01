import ShowbackCore
import Foundation
do {
    if try await !CLI.perform(Array(CommandLine.arguments.dropFirst())) { throw Failure("Unknown command. Run showback --help.") }
} catch {
    FileHandle.standardError.write(Data(("showback: \(error.localizedDescription)\n").utf8))
    exit(1)
}
