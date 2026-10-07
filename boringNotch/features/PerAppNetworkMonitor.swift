//
//  PerAppNetworkMonitor.swift
//  boringNotch
//
//  Tools: per-app network usage. Reads cumulative byte counters by
//  sampling `nettop -P -l 1` (the same private NetworkStatistics source
//  Activity Monitor uses, but through the shipped CLI so we link no
//  private frameworks). Refreshes only while a consumer asks for it.
//

import AppKit
import Foundation

struct AppNetworkUsage: Identifiable {
    let pid: Int32
    let name: String
    let rxBytes: Int64
    let txBytes: Int64
    let icon: NSImage?
    var id: Int32 { pid }

    var totalBytes: Int64 { rxBytes + txBytes }
}

final class PerAppNetworkMonitor: ObservableObject {
    static let shared = PerAppNetworkMonitor()

    @Published var usages: [AppNetworkUsage] = []
    @Published var isSampling = false

    private init() {}

    func refresh() {
        guard !isSampling else { return }
        isSampling = true

        Task.detached(priority: .utility) {
            let samples = Self.sampleNettop()
            await MainActor.run {
                self.usages = samples
                    .filter { $0.totalBytes > 0 }
                    .sorted { $0.totalBytes > $1.totalBytes }
                    .prefix(8)
                    .map { usage in
                        var enriched = usage
                        enriched = AppNetworkUsage(
                            pid: usage.pid,
                            name: usage.name,
                            rxBytes: usage.rxBytes,
                            txBytes: usage.txBytes,
                            icon: Self.icon(forPID: usage.pid, name: usage.name)
                        )
                        return enriched
                    }
                self.isSampling = false
            }
        }
    }

    private static func icon(forPID pid: Int32, name: String) -> NSImage? {
        if let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon {
            return icon
        }
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame
        }), let icon = app.icon {
            return icon
        }
        return NSWorkspace.shared.icon(forFileType: "")
    }

    private static func sampleNettop() -> [AppNetworkUsage] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-l", "1", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { parse(line: String($0)) }
    }

    private static func parse(line: String) -> AppNetworkUsage? {
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count >= 5 else { return nil }

        guard let outUnit = tokens.last,
              let outValue = tokens.dropLast().last,
              let inUnit = tokens.dropLast(2).last,
              let inValue = tokens.dropLast(3).last else { return nil }

        let nameAndPID = tokens.dropLast(4).joined(separator: " ")
        guard let dotIndex = nameAndPID.lastIndex(of: "."),
              let pid = Int32(nameAndPID[nameAndPID.index(after: dotIndex)...]) else { return nil }

        let name = String(nameAndPID[..<dotIndex])
        guard !name.isEmpty else { return nil }

        guard let rx = byteCount(value: inValue, unit: inUnit),
              let tx = byteCount(value: outValue, unit: outUnit) else { return nil }

        return AppNetworkUsage(pid: pid, name: name, rxBytes: rx, txBytes: tx, icon: nil)
    }

    private static func byteCount(value: String, unit: String) -> Int64? {
        guard let number = Double(value) else { return nil }
        let multiplier: Double
        switch unit.uppercased() {
        case "B": multiplier = 1
        case "KIB": multiplier = 1024
        case "MIB": multiplier = 1024 * 1024
        case "GIB": multiplier = 1024 * 1024 * 1024
        case "KB": multiplier = 1000
        case "MB": multiplier = 1000 * 1000
        case "GB": multiplier = 1000 * 1000 * 1000
        default: return nil
        }
        return Int64(number * multiplier)
    }
}
