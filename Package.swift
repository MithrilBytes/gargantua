// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "gargantua",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "gargantua", targets: ["Gargantua"]),
        .library(name: "Oracle", targets: ["Oracle"]),
    ],
    targets: [
        .target(name: "ShaderTypes"),
        .target(name: "Oracle"),
        .executableTarget(
            name: "Gargantua",
            dependencies: ["Oracle", "ShaderTypes"],
            exclude: ["Shaders"],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("MetalFX"),
                .linkedFramework("AppKit"),
            ],
            plugins: ["EmbedResources"]
        ),
        .executableTarget(name: "EmbedResourcesTool"),
        .plugin(
            name: "EmbedResources",
            capability: .buildTool(),
            dependencies: ["EmbedResourcesTool"]
        ),
        .testTarget(name: "OracleTests", dependencies: ["Oracle"]),
        .testTarget(name: "StyleTests", dependencies: ["Oracle"]),
    ],
    swiftLanguageModes: [.v6]
)
