//
//  SystemStatsManager.swift
//  boringNotch
//
//  CPU, memory and network throughput for the closed notch.
//

import Combine
import Darwin
import Defaults
import Foundation

/// One moment of machine load. Kept in a rolling window so the stats tab can
/// draw where things have been, not just where they are.
struct SystemStatsSample: Identifiable, Equatable {
    let id = UUID()
    let cpu: Double
    let memory: Double
    let download: Double
    let upload: Double
    let date: Date
}

/// Samples the machine's load on a timer while something is displaying it.
///
/// Every figure here is a *delta* between samples — CPU ticks and interface
/// byte counters are cumulative since boot, so a single reading says nothing.
@MainActor
final class SystemStatsManager: ObservableObject {
    static let shared = SystemStatsManager()

    /// 0...1 across all cores.
    @Published private(set) var cpuUsage: Double = 0
    /// 0...1 of physical memory in use.
    @Published private(set) var memoryUsage: Double = 0
    /// Bytes per second, averaged over the last sample interval.
    @Published private(set) var downloadRate: Double = 0
    @Published private(set) var uploadRate: Double = 0

    /// Rolling window behind the graphs, oldest first.
    @Published private(set) var history: [SystemStatsSample] = []

    /// Two minutes at the sampling interval — enough to see a spike arrive and
    /// pass without the graph turning into noise.
    private static let historyLimit = 60

    private var sampleTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private var previousCPUTicks: (busy: Double, total: Double)?
    private var previousNetwork: (received: UInt64, sent: UInt64, date: Date)?

    /// Long enough that the numbers are readable rather than twitchy, short
    /// enough to feel live.
    private static let interval: Duration = .seconds(2)

    private init() {
        Defaults.publisher(.systemStatsEnabled)
            .sink { [weak self] change in
                Task { @MainActor in
                    if change.newValue {
                        self?.start()
                    } else {
                        self?.stop()
                    }
                }
            }
            .store(in: &cancellables)

        if Defaults[.systemStatsEnabled] {
            start()
        }
    }

    // MARK: Lifecycle

    func start() {
        guard sampleTask == nil else { return }
        sampleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        sampleTask?.cancel()
        sampleTask = nil
        previousCPUTicks = nil
        previousNetwork = nil
        cpuUsage = 0
        memoryUsage = 0
        downloadRate = 0
        uploadRate = 0
        history = []
    }

    // MARK: Sampling

    private func sample() {
        if let cpu = readCPUUsage() { cpuUsage = cpu }
        if let memory = readMemoryUsage() { memoryUsage = memory }
        readNetworkRates()

        history.append(
            SystemStatsSample(
                cpu: cpuUsage,
                memory: memoryUsage,
                download: downloadRate,
                upload: uploadRate,
                date: Date()
            )
        )
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
    }

    /// Largest throughput in the window, for scaling the network graph. Floored
    /// so a quiet network does not make noise look like traffic.
    var peakNetworkRate: Double {
        max(64 * 1024, history.map { max($0.download, $0.upload) }.max() ?? 0)
    }

    /// Busy share since the previous sample.
    private func readCPUUsage() -> Double? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)

        let busy = user + system + nice
        let total = busy + idle

        defer { previousCPUTicks = (busy, total) }
        guard let previous = previousCPUTicks else { return nil }

        let busyDelta = busy - previous.busy
        let totalDelta = total - previous.total
        guard totalDelta > 0 else { return nil }

        return min(1, max(0, busyDelta / totalDelta))
    }

    /// Share of physical memory that is not free — the figure Activity Monitor
    /// calls "memory used": resident, wired and compressed pages.
    private func readMemoryUsage() -> Double? {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return nil }

        return min(1, max(0, used / total))
    }

    /// Throughput across the physical interfaces, ignoring loopback and virtual
    /// ones so a busy VM bridge does not read as internet traffic.
    private func readNetworkRates() {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return }
        defer { freeifaddrs(addresses) }

        var received: UInt64 = 0
        var sent: UInt64 = 0

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }

            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }

            guard let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            received += UInt64(data.pointee.ifi_ibytes)
            sent += UInt64(data.pointee.ifi_obytes)
        }

        let now = Date()
        defer { previousNetwork = (received, sent, now) }
        guard let previous = previousNetwork else { return }

        let elapsed = now.timeIntervalSince(previous.date)
        guard elapsed > 0 else { return }

        // Counters reset when an interface goes away; a negative delta is that,
        // not a transfer.
        downloadRate = received >= previous.received ? Double(received - previous.received) / elapsed : 0
        uploadRate = sent >= previous.sent ? Double(sent - previous.sent) / elapsed : 0
    }

    // MARK: Formatting

    static func formatPercent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// Compact rate, e.g. "1.2 MB/s". Kept short: it shares the notch with the
    /// other side's reading.
    static func formatRate(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        // Without this a rate of nothing reads as "Zero KB/s".
        formatter.allowsNonnumericFormatting = false
        return "\(formatter.string(fromByteCount: Int64(max(0, bytesPerSecond))))/s"
    }
}
