import Foundation
import IOBluetooth

let args = CommandLine.arguments

guard args.count >= 2 else {
    fputs("Usage: BTTLiteBluetoothHelper <bluetooth-address>\n", stderr)
    exit(64)
}

let address = args[1]
guard let device = IOBluetoothDevice(addressString: address) else {
    fputs("Bluetooth device not found\n", stderr)
    exit(2)
}

let status: IOReturn = device.isConnected() ? device.closeConnection() : device.openConnection()
exit(status == kIOReturnSuccess ? 0 : 3)
