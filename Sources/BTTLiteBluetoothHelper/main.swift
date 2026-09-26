import Foundation
import IOBluetooth

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: BTTLiteBluetoothHelper <bluetooth-address> [device-name]\n", stderr)
    exit(64)
}

let requestedAddress = args[1]
let requestedName = args.count >= 3 ? args[2] : ""

func normalizedAddress(_ value: String) -> String {
    let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
    return value.unicodeScalars
        .filter { allowed.contains($0) }
        .map(String.init)
        .joined()
        .lowercased()
}

func formattedAddress(_ normalized: String, separator: String) -> String? {
    guard normalized.count == 12 else { return nil }
    var parts: [String] = []
    var index = normalized.startIndex
    for _ in 0..<6 {
        let next = normalized.index(index, offsetBy: 2)
        parts.append(String(normalized[index..<next]))
        index = next
    }
    return parts.joined(separator: separator)
}

let wanted = normalizedAddress(requestedAddress)
let paired = IOBluetoothDevice.pairedDevices().compactMap { $0 as? IOBluetoothDevice }

var device = paired.first { candidate in
    guard let address = candidate.addressString else { return false }
    return !wanted.isEmpty && normalizedAddress(address) == wanted
}

if device == nil, !requestedName.isEmpty {
    device = paired.first { candidate in
        let name = candidate.name ?? candidate.nameOrAddress ?? ""
        return name.caseInsensitiveCompare(requestedName) == .orderedSame
    }
}

if device == nil, !wanted.isEmpty {
    var candidates = [requestedAddress]
    if let colon = formattedAddress(wanted, separator: ":") { candidates.append(colon) }
    if let hyphen = formattedAddress(wanted, separator: "-") { candidates.append(hyphen) }
    for candidate in candidates {
        if let resolved = IOBluetoothDevice(addressString: candidate) {
            device = resolved
            break
        }
    }
}

guard let device else {
    fputs("Bluetooth device not found\n", stderr)
    exit(2)
}

if device.isConnected() {
    var status: IOReturn = kIOReturnSuccess
    for _ in 0..<6 {
        status = device.closeConnection()
        if status != kIOReturnSuccess { break }
        if !device.isConnected() { exit(0) }
        Thread.sleep(forTimeInterval: 0.15)
    }
    exit(!device.isConnected() ? 0 : 3)
} else {
    let status = device.openConnection()
    guard status == kIOReturnSuccess else { exit(3) }
    for _ in 0..<20 {
        if device.isConnected() { exit(0) }
        Thread.sleep(forTimeInterval: 0.10)
    }
    exit(device.isConnected() ? 0 : 3)
}
