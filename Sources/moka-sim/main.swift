import Foundation
import MokaCore

let result = SimCommand.run(arguments: Array(CommandLine.arguments.dropFirst())) { path in
    FileManager.default.contents(atPath: path)
}
FileHandle.standardOutput.write(Data(result.stdout.utf8))
FileHandle.standardError.write(Data(result.stderr.utf8))
exit(result.exitCode)
