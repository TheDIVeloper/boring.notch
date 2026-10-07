//
//  DiskEjectView.swift
//  boringNotch
//
//  Tools: list mounted volumes and eject them safely.
//

import AppKit
import Defaults
import SwiftUI

struct EjectVolume: Identifiable {
    let url: URL
    let name: String
    let icon: NSImage
    let isRemovable: Bool
    let isNetwork: Bool
    let freeBytes: Int64
    let totalBytes: Int64
    var id: URL { url }
}

final class DiskEjectModel: ObservableObject {
    @Published var volumes: [EjectVolume] = []
    @Published var error: String?
    @Published var ejecting: Set<URL> = []

    func refresh() {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) else { return }

        var result: [EjectVolume] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            let isRemovable = values.volumeIsRemovable ?? false
            let isInternal = values.volumeIsInternal ?? true
            let isNetwork = !(values.volumeIsLocal ?? true)
            guard isRemovable || isNetwork || !isInternal else { continue }
            result.append(
                EjectVolume(
                    url: url,
                    name: values.volumeName ?? url.lastPathComponent,
                    icon: NSWorkspace.shared.icon(forFile: url.path),
                    isRemovable: isRemovable,
                    isNetwork: isNetwork,
                    freeBytes: Int64(values.volumeAvailableCapacityForImportantUsage ?? 0),
                    totalBytes: Int64(values.volumeTotalCapacity ?? 0)
                )
            )
        }
        volumes = result
        if !result.isEmpty { error = nil }
    }

    func eject(_ volume: EjectVolume) {
        ejecting.insert(volume.url)
        Task { @MainActor in
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
                error = nil
            } catch {
                self.error = "\(volume.name): \(error.localizedDescription)"
            }
            self.ejecting.remove(volume.url)
            self.refresh()
        }
    }
}

struct DiskEjectView: View {
    let onBack: () -> Void
    @StateObject private var model = DiskEjectModel()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)

                Text("Disks")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.gray)
            }

            if model.volumes.isEmpty {
                Text("No removable volumes")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.volumes) { volume in
                            row(for: volume)
                        }
                    }
                }
                .frame(maxHeight: 170)
            }

            if let error = model.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { model.refresh() }
    }

    private func row(for volume: EjectVolume) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: volume.icon)
                .resizable()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(volume.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if volume.totalBytes > 0 {
                    Text("\(byteString(volume.freeBytes)) free of \(byteString(volume.totalBytes))")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                }
            }

            Spacer()

            Button {
                model.eject(volume)
            } label: {
                if model.ejecting.contains(volume.url) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "eject.fill")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(model.ejecting.contains(volume.url))
            .help("Eject \(volume.name)")
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
