import Darwin
import Foundation
import IOKit

/// Thin runtime-loaded bridge to Apple's private MultitouchSupport.framework.
/// Keeping all private ABI assumptions here makes the rest of BTT Lite ordinary Swift.
final class MultitouchBridge {
    struct Device {
        let reference: UnsafeMutableRawPointer
        let id: UInt
        let kind: GestureDevice
        let name: String
    }

    typealias FrameHandler = (_ device: Device, _ contacts: [RawTouchContact], _ uptime: TimeInterval) -> Void

    private static let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    private typealias ContactCallback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
    ) -> Int32
    private typealias CreateListFn = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer?, ContactCallback) -> Void
    private typealias StartFn = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
    private typealias StopFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    private typealias IsBuiltInFn = @convention(c) (UnsafeMutableRawPointer?) -> Bool
    private typealias GetServiceFn = @convention(c) (UnsafeMutableRawPointer?) -> io_service_t

    private enum ContactLayout {
        static let stride = 96
        static let pathIdentifier = 16
        static let state = 20
        static let fingerIdentifier = 24
        static let positionX = 32
        static let positionY = 36
        static let size = 48
        static let maximumContacts = 32
        static let positionBearingStates: ClosedRange<Int32> = 3...5
    }

    private let handle: UnsafeMutableRawPointer?
    private let createList: CreateListFn?
    private let register: RegisterFn?
    private let unregister: RegisterFn?
    private let startDevice: StartFn?
    private let stopDevice: StopFn?
    private let isBuiltIn: IsBuiltInFn?
    private let getService: GetServiceFn?

    private var deviceList: CFArray?
    private(set) var devices: [Device] = []

    private static let handlerLock = NSLock()
    private static var frameHandler: ((UnsafeMutableRawPointer, [RawTouchContact], TimeInterval) -> Void)?

    init() {
        let library = dlopen(Self.frameworkPath, RTLD_NOW | RTLD_LOCAL)
        handle = library

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let library, let pointer = dlsym(library, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }

        createList = symbol("MTDeviceCreateList", as: CreateListFn.self)
        register = symbol("MTRegisterContactFrameCallback", as: RegisterFn.self)
        unregister = symbol("MTUnregisterContactFrameCallback", as: RegisterFn.self)
        startDevice = symbol("MTDeviceStart", as: StartFn.self)
        stopDevice = symbol("MTDeviceStop", as: StopFn.self)
        isBuiltIn = symbol("MTDeviceIsBuiltIn", as: IsBuiltInFn.self)
        getService = symbol("MTDeviceGetService", as: GetServiceFn.self)
    }

    deinit {
        stop()
        // Deliberately do not dlclose the private framework. Its callback worker can
        // outlive unregistration for a moment; unloading executable code is unsafe.
    }

    var isAvailable: Bool {
        createList != nil && register != nil && unregister != nil && startDevice != nil && stopDevice != nil
    }

    @discardableResult
    func start(handler: @escaping FrameHandler) -> Bool {
        stop()
        guard isAvailable,
              let createList,
              let register,
              let startDevice,
              let listPointer = createList() else { return false }

        let list = Unmanaged<CFArray>.fromOpaque(listPointer).takeRetainedValue()
        deviceList = list

        var discovered: [Device] = []
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let reference = UnsafeMutableRawPointer(mutating: raw)
            discovered.append(describe(reference))
        }
        devices = discovered
        let byID = Dictionary(uniqueKeysWithValues: discovered.map { ($0.id, $0) })

        Self.setFrameHandler { reference, contacts, timestamp in
            let id = UInt(bitPattern: reference)
            guard let device = byID[id] else { return }
            let eventTime = timestamp.isFinite && timestamp > 0
                ? timestamp
                : ProcessInfo.processInfo.systemUptime
            handler(device, contacts, eventTime)
        }

        for device in discovered {
            register(device.reference, Self.contactCallback)
            _ = startDevice(device.reference, 0)
        }
        return !discovered.isEmpty
    }

    func stop() {
        Self.setFrameHandler(nil)
        if let unregister, let stopDevice {
            for device in devices {
                _ = stopDevice(device.reference)
                unregister(device.reference, Self.contactCallback)
            }
        }
        devices.removeAll(keepingCapacity: true)
        deviceList = nil
    }

    private func describe(_ reference: UnsafeMutableRawPointer) -> Device {
        let service = getService?(reference) ?? 0
        let name = registryString(service, "Product") ?? "Multitouch device"
        let width = registryNumber(service, "Sensor Surface Width") ?? 0
        let height = registryNumber(service, "Sensor Surface Height") ?? 0
        let builtIn = isBuiltIn?(reference) ?? false

        let lower = name.lowercased()
        let kind: GestureDevice
        if builtIn || lower.contains("trackpad") {
            kind = .trackpad
        } else if lower.contains("mouse") {
            kind = .magicMouse
        } else if width > 0, height > 0, width < height {
            kind = .magicMouse
        } else {
            kind = .trackpad
        }

        return Device(reference: reference, id: UInt(bitPattern: reference), kind: kind, name: name)
    }

    private func registryString(_ service: io_service_t, _ key: String) -> String? {
        guard service != 0 else { return nil }
        return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    private func registryNumber(_ service: io_service_t, _ key: String) -> Double? {
        guard service != 0 else { return nil }
        return (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber)?.doubleValue
    }

    private static func setFrameHandler(_ handler: ((UnsafeMutableRawPointer, [RawTouchContact], TimeInterval) -> Void)?) {
        handlerLock.lock()
        frameHandler = handler
        handlerLock.unlock()
    }

    private static func currentFrameHandler() -> ((UnsafeMutableRawPointer, [RawTouchContact], TimeInterval) -> Void)? {
        handlerLock.lock()
        defer { handlerLock.unlock() }
        return frameHandler
    }

    private static let contactCallback: ContactCallback = { device, touches, count, timestamp, _ in
        guard let device, let handler = MultitouchBridge.currentFrameHandler() else { return 0 }
        guard count >= 0, count <= ContactLayout.maximumContacts else { return 0 }

        var parsed: [RawTouchContact] = []
        if let touches, count > 0 {
            parsed.reserveCapacity(Int(count))
            for index in 0..<Int(count) {
                let record = touches.advanced(by: index * ContactLayout.stride)
                let state = record.load(fromByteOffset: ContactLayout.state, as: Int32.self)
                guard ContactLayout.positionBearingStates.contains(state) else { continue }

                let x = record.load(fromByteOffset: ContactLayout.positionX, as: Float32.self)
                let y = record.load(fromByteOffset: ContactLayout.positionY, as: Float32.self)
                let size = record.load(fromByteOffset: ContactLayout.size, as: Float32.self)
                guard x.isFinite, y.isFinite else { continue }

                parsed.append(RawTouchContact(
                    id: Int(record.load(fromByteOffset: ContactLayout.fingerIdentifier, as: Int32.self)),
                    x: min(max(Double(x), 0), 1),
                    y: min(max(Double(y), 0), 1),
                    size: size.isFinite ? Double(size) : 0
                ))
            }
        }
        handler(device, parsed, timestamp)
        return 0
    }
}
