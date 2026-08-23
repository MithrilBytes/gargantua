import Foundation

switch Options.parse(Array(CommandLine.arguments.dropFirst())) {
case .success(let options):
    Program.run(options)
case .failure(let error):
    Exit.usage(error.sentence)
}
