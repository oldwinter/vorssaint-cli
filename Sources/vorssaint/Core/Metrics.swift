// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import IOKit.ps

// MARK: - CPU

struct CPUTicks {
    var user: Double = 0, sys: Double = 0, idle: Double = 0, nice: Double = 0
    var total: Double { user + sys + idle + nice }

    static func sample() -> CPUTicks {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return CPUTicks() }
        return CPUTicks(user: Double(info.cpu_ticks.0), sys: Double(info.cpu_ticks.1),
                        idle: Double(info.cpu_ticks.2), nice: Double(info.cpu_ticks.3))
    }

    static func usage(between a: CPUTicks, and b: CPUTicks) -> (used: Double, user: Double, sys: Double, idle: Double) {
        let dUser = b.user - a.user, dSys = b.sys - a.sys, dIdle = b.idle - a.idle, dNice = b.nice - a.nice
        let dTotal = max(1e-9, dUser + dSys + dIdle + dNice)
        let busy = (dUser + dSys + dNice) / dTotal * 100
        return (busy, dUser / dTotal * 100, (dSys + dNice) / dTotal * 100, dIdle / dTotal * 100)
    }
}

// MARK: - Memory

struct MemStats: Encodable {
    var totalBytes: UInt64, usedBytes: UInt64, freeBytes: UInt64
    var activeBytes: UInt64, wiredBytes: UInt64, compressedBytes: UInt64, purgeableBytes: UInt64
    var swapTotalBytes: UInt64, swapUsedBytes: UInt64
    var usedPercent: Double
}

enum Memory {
    static func stats() -> MemStats {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize = vm_size_t(0)
        host_page_size(mach_host_self(), &pageSize)
        let ps = UInt64(pageSize)

        var total: UInt64 = 0
        var sz = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &sz, nil, 0)

        var swap = xsw_usage()
        sz = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &sz, nil, 0)

        guard kr == KERN_SUCCESS else { return MemStats(totalBytes: total, usedBytes: 0, freeBytes: 0, activeBytes: 0, wiredBytes: 0, compressedBytes: 0, purgeableBytes: 0, swapTotalBytes: 0, swapUsedBytes: 0, usedPercent: 0) }

        let active = UInt64(vm.active_count) * ps
        let wired = UInt64(vm.wire_count) * ps
        let compressed = UInt64(vm.compressor_page_count) * ps
        let purgeable = UInt64(vm.purgeable_count) * ps
        let free = UInt64(vm.free_count) * ps + UInt64(vm.speculative_count) * ps
        let used = active + wired + compressed
        return MemStats(
            totalBytes: total, usedBytes: used, freeBytes: free + purgeable,
            activeBytes: active, wiredBytes: wired, compressedBytes: compressed, purgeableBytes: purgeable,
            swapTotalBytes: swap.xsu_total, swapUsedBytes: swap.xsu_used,
            usedPercent: total > 0 ? Double(used) / Double(total) * 100 : 0
        )
    }
}

// MARK: - Disk

struct DiskStats: Encodable {
    var mount: String, totalBytes: UInt64, freeBytes: UInt64, usedBytes: UInt64, usedPercent: Double
}

enum Disk {
    static func stats(path: String = "/") -> DiskStats? {
        guard let a = try? FileManager.default.attributesOfFileSystem(forPath: path),
              let total = a[.systemSize] as? UInt64,
              let free = a[.systemFreeSize] as? UInt64 else { return nil }
        let used = total - free
        return DiskStats(mount: path, totalBytes: total, freeBytes: free, usedBytes: used,
                         usedPercent: total > 0 ? Double(used) / Double(total) * 100 : 0)
    }
}

// MARK: - Battery

struct BatteryStats: Encodable {
    var present: Bool, charging: Bool, onAC: Bool
    var percent: Int, cycleCount: Int?, temperatureC: Double?, timeToEmptyMin: Int?
}

enum Battery {
    static func stats() -> BatteryStats {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let src = list.first,
              let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any] else {
            return BatteryStats(present: false, charging: false, onAC: false, percent: 0, cycleCount: nil, temperatureC: nil, timeToEmptyMin: nil)
        }
        let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maxc = (d[kIOPSMaxCapacityKey] as? Int).map { max(1, $0) } ?? 100
        let charging = d[kIOPSIsChargingKey] as? Bool ?? false
        let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let tte = d[kIOPSTimeToEmptyKey] as? Int
        var cycles: Int?
        var temp: Double?
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("AppleSmartBattery"))
        if svc != 0 {
            if let c = IORegistryEntryCreateCFProperty(svc, "CycleCount" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int { cycles = c }
            if let t = IORegistryEntryCreateCFProperty(svc, "Temperature" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Double { temp = t / 100 }
            IOObjectRelease(svc)
        }
        return BatteryStats(present: true, charging: charging, onAC: onAC,
                            percent: cur * 100 / maxc, cycleCount: cycles, temperatureC: temp,
                            timeToEmptyMin: (tte ?? -1) >= 0 ? tte : nil)
    }
}

