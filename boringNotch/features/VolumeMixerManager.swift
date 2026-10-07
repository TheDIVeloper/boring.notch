//
//  VolumeMixerManager.swift
//  boringNotch
//
//  Per-app volume mixer. Lists every process that holds an audio
//  connection, keeps a MixerEngine for each row the user pulled below
//  100%, and leaves everything at 100% completely untouched. Volumes
//  persist per bundle id in SwiftyDefaults.
//

import AppKit
import CoreAudio
import Defaults
import Foundation

struct MixerAppRow: Identifiable, Equatable {
    let id: String
    let pid: pid_t
    let name: String
    let bundleID: String?
    let icon: NSImage?
    var isPlaying: Bool
    var volume: Double
    var hasProcess: Bool

    static func == (lhs: MixerAppRow, rhs: MixerAppRow) -> Bool {
        lhs.id == rhs.id && lhs.pid == rhs.pid && lhs.name == rhs.name
            && lhs.bundleID == rhs.bundleID && lhs.isPlaying == rhs.isPlaying
            && lhs.volume == rhs.volume && lhs.hasProcess == rhs.hasProcess
    }
}

final class VolumeMixerManager: ObservableObject {
    static let shared = VolumeMixerManager()

    static let unityVolume = 0.999

    @Published var rows: [MixerAppRow] = []
    @Published var needsPermission = false
    @Published var errorMessage: String?

    private var engines: [String: MixerEngine] = [:]
    private var processByRow: [String: AudioObjectID] = [:]
    private var timer: Timer?
    private var lastOutputUID: String?

    private init() {}

    func startMonitoring() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    // MARK: - Volume changes

    func setVolume(_ volume: Double, for id: String) {
        let clamped = min(max(volume, 0), 1)
        var volumes = Defaults[.mixerAppVolumes]
        volumes[id] = clamped
        Defaults[.mixerAppVolumes] = volumes
        if let index = rows.firstIndex(where: { $0.id == id }) {
            rows[index].volume = clamped
        }

        if clamped >= Self.unityVolume {
            engines[id]?.stop()
            engines[id] = nil
        } else if let processObjectID = processByRow[id] {
            startEngineIfNeeded(id: id, processObjectID: processObjectID, volume: clamped)
            engines[id]?.setGain(Float(clamped))
        }
    }

    func resetVolume(for id: String) {
        setVolume(1.0, for: id)
    }

    // MARK: - Refresh

    private func tick() {
        guard Defaults[.featureVolumeMixer] else {
            if !engines.isEmpty || !rows.isEmpty {
                teardownAll()
                rows = []
            }
            return
        }

        rebuildIfOutputChanged()
        refresh()
    }

    private func rebuildIfOutputChanged() {
        guard let device = try? MixerCoreAudio.defaultOutputDevice(),
              let uid = try? MixerCoreAudio.deviceUID(device) else { return }
        if let last = lastOutputUID, last != uid {
            for engine in engines.values { engine.stop() }
            engines = [:]
        }
        lastOutputUID = uid
    }

    private func refresh() {
        var candidates: [MixerAppRow] = []
        var seen = Set<String>()
        var processes: [AudioObjectID] = []

        do {
            processes = try MixerCoreAudio.processList()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        for process in processes {
            guard let pid = MixerCoreAudio.pid(of: process), pid > 0, pid != getpid() else { continue }
            let runningApp = NSRunningApplication(processIdentifier: pid)
            let bundleID = MixerCoreAudio.bundleID(of: process)
            let rowID = bundleID ?? "pid-\(pid)"
            guard !seen.contains(rowID) else { continue }
            seen.insert(rowID)

            processByRow[rowID] = process
            let volume = Defaults[.mixerAppVolumes][rowID] ?? 1.0
            candidates.append(
                MixerAppRow(
                    id: rowID,
                    pid: pid,
                    name: runningApp?.localizedName ?? bundleID ?? "Process \(pid)",
                    bundleID: bundleID,
                    icon: runningApp?.icon,
                    isPlaying: MixerCoreAudio.isRunningOutput(process),
                    volume: volume,
                    hasProcess: true
                )
            )
        }

        for (rowID, volume) in Defaults[.mixerAppVolumes] where !seen.contains(rowID) && volume < Self.unityVolume {
            candidates.append(
                MixerAppRow(
                    id: rowID,
                    pid: 0,
                    name: rowID.hasPrefix("pid-") ? String(rowID.dropFirst(4)) : rowID,
                    bundleID: rowID.hasPrefix("pid-") ? nil : rowID,
                    icon: nil,
                    isPlaying: false,
                    volume: volume,
                    hasProcess: false
                )
            )
        }

        candidates.sort { lhs, rhs in
            if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        if rows != candidates {
            rows = candidates
        }

        reconcileEngines()
    }

    private func reconcileEngines() {
        var liveIDs = Set<String>()
        for row in rows where row.hasProcess {
            liveIDs.insert(row.id)
            if row.volume < Self.unityVolume, let processObjectID = processByRow[row.id] {
                startEngineIfNeeded(id: row.id, processObjectID: processObjectID, volume: row.volume)
                engines[row.id]?.setGain(Float(row.volume))
            } else if let engine = engines[row.id] {
                engine.stop()
                engines[row.id] = nil
            }
        }

        for (rowID, engine) in engines where !liveIDs.contains(rowID) {
            engine.stop()
            engines[rowID] = nil
        }
    }

    private func startEngineIfNeeded(id: String, processObjectID: AudioObjectID, volume: Double) {
        guard engines[id] == nil else { return }
        if #available(macOS 14.2, *) {
            do {
                let engine = try MixerEngine(processObjectID: processObjectID, gain: Float(volume))
                try engine.start()
                engines[id] = engine
                needsPermission = false
            } catch {
                if case let MixerCoreAudioError.osStatus(_, operation) = error,
                   operation == "create process tap" {
                    needsPermission = true
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func teardownAll() {
        for engine in engines.values { engine.stop() }
        engines = [:]
        processByRow = [:]
        needsPermission = false
        errorMessage = nil
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    deinit {
        timer?.invalidate()
        for engine in engines.values { engine.stop() }
    }
}
