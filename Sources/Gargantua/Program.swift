import Foundation
import Oracle

enum Program {
    static let version = "0.1.0"

    @MainActor
    static func run(_ options: Options) {
        switch options.command {
        case .version:
            Console.line("gargantua \(version)")
        case .constants:
            FileHandle.standardOutput.write(Data(MetalHeader.render().utf8))
        case .interactive:
            Application.run(options)
        case .still(let path):
            Still.render(options, path: path)
        case .bench:
            Bench.run(options)
        case .validate:
            Validate.run(options)
        }
    }
}
