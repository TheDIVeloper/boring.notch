//
//  StatsView.swift
//  boringNotch
//
//  Tools: performance stats tab. Polls CPU, memory and network once a
//  second while the tab is visible, so it costs nothing when closed.
//

import Darwin
import Defaults
import SwiftUI

final class StatsManager: ObservableObject {
    @Published var cpuUsage: Double = 0
    @Published var memoryUsed: UInt64 = 0
    @Published var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published var netRxRate: UInt64 = 0
    @Published var netTxRate: UInt64 = 0

    private var timer: Timer?
    private var previousTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var previousBytes: (rx: UInt64, tx: UInt64)?
    private var previousSampleDate = Date()

    func start() {
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sample()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousTicks = nil
        previousBytes = nil
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleNetwork()
        previousSampleDate = Date()
    }

    private func sampleCPU() {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let ticks = (user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
        defer { previousTicks = ticks }
        guard let previous = previousTicks else { return }

        let userDelta = Double(ticks.user &- previous.user)
        let systemDelta = Double(ticks.system &- previous.system)
        let niceDelta = Double(ticks.nice &- previous.nice)
        let idleDelta = Double(ticks.idle &- previous.idle)
        let busy = userDelta + systemDelta + niceDelta
        let total = busy + idleDelta
        if total > 0 {
            cpuUsage = busy / total * 100.0
        }
    }

    private func sampleMemory() {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let pageSize = UInt64(vm_kernel_page_size)
        memoryUsed = (UInt64(stats.active_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)) * pageSize
        memoryTotal = ProcessInfo.processInfo.physicalMemory
    }

    private func sampleNetwork() {
        guard let bytes = interfaceByteCounters() else { return }
        defer { previousBytes = bytes }
        guard let previous = previousBytes else { return }

        let elapsed = Date().timeIntervalSince(previousSampleDate)
        guard elapsed > 0 else { return }
        netRxRate = wrappedDelta(bytes.rx, previous.rx) / UInt64(elapsed)
        netTxRate = wrappedDelta(bytes.tx, previous.tx) / UInt64(elapsed)
    }

    private func wrappedDelta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        if current >= previous {
            return current - previous
        }
        return (UInt64(UInt32.max) + 1) - previous + current
    }

    private func interfaceByteCounters() -> (rx: UInt64, tx: UInt64)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let data = current.pointee.ifa_data else { continue }
            let ifinfo = data.assumingMemoryBound(to: if_data.self).pointee
            rx += UInt64(ifinfo.ifi_ibytes)
            tx += UInt64(ifinfo.ifi_obytes)
        }
        return (rx, tx)
    }
}

struct StatsView: View {
    @StateObject private var stats = StatsManager()
    @ObservedObject private var speedTest = SpeedTestManager.shared
    @ObservedObject private var network = PerAppNetworkMonitor.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
            HStack {
                Text("Performance")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }

            statRow(
                icon: "gauge.with.dots.needle.50percent",
                label: "CPU",
                value: String(format: "%.0f%%", stats.cpuUsage),
                fraction: stats.cpuUsage / 100.0
            )

            statRow(
                icon: "memorychip",
                label: "Memory",
                value: "\(byteString(stats.memoryUsed)) of \(byteString(stats.memoryTotal))",
                fraction: stats.memoryTotal > 0 ? Double(stats.memoryUsed) / Double(stats.memoryTotal) : 0
            )

            HStack(spacing: 8) {
                Label {
                    Text("Down \(byteString(stats.netRxRate))/s")
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                } icon: {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                }
                Label {
                    Text("Up \(byteString(stats.netTxRate))/s")
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                } icon: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                Spacer()
            }

            if Defaults[.featureSpeedTest] {
                speedTestSection
            }

            if Defaults[.featurePerAppNetwork] {
                perAppSection
            }
        }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            stats.start()
            if Defaults[.featurePerAppNetwork] {
                network.refresh()
            }
        }
        .onDisappear {
            stats.stop()
        }
    }

    private var speedTestSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(Color.white.opacity(0.15))
            HStack {
                Text("Speed test")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button(speedTest.isRunning ? "Running…" : "Run") {
                    speedTest.run()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
                .foregroundStyle(speedTest.isRunning ? .gray : .white)
                .disabled(speedTest.isRunning)
            }

            if speedTest.phase == .downloading {
                ProgressView(value: speedTest.progress)
                    .controlSize(.small)
                Text("Downloading…")
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
            } else if speedTest.phase == .uploading {
                ProgressView()
                    .controlSize(.small)
                Text("Uploading…")
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
            }

            if let down = speedTest.downloadMbps, let up = speedTest.uploadMbps {
                HStack(spacing: 14) {
                    Label(String(format: "Down %.1f Mbps", down), systemImage: "arrow.down")
                    Label(String(format: "Up %.1f Mbps", up), systemImage: "arrow.up")
                }
                .font(.system(size: 11))
                .foregroundStyle(.white)
            }

            if speedTest.phase == .failed {
                Text("Speed test failed. Check the connection and try again.")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
            }
        }
    }

    private var perAppSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(Color.white.opacity(0.15))
            HStack {
                Text("Top apps by network")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Refresh") {
                    network.refresh()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
                .foregroundStyle(.gray)
                .disabled(network.isSampling)
            }

            Text("Totals since each app started")
                .font(.system(size: 9))
                .foregroundStyle(.gray)

            if network.isSampling && network.usages.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 6)
            } else if network.usages.isEmpty {
                Text("No per-app counters yet")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                    .padding(.vertical, 4)
            } else {
                ForEach(network.usages) { usage in
                    HStack(spacing: 8) {
                        if let icon = usage.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 14, height: 14)
                        }
                        Text(usage.name)
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Label(byteString(usage.rxBytes), systemImage: "arrow.down")
                        Label(byteString(usage.txBytes), systemImage: "arrow.up")
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
                }
            }
        }
    }

    private func statRow(icon: String, label: String, value: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                Spacer()
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(fraction > 0.8 ? Color.orange : Color.green)
                        .frame(width: max(4, proxy.size.width * min(fraction, 1.0)))
                }
            }
            .frame(height: 5)
        }
    }

    private func byteString(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func byteString(_ bytes: Int64) -> String {
        byteString(UInt64(clamping: bytes))
    }
}
