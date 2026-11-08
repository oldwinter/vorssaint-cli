// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import IOKit

// Minimal SMC reader (fan RPM on Apple Silicon / Intel). Public IOKit only.
// Layout mirrors the classic C SMCKeyData_t (beltex/SMCKit port).

private let kSMCHandleYPCEvent: UInt32 = 2
private let kSMCReadKey: UInt8 = 5
private let kSMCWriteKey: UInt8 = 6
private let kSMCGetKeyInfo: UInt8 = 9

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCKeyDataVers { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
private struct SMCKeyDataPLimits { var version: UInt16 = 0; var length: UInt16 = 0; var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
private struct SMCKeyDataInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCKeyDataVers()
    var pLimitData = SMCKeyDataPLimits()
    var keyInfo = SMCKeyDataInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private func fourCC(_ s: String) -> UInt32 {
    s.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
}

enum SMC {
    nonisolated(unsafe) private static var connection: io_connect_t = 0
    nonisolated(unsafe) private static var opened = false

    private static func open() -> Bool {
        if opened { return connection != 0 }
        opened = true
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("AppleSMC"))
        guard svc != 0 else { return false }
        defer { IOObjectRelease(svc) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(svc, mach_task_self_, 0, &conn) == kIOReturnSuccess else { return false }
        connection = conn
        return true
    }

    private static func call(_ input: inout SMCKeyData) -> SMCKeyData? {
        guard open() else { return nil }
        var output = SMCKeyData()
        var outSize = MemoryLayout<SMCKeyData>.stride
        let kr = IOConnectCallStructMethod(connection, kSMCHandleYPCEvent,
                                         &input, MemoryLayout<SMCKeyData>.stride,
                                         &output, &outSize)
        guard kr == kIOReturnSuccess else { return nil }
        return output
    }

    private static func typeString(_ dt: UInt32) -> String {
        String(format: "%c%c%c%c", (dt >> 24) & 0xFF, (dt >> 16) & 0xFF, (dt >> 8) & 0xFF, dt & 0xFF)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func keyInfoStruct(_ key: String) -> SMCKeyDataInfo? {
        var infoIn = SMCKeyData()
        infoIn.key = fourCC(key)
        infoIn.data8 = kSMCGetKeyInfo
        guard let infoOut = call(&infoIn) else { return nil }
        return infoOut.keyInfo
    }

    /// Type string ("flt ", "fpe2", "sp78", …) and byte size for a key.
    static func keyInfo(_ key: String) -> (type: String, size: Int)? {
        guard let info = keyInfoStruct(key) else { return nil }
        return (typeString(info.dataType), Int(info.dataSize))
    }

    /// Read one SMC key → (type string, raw bytes). nil if unavailable.
    static func readKey(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard let info = keyInfoStruct(key) else { return nil }

        var read = SMCKeyData()
        read.key = fourCC(key)
        read.keyInfo = info
        read.data8 = kSMCReadKey
        guard let out = call(&read), out.result == 0 else { return nil }

        let size = min(Int(info.dataSize), 32)
        let raw = withUnsafeBytes(of: out.bytes) { Array($0.prefix(size)) }
        return (typeString(info.dataType), raw)
    }

    /// Write raw bytes to an SMC key. The byte count must match the key size.
    static func writeKey(_ key: String, bytes: [UInt8]) -> Bool {
        guard let info = keyInfoStruct(key),
              bytes.count == Int(info.dataSize),
              bytes.count <= 32 else { return false }
        var input = SMCKeyData()
        input.key = fourCC(key)
        input.keyInfo = info
        input.data8 = kSMCWriteKey
        withUnsafeMutableBytes(of: &input.bytes) { ptr in
            for (i, b) in bytes.enumerated() { ptr[i] = b }
        }
        guard let out = call(&input) else { return false }
        return out.result == 0
    }

    /// Encode `value` in the key's existing SMC type and write it.
    static func writeNumber(_ key: String, _ value: Double) -> Bool {
        guard let info = keyInfoStruct(key) else { return false }
        let type = typeString(info.dataType)
        let size = Int(info.dataSize)
        var bytes: [UInt8] = []
        if type.hasPrefix("flt"), size == 4 {
            var be = Float(value).bitPattern.bigEndian
            bytes = withUnsafeBytes(of: &be) { Array($0) }
        } else if type.hasPrefix("fpe2"), size == 2 {
            var be = UInt16(clamping: Int((value * 4).rounded())).bigEndian
            bytes = withUnsafeBytes(of: &be) { Array($0) }
        } else if type.hasPrefix("sp"), size == 2 {
            let frac = Int(String(type.last!), radix: 16) ?? 0
            var be = Int16(clamping: Int((value * Double(1 << frac)).rounded())).bigEndian
            bytes = withUnsafeBytes(of: &be) { Array($0) }
        } else if type.hasPrefix("ui"), size == 1 {
            bytes = [UInt8(clamping: Int(value))]
        } else if type.hasPrefix("ui"), size == 2 {
            var be = UInt16(clamping: Int(value)).bigEndian
            bytes = withUnsafeBytes(of: &be) { Array($0) }
        } else if type.hasPrefix("ui"), size == 4 {
            var be = UInt32(clamping: Int(value)).bigEndian
            bytes = withUnsafeBytes(of: &be) { Array($0) }
        } else {
            return false
        }
        return writeKey(key, bytes: bytes)
    }

    static func readFloat(_ key: String) -> Double? {
        guard let (type, b) = readKey(key) else { return nil }
        if type.hasPrefix("flt"), b.count >= 4 {
            return Double(Float(bitPattern: UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])))
        }
        if type.hasPrefix("fpe2"), b.count >= 2 {
            return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4.0
        }
        if type.hasPrefix("sp"), b.count >= 2 {
            let frac = Int(String(type.last!), radix: 16) ?? 0
            return Double(Int(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1])))) / Double(1 << frac)
        }
        if type.hasPrefix("ui"), let first = b.first { return Double(first) }
        return nil
    }

    struct Fan: Encodable { var index: Int, rpm: Double, minRpm: Double, maxRpm: Double }

    static func fans() -> [Fan] {
        guard let n = readFloat("FNum"), n > 0 else { return [] }
        var out: [Fan] = []
        for i in 0..<Int(n) {
            let p = String(format: "F%d", i)
            guard let ac = readFloat("\(p)Ac") else { continue }
            out.append(Fan(index: i, rpm: ac, minRpm: readFloat("\(p)Mn") ?? 0, maxRpm: readFloat("\(p)Mx") ?? 0))
        }
        return out
    }
}
