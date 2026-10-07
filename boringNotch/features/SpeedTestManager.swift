//
//  SpeedTestManager.swift
//  boringNotch
//
//  Tools: network speed test. Downloads 25 MB and uploads 5 MB from
//  Cloudflare's test endpoint and reports Mbps.
//

import Foundation

final class SpeedTestManager: ObservableObject {
    static let shared = SpeedTestManager()

    enum Phase: Equatable {
        case idle
        case downloading
        case uploading
        case done
        case failed
    }

    @Published var phase: Phase = .idle
    @Published var downloadMbps: Double?
    @Published var uploadMbps: Double?
    @Published var progress: Double = 0

    private let downloadBytes = 25_000_000
    private let uploadBytes = 5_000_000

    private init() {}

    var isRunning: Bool {
        phase == .downloading || phase == .uploading
    }

    func run() {
        guard !isRunning else { return }
        phase = .downloading
        downloadMbps = nil
        uploadMbps = nil
        progress = 0

        Task {
            await performDownload()
        }
    }

    func reset() {
        guard !isRunning else { return }
        phase = .idle
        downloadMbps = nil
        uploadMbps = nil
        progress = 0
    }

    private func performDownload() async {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(downloadBytes)") else {
            await MainActor.run { self.phase = .failed }
            return
        }
        let start = Date()
        var received = 0

        do {
            let (stream, response) = try await URLSession.shared.bytes(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                await MainActor.run { self.phase = .failed }
                return
            }
            for try await _ in stream {
                received += 1
                if received % 250_000 == 0 {
                    let fraction = Double(received) / Double(downloadBytes)
                    await MainActor.run { self.progress = min(fraction, 1.0) }
                }
            }
            let elapsed = max(Date().timeIntervalSince(start), 0.001)
            let mbps = Double(received) * 8.0 / elapsed / 1_000_000.0
            await MainActor.run {
                self.downloadMbps = mbps
                self.phase = .uploading
            }
            await performUpload()
        } catch {
            await MainActor.run { self.phase = .failed }
        }
    }

    private func performUpload() async {
        guard let url = URL(string: "https://speed.cloudflare.com/__up") else {
            await MainActor.run { self.phase = .failed }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(count: uploadBytes)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let start = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let elapsed = max(Date().timeIntervalSince(start), 0.001)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                await MainActor.run { self.phase = .failed }
                return
            }
            let mbps = Double(uploadBytes) * 8.0 / elapsed / 1_000_000.0
            await MainActor.run {
                self.uploadMbps = mbps
                self.phase = .done
            }
        } catch {
            await MainActor.run { self.phase = .failed }
        }
    }
}
