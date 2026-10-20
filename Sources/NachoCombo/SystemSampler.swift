import Foundation
import Darwin
import NachoComboCore

/// Thin wrappers over Mach / BSD counters. Pure math lives in NachoComboCore.
enum SystemSampler {
    static func cpuTicks() -> CPUTicks? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1),
                        idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3))
    }

    /// "Memory used" the way Activity Monitor reports it: app + wired + compressed.
    static func memory() -> (used: UInt64, total: UInt64)? {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(getpagesize())
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return (pages * page, ProcessInfo.processInfo.physicalMemory)
    }

    static func networkCounters() -> [String: (rx: UInt64, tx: UInt64)] {
        var result: [String: (rx: UInt64, tx: UInt64)] = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return result }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let entry = current.pointee
            if let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               let data = entry.ifa_data,
               (entry.ifa_flags & UInt32(IFF_UP)) != 0, (entry.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 {
                let name = String(cString: entry.ifa_name)
                let counters = data.assumingMemoryBound(to: if_data.self).pointee
                result[name] = (UInt64(counters.ifi_ibytes), UInt64(counters.ifi_obytes))
            }
            cursor = entry.ifa_next
        }
        return result
    }
}
