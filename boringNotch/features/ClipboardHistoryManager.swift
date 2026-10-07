//
//  ClipboardHistoryManager.swift
//  boringNotch
//
//  Tools: clipboard history. Polls the general pasteboard, skips items
//  other apps marked confidential or transient, persists text entries.
//

import AppKit
import Defaults
import Foundation

struct ClipboardEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var copiedAt: Date
}

final class ClipboardHistoryManager: ObservableObject {
    static let shared = ClipboardHistoryManager()

    @Published private(set) var entries: [ClipboardEntry] = []

    private let maxEntries = 50
    private let maxTextLength = 100_000
    private var timer: Timer?
    private var lastChangeCount: Int
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let fm = FileManager.default
        let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = (support ?? fm.temporaryDirectory)
            .appendingPathComponent("boringNotch", isDirectory: true)
            .appendingPathComponent("Clipboard", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? decoder.decode([ClipboardEntry].self, from: data) {
            entries = saved
        }
        lastChangeCount = NSPasteboard.general.changeCount

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        guard Defaults[.featureClipboardHistory] else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let items = pasteboard.pasteboardItems else { return }

        for item in items {
            let types = item.types.map { $0.rawValue }
            if types.contains(where: { $0.contains("Concealed") || $0.contains("Transient") }) {
                return
            }
            if let text = item.string(forType: .string), !text.isEmpty {
                record(text)
                return
            }
            if let fileURLString = item.string(forType: .fileURL),
               let url = URL(string: fileURLString) {
                record(url.path)
                return
            }
        }
    }

    private func record(_ rawText: String) {
        let text = String(rawText.prefix(maxTextLength))
        entries.removeAll { $0.text == text }
        entries.insert(ClipboardEntry(id: UUID(), text: text, copiedAt: Date()), at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        save()
    }

    func copy(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        entries.removeAll { $0.id == entry.id }
        entries.insert(ClipboardEntry(id: entry.id, text: entry.text, copiedAt: Date()), at: 0)
        save()
    }

    func remove(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clearAll() {
        entries = []
        save()
    }

    private func save() {
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
