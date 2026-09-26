// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BTTLite",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "BTTLite", targets: ["BTTLite"]),
        .executable(name: "BTTLiteBluetoothHelper", targets: ["BTTLiteBluetoothHelper"])
    ],
    targets: [
        .executableTarget(
            name: "BTTLite",
            path: "Sources/BTTLite"
        ),
        .executableTarget(
            name: "BTTLiteBluetoothHelper",
            path: "Sources/BTTLiteBluetoothHelper",
            linkerSettings: [.linkedFramework("IOBluetooth")]
        )
    ],
    swiftLanguageModes: [.v5]
)
