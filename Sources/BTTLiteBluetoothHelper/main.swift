import Foundation
import IOBluetooth
import IOKit

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

func ioReturnDescription(_ status: IOReturn) -> String {
    switch status {
    case kIOReturnSuccess: return "success"
    case kIOReturnBusy: return "device busy"
    case kIOReturnTimeout: return "I/O timeout"
    case kIOReturnOffline: return "device offline"
    case kIOReturnNotReady: return "device not ready"
    case kIOReturnNotAttached: return "device not attached"
    case kIOReturnNotPermitted: return "operation not permitted"
    default: return "IOReturn \(status)"
    }
}

func waitUntil(_ predicate: () -> Bool, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if predicate() { return true }
        Thread.sleep(forTimeInterval: 0.10)
    } while Date() < deadline
    return predicate()
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
    let status = device.closeConnection()
    if !device.isConnected() || waitUntil({ !device.isConnected() }, timeout: 2.5) {
        print("disconnected")
        exit(0)
    }

    fputs(
        "Bluetooth disconnect failed: \(ioReturnDescription(status)) (\(status)). " +
        "No automatic retry was made.\n",
        stderr
    )
    exit(3)
} else {
    let status = device.openConnection()

    if device.isConnected() || waitUntil({ device.isConnected() }, timeout: 2.0) {
        print("connected")
        exit(0)
    }

    fputs(
        "Bluetooth connect failed: \(ioReturnDescription(status)) (\(status)). " +
        "No automatic retry was made.\n",
        stderr
    )
    exit(3)
}
