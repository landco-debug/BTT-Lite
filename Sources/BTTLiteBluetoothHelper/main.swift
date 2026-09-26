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

let wanted = normalizedAddress(requestedAddress)
let paired = IOBluetoothDevice.pairedDevices().compactMap { $0 as? IOBluetoothDevice }

guard let device = paired.first(where: { candidate in
    if !wanted.isEmpty, let address = candidate.addressString,
       normalizedAddress(address) == wanted {
        return true
    }
    if !requestedName.isEmpty {
        let name = candidate.name ?? candidate.nameOrAddress ?? ""
        return name.caseInsensitiveCompare(requestedName) == .orderedSame
    }
    return false
}) else {
    fputs("Bluetooth device is not present in the paired-device list\n", stderr)
    exit(2)
}

guard device.isPaired() else {
    fputs("Bluetooth device is not paired\n", stderr)
    exit(4)
}

if device.isConnected() {
    // A single closeConnection can report success before every profile/transport
    // has fully dropped. Mirror mature CLI tools and retry for a few seconds.
    for _ in 0..<10 {
        let status = device.closeConnection()
        if !device.isConnected() {
            print("disconnected")
            exit(0)
        }
        if status != kIOReturnSuccess {
            fputs("Bluetooth disconnect failed: \(status)\n", stderr)
            exit(3)
        }
        Thread.sleep(forTimeInterval: 0.50)
    }
    exit(device.isConnected() ? 3 : 0)
} else {
    // openConnection() is synchronous for IOBluetoothDevice, but sleeping devices
    // can need more than one page attempt on current macOS hardware.
    var lastStatus: IOReturn = kIOReturnSuccess
    for _ in 0..<3 {
        lastStatus = device.openConnection()
        if device.isConnected() {
            print("connected")
            exit(0)
        }
        Thread.sleep(forTimeInterval: 0.75)
    }
    fputs("Bluetooth connect failed: \(lastStatus)\n", stderr)
    exit(3)
}
