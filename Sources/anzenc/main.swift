import Foundation
import AnzenLib

enum CommandError: Error {
    case missingInput
}

func main(args: [String] = CommandLine.arguments) throws {
    // let programName    = args[0]
    let positionalArgs = args.dropFirst().filter { !$0.starts(with: "-") }
    // let optionalArgs   = args.dropFirst().filter { $0.starts(with: "-") }

    if positionalArgs.isEmpty {
        throw CommandError.missingInput
    }

    let source = try String(contentsOf: URL(fileURLWithPath: positionalArgs[0]))
    let module = try AnzenLib.parse(text: source)
    _ = try AnzenLib.performSema(on: module)
}

do {
    try main()
} catch AnzenLib.CompilerError.inferenceError(let file, let line) {
    let basename = file.split(separator: "/").last!
    print("inferenceError at \(basename):\(line)")
} catch let e {
    print(e.localizedDescription)
    exit(1)
}
exit(0)
