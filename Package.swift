// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LucideInline",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LucideInline",
            path: "Sources/LucideInline",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
