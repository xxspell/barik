import Foundation
import IOKit

private enum SMCDataType: String {
    case ui8 = "ui8 "
    case ui16 = "ui16"
    case ui32 = "ui32"
    case sp1e = "sp1e"
    case sp3c = "sp3c"
    case sp4b = "sp4b"
    case sp5a = "sp5a"
    case spa5 = "spa5"
    case sp69 = "sp69"
    case sp78 = "sp78"
    case sp87 = "sp87"
    case sp96 = "sp96"
    case spb4 = "spb4"
    case spf0 = "spf0"
    case flt = "flt "
    case fpe2 = "fpe2"
}

private enum SMCCommand: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case readKeyInfo = 9
}

private struct SMCKeyData {
    typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    struct KeyInfo {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = (major: UInt8(0), minor: UInt8(0), build: UInt8(0), reserved: UInt8(0), release: UInt16(0))
    var pLimitData = (version: UInt16(0), length: UInt16(0), cpuPLimit: UInt32(0), gpuPLimit: UInt32(0), memPLimit: UInt32(0))
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

private struct SMCValue {
    let key: String
    var dataSize: UInt32 = 0
    var dataType: String = ""
    var bytes: [UInt8] = Array(repeating: 0, count: 32)
}

private extension FourCharCode {
    init(fourCharacterString string: String) {
        precondition(string.count == 4)
        self = string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    func fourCharacterString() -> String {
        String(describing: UnicodeScalar(self >> 24 & 0xff)!)
            + String(describing: UnicodeScalar(self >> 16 & 0xff)!)
            + String(describing: UnicodeScalar(self >> 8 & 0xff)!)
            + String(describing: UnicodeScalar(self & 0xff)!)
    }
}

private extension UInt16 {
    init(bytes: (UInt8, UInt8)) {
        self = UInt16(bytes.0) << 8 | UInt16(bytes.1)
    }
}

private extension UInt32 {
    init(bytes: (UInt8, UInt8, UInt8, UInt8)) {
        self = UInt32(bytes.0) << 24 | UInt32(bytes.1) << 16 | UInt32(bytes.2) << 8 | UInt32(bytes.3)
    }
}

private extension Int {
    init(fromFPE2 bytes: (UInt8, UInt8)) {
        self = (Int(bytes.0) << 6) + (Int(bytes.1) >> 2)
    }
}

private extension Float {
    init?(_ bytes: [UInt8]) {
        self = bytes.withUnsafeBytes { rawBuffer in
            rawBuffer.load(fromByteOffset: 0, as: Self.self)
        }
    }
}

final class SMCReader {
    static let shared = SMCReader()

    private let lock = NSLock()
    private var connection: io_connect_t = 0

    private init() {
        _ = openConnection()
    }

    deinit {
        closeConnection()
    }

    func readValue(for key: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }

        guard ensureConnection() else { return nil }

        var value = SMCValue(key: key)
        guard read(&value) == kIOReturnSuccess else { return nil }
        return decode(value)
    }

    private func ensureConnection() -> Bool {
        connection != 0 || openConnection()
    }

    private func openConnection() -> Bool {
        closeConnection()

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleSMC")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == kIOReturnSuccess else { return false }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
        return openResult == kIOReturnSuccess
    }

    private func closeConnection() {
        guard connection != 0 else { return }
        IOServiceClose(connection)
        connection = 0
    }

    private func decode(_ value: SMCValue) -> Double? {
        guard value.dataSize > 0 else { return nil }
        if value.bytes.first(where: { $0 != 0 }) == nil { return nil }

        switch value.dataType {
        case SMCDataType.ui8.rawValue:
            return Double(value.bytes[0])
        case SMCDataType.ui16.rawValue:
            return Double(UInt16(bytes: (value.bytes[0], value.bytes[1])))
        case SMCDataType.ui32.rawValue:
            return Double(UInt32(bytes: (value.bytes[0], value.bytes[1], value.bytes[2], value.bytes[3])))
        case SMCDataType.sp1e.rawValue:
            return Double(UInt16(value.bytes[0]) * 256 + UInt16(value.bytes[1])) / 16384
        case SMCDataType.sp3c.rawValue:
            return Double(UInt16(value.bytes[0]) * 256 + UInt16(value.bytes[1])) / 4096
        case SMCDataType.sp4b.rawValue:
            return Double(UInt16(value.bytes[0]) * 256 + UInt16(value.bytes[1])) / 2048
        case SMCDataType.sp5a.rawValue:
            return Double(UInt16(value.bytes[0]) * 256 + UInt16(value.bytes[1])) / 1024
        case SMCDataType.sp69.rawValue:
            return Double(UInt16(value.bytes[0]) * 256 + UInt16(value.bytes[1])) / 512
        case SMCDataType.sp78.rawValue:
            return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1])) / 256
        case SMCDataType.sp87.rawValue:
            return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1])) / 128
        case SMCDataType.sp96.rawValue:
            return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1])) / 64
        case SMCDataType.spa5.rawValue:
            return Double(UInt16(value.bytes[0]) * 256 + UInt16(value.bytes[1])) / 32
        case SMCDataType.spb4.rawValue:
            return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1])) / 16
        case SMCDataType.spf0.rawValue:
            return Double(Int(value.bytes[0]) * 256 + Int(value.bytes[1]))
        case SMCDataType.flt.rawValue:
            guard let floatValue = Float(value.bytes) else { return nil }
            return Double(floatValue)
        case SMCDataType.fpe2.rawValue:
            return Double(Int(fromFPE2: (value.bytes[0], value.bytes[1])))
        default:
            return nil
        }
    }

    private func read(_ value: inout SMCValue) -> kern_return_t {
        var input = SMCKeyData()
        var output = SMCKeyData()

        input.key = FourCharCode(fourCharacterString: value.key)
        input.data8 = SMCCommand.readKeyInfo.rawValue

        var result = call(command: .kernelIndex, input: &input, output: &output)
        guard result == kIOReturnSuccess else { return result }

        value.dataSize = UInt32(output.keyInfo.dataSize)
        value.dataType = output.keyInfo.dataType.fourCharacterString()

        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = SMCCommand.readBytes.rawValue

        result = call(command: .kernelIndex, input: &input, output: &output)
        guard result == kIOReturnSuccess else { return result }

        withUnsafeBytes(of: output.bytes) { rawBuffer in
            value.bytes.withUnsafeMutableBytes { destination in
                destination.copyBytes(from: rawBuffer.prefix(Int(value.dataSize)))
            }
        }
        return kIOReturnSuccess
    }

    private func call(
        command: SMCCommand,
        input: inout SMCKeyData,
        output: inout SMCKeyData
    ) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        return IOConnectCallStructMethod(
            connection,
            UInt32(command.rawValue),
            &input,
            inputSize,
            &output,
            &outputSize
        )
    }
}
