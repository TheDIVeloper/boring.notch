//
//  AppCleanerManager.swift
//  boringNotch
//
//  Tools: app cleaner and uninstaller. Lists user-installed apps,
//  scans for leftovers by bundle id (strong match, checked by default)
//  or by exact app name (weak match, unchecked by default), and moves
//  the selected items to the Trash. Nothing is ever deleted outright.
//

import AppKit
import Defaults
import Foundation

struct InstalledApp: Identifiable, Equatable {
    let id = UUID()
    let path: URL
    let name: String
    let bundleID: String?
    let icon: NSImage

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool {
        lhs.path == rhs.path
    }
}

struct LeftoverItem: Identifiable {
    let path: URL
    let category: String
    let strongMatch: Bool
    let size: Int64
    var isSelected: Bool
    var id: URL { path }
}

final class AppCleanerManager: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var selectedApp: InstalledApp?
    @Published var appSize: Int64?
    @Published var leftovers: [LeftoverItem] = []
    @Published var isScanning = false
    @Published var isTrashing = false
    @Published var statusMessage: String?

    private let fm = FileManager.default

    private var applicationDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
    }

    func loadApps() {
        var results: [InstalledApp] = []
        var seenPaths = Set<String>()

        for root in applicationDirectories {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                enumerator.skipDescendants()

                guard seenPaths.insert(url.path).inserted else { continue }
                guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { continue }
                guard !bundleID.hasPrefix("com.apple.") else { continue }

                results.append(
                    InstalledApp(
                        path: url,
                        name: url.deletingPathExtension().lastPathComponent,
                        bundleID: bundleID,
                        icon: NSWorkspace.shared.icon(forFile: url.path)
                    )
                )
            }
        }
        apps = results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func select(_ app: InstalledApp) {
        selectedApp = app
        appSize = nil
        leftovers = []
        statusMessage = nil
        isScanning = true

        let path = app.path
        Task.detached(priority: .userInitiated) {
            let size = Self.size(of: path)
            let leftovers = Self.scanLeftovers(for: app)
            await MainActor.run {
                guard self.selectedApp == app else { return }
                self.appSize = size
                self.leftovers = leftovers
                self.isScanning = false
            }
        }
    }

    func deselect() {
        selectedApp = nil
        leftovers = []
        appSize = nil
        statusMessage = nil
    }

    func toggle(_ item: LeftoverItem) {
        guard let index = leftovers.firstIndex(where: { $0.id == item.id }) else { return }
        leftovers[index].isSelected.toggle()
    }

    func selectAll(_ selected: Bool) {
        for index in leftovers.indices {
            leftovers[index].isSelected = selected
        }
    }

    var selectedCount: Int {
        (selectedApp != nil ? 1 : 0) + leftovers.filter(\.isSelected).count
    }

    var selectedSize: Int64 {
        (selectedApp != nil ? (appSize ?? 0) : 0) + leftovers.filter(\.isSelected).reduce(0) { $0 + $1.size }
    }

    func trashSelection() {
        guard let app = selectedApp, !isTrashing else { return }
        isTrashing = true
        statusMessage = nil

        var targets: [URL] = [app.path]
        targets.append(contentsOf: leftovers.filter(\.isSelected).map(\.path))

        Task.detached(priority: .userInitiated) {
            var failures: [String] = []
            var trashedCount = 0
            for target in targets {
                do {
                    try self.fm.trashItem(at: target, resultingItemURL: nil)
                    trashedCount += 1
                } catch {
                    failures.append("\(target.lastPathComponent): \(error.localizedDescription)")
                }
            }
            await MainActor.run {
                self.isTrashing = false
                if failures.isEmpty {
                    self.statusMessage = "Moved \(trashedCount) item(s) to the Trash."
                    self.deselect()
                    self.loadApps()
                } else {
                    self.statusMessage = "Trashed \(trashedCount), failed: \(failures.joined(separator: "; "))"
                    self.select(app)
                }
            }
        }
    }

    // MARK: - Scanning

    private static func scanLeftovers(for app: InstalledApp) -> [LeftoverItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let bundleID = app.bundleID?.lowercased()
        let appName = app.name.lowercased()

        struct Candidate {
            let path: URL
            let category: String
            let strong: Bool
        }

        var candidates: [Candidate] = []

        func matches(_ entryName: String, allowNameMatch: Bool) -> Bool {
            let lower = entryName.lowercased()
            if let bundleID, lower.contains(bundleID) { return true }
            if allowNameMatch {
                if lower == appName || lower == appName + ".plist" { return true }
            }
            return false
        }

        func scanDirectory(_ dir: URL, category: String, allowNameMatch: Bool) {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            for entry in entries {
                if matches(entry.lastPathComponent, allowNameMatch: allowNameMatch) {
                    let strong = bundleID != nil && entry.lastPathComponent.lowercased().contains(bundleID!)
                    candidates.append(Candidate(path: entry, category: category, strong: strong))
                }
            }
        }

        let library = home.appendingPathComponent("Library")
        scanDirectory(library.appendingPathComponent("Application Support"), category: "Application Support", allowNameMatch: true)
        scanDirectory(library.appendingPathComponent("Caches"), category: "Caches", allowNameMatch: true)
        scanDirectory(library.appendingPathComponent("Logs"), category: "Logs", allowNameMatch: true)
        scanDirectory(library.appendingPathComponent("Containers"), category: "Container", allowNameMatch: false)
        scanDirectory(library.appendingPathComponent("Group Containers"), category: "Group Container", allowNameMatch: true)
        scanDirectory(library.appendingPathComponent("HTTPStorages"), category: "HTTP Storage", allowNameMatch: false)
        scanDirectory(library.appendingPathComponent("WebKit"), category: "WebKit", allowNameMatch: false)
        scanDirectory(library.appendingPathComponent("Saved Application State"), category: "Saved State", allowNameMatch: false)
        scanDirectory(library.appendingPathComponent("LaunchAgents"), category: "Launch Agent", allowNameMatch: false)

        let preferences = library.appendingPathComponent("Preferences")
        if let entries = try? fm.contentsOfDirectory(at: preferences, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for entry in entries where matches(entry.lastPathComponent, allowNameMatch: true) {
                let strong = bundleID != nil && entry.lastPathComponent.lowercased().contains(bundleID!)
                candidates.append(Candidate(path: entry, category: "Preferences", strong: strong))
            }
        }

        var seen = Set<String>()
        var items: [LeftoverItem] = []
        for candidate in candidates where seen.insert(candidate.path.path).inserted {
            items.append(
                LeftoverItem(
                    path: candidate.path,
                    category: candidate.category,
                    strongMatch: candidate.strong,
                    size: size(of: candidate.path),
                    isSelected: candidate.strong
                )
            )
        }
        return items.sorted { $0.path.lastPathComponent.localizedCaseInsensitiveCompare($1.path.lastPathComponent) == .orderedAscending }
    }

    private static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }

        guard values.isDirectory == true else {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: []) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let fileValues = try? fileURL.resourceValues(forKeys: keys) else { continue }
            total += Int64(fileValues.totalFileAllocatedSize ?? fileValues.fileAllocatedSize ?? 0)
        }
        return total
    }
}
