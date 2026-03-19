import Foundation
import Darwin

@MainActor
final class ResourceMonitor: ObservableObject {
    @Published private(set) var cpuUsagePercent: Double = 0
    @Published private(set) var usedMemoryBytes: UInt64 = 0
    @Published private(set) var totalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var appMemoryBytes: UInt64 = 0

    private var timer: Timer?
    private var previousCPULoad: host_cpu_load_info_data_t?

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    var statline: String {
        let cpu = String(format: "%.1f%%", cpuUsagePercent)
        return "CPU: \(cpu) | Mem: \(formatBytes(usedMemoryBytes))/\(formatBytes(totalMemoryBytes)) | App: \(formatBytes(appMemoryBytes))"
    }

    func start() {
        guard timer == nil else { return }
        sample()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        sampleCPU()
        sampleSystemMemory()
        sampleAppMemory()
    }

    private func sampleCPU() {
        var cpuInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &cpuInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }

        if let previous = previousCPULoad {
            let user = Double(cpuInfo.cpu_ticks.0 - previous.cpu_ticks.0)
            let system = Double(cpuInfo.cpu_ticks.1 - previous.cpu_ticks.1)
            let idle = Double(cpuInfo.cpu_ticks.2 - previous.cpu_ticks.2)
            let nice = Double(cpuInfo.cpu_ticks.3 - previous.cpu_ticks.3)

            let total = user + system + idle + nice
            if total > 0 {
                cpuUsagePercent = ((user + system + nice) / total) * 100.0
            }
        }

        previousCPULoad = cpuInfo
    }

    private func sampleSystemMemory() {
        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        let usedPages = UInt64(vmStats.active_count + vmStats.inactive_count + vmStats.wire_count + vmStats.compressor_page_count)
        usedMemoryBytes = usedPages * UInt64(pageSize)
        totalMemoryBytes = ProcessInfo.processInfo.physicalMemory
    }

    private func sampleAppMemory() {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }
        appMemoryBytes = info.phys_footprint
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        Self.byteFormatter.string(fromByteCount: Int64(bytes))
    }
}