// MARK: - Network counters

struct IfaceCounters: Encodable {
    var name: String, rxBytes: UInt64, txBytes: UInt64
}

enum NetCounters {
    static func sample() -> [IfaceCounters] {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return [] }
        defer { freeifaddrs(first) }
        var acc: [String: (rx: UInt64, tx: UInt64)] = [:]
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            defer { p = cur.pointee.ifa_next }
            guard let sa = cur.pointee.ifa_addr, Int32(sa.pointee.sa_family) == AF_LINK,
                  let data = cur.pointee.ifa_data else { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            let name = String(cString: cur.pointee.ifa_name)
            let e = acc[name] ?? (0, 0)
            acc[name] = (e.rx + UInt64(d.ifi_ibytes), e.tx + UInt64(d.ifi_obytes))
        }
        return acc.filter { $0.key.hasPrefix("en") || $0.key.hasPrefix("awdl") || $0.key.hasPrefix("llw") || $0.key.hasPrefix("lo") }
            .map { IfaceCounters(name: $0.key, rxBytes: $0.value.rx, txBytes: $0.value.tx) }
            .sorted { $0.name < $1.name }
    }

    static func addresses() -> [(name: String, family: String, addr: String)] {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return [] }
        defer { freeifaddrs(first) }
        var out: [(String, String, String)] = []
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            defer { p = cur.pointee.ifa_next }
            guard let sa = cur.pointee.ifa_addr else { continue }
            let fam = Int32(sa.pointee.sa_family)
            guard fam == AF_INET || fam == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            var serv = [CChar](repeating: 0, count: Int(NI_MAXSERV))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), &serv, socklen_t(serv.count), NI_NUMERICHOST) == 0 {
                let name = String(cString: cur.pointee.ifa_name)
                guard name.hasPrefix("en") || name == "lo0" else { continue }
                out.append((name, fam == AF_INET ? "ipv4" : "ipv6", String(decoding: host.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self)))
            }
        }
        return out.sorted { $0.0 < $1.0 }
    }
}

// MARK: - Load average / uptime

enum Sys {
    static func loadAvg() -> [Double] {
        var l = [Double](repeating: 0, count: 3)
        getloadavg(&l, 3)
        return l
    }
    static func uptimeSeconds() -> TimeInterval {
        var tv = timeval()
        var sz = MemoryLayout<timeval>.size
        var mib = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &tv, &sz, nil, 0) == 0 else { return 0 }
        return Date().timeIntervalSince1970 - TimeInterval(tv.tv_sec)
    }
    static func hostInfo() -> (model: String, chip: String, cores: Int, os: String) {
        var chip = [CChar](repeating: 0, count: 256)
        var sz = chip.count
        sysctlbyname("hw.model", &chip, &sz, nil, 0)
        var brand = [CChar](repeating: 0, count: 256)
        var bsz = brand.count
        sysctlbyname("machdep.cpu.brand_string", &brand, &bsz, nil, 0)
        var ncpu: Int32 = 0
        var nsz = MemoryLayout<Int32>.size
        sysctlbyname("hw.ncpu", &ncpu, &nsz, nil, 0)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        func str(_ arr: [CChar]) -> String {
            String(decoding: arr.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self)
        }
        return (str(chip), bsz > 1 ? str(brand) : str(chip),
                Int(ncpu), "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)")
    }
}

// MARK: - Formatting helpers

func fmtBytes(_ b: UInt64, digits: Int = 1) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var v = Double(b), i = 0
    while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
    return i == 0 ? "\(Int(v)) \(units[i])" : String(format: "%.\(digits)f %@", v, units[i])
}

func fmtBytesSigned(_ v: Double) -> String { fmtBytes(UInt64(max(0, v))) }

func fmtDuration(_ s: TimeInterval) -> String {
    let t = Int(s)
    if t < 60 { return "\(t)s" }
    if t < 3600 { return "\(t / 60)m \(t % 60)s" }
    return "\(t / 3600)h \((t % 3600) / 60)m"
}
