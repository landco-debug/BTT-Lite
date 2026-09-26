// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "BTTLite",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "BTTLite", targets: ["BTTLite"]),
        .executable(name: "BTTLiteBluetoothHelper", targets: ["BTTLiteBluetoothHelper"]),
        .executable(name: "BTTLiteJavaScriptHelper", targets: ["BTTLiteJavaScriptHelper"])
    ],
    targets: [
        .executableTarget(
            name: "BTTLite",
            path: "Sources/BTTLite",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "BTTLiteBluetoothHelper",
            path: "Sources/BTTLiteBluetoothHelper",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "BTTLiteJavaScriptHelper",
            path: "Sources/BTTLiteJavaScriptHelper",
            linkerSettings: [.linkedFramework("JavaScriptCore")]
        )
    ],
    swiftLanguageModes: [.v5]
)
