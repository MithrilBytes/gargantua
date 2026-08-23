import Foundation
import PackagePlugin

/// Embeds shader sources, the shared shader header, and golden definitions
/// into the executable as string literals, so the built binary is self
/// contained and the shaders can be compiled by the runtime Metal compiler.
@main
struct EmbedResources: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target as? SwiftSourceModuleTarget else { return [] }
        let shaders = target.directoryURL.appending(path: "Shaders")
        let types = context.package.directoryURL.appending(path: "Sources/ShaderTypes/include")
        let goldens = context.package.directoryURL.appending(path: "goldens")
        let directories = [shaders, types, goldens]
        let inputs = directories.flatMap { directory -> [URL] in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path())) ?? []
            return names.sorted().map { directory.appending(path: $0) }
        }
        let output = context.pluginWorkDirectoryURL.appending(path: "EmbeddedResources.swift")
        return [
            .buildCommand(
                displayName: "Embedding shaders and goldens",
                executable: try context.tool(named: "EmbedResourcesTool").url,
                arguments: [output.path()] + directories.map { $0.path() },
                inputFiles: inputs,
                outputFiles: [output]
            )
        ]
    }
}
