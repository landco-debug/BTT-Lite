// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BTTLite",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "BTTLite", targets: ["BTTLite"])
    ],
    targets: [
        .executableTarget(
            name: "BTTLite",
            path: "Sources/BTTLite"
        )
    ]
)
