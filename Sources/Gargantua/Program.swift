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
        case .still:
            Exit.operational("Still rendering arrives with the march pass in a later milestone.")
        case .bench:
            Exit.operational("The bench subcommand arrives in a later milestone.")
        case .validate:
            Exit.operational("The validate subcommand arrives in a later milestone.")
        }
    }
}
