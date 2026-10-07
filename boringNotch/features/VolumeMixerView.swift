//
//  VolumeMixerView.swift
//  boringNotch
//
//  Tools: per-app volume mixer. Rows come from VolumeMixerManager;
//  apps below 100% get a muted process tap plus a private aggregate
//  device re-rendering them at the chosen gain. Apps at 100% are never
//  touched.
//

import Defaults
import SwiftUI

struct VolumeMixerView: View {
    let onBack: () -> Void
    @ObservedObject private var manager = VolumeMixerManager.shared

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)

                Text("Volume mixer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()
            }

            if manager.needsPermission {
                VStack(alignment: .leading, spacing: 8) {
                    Text("macOS needs the Screen & System Audio Recording permission before an app can be pulled into the mixer.")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Open Privacy Settings") {
                        manager.openPrivacySettings()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.14))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if manager.rows.isEmpty {
                Text("No apps are playing audio")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(manager.rows) { row in
                            self.row(for: row)
                        }
                    }
                }
                .frame(maxHeight: 190)
            }

            if let error = manager.errorMessage {
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
        .onAppear {
            manager.startMonitoring()
        }
    }

    private func row(for row: MixerAppRow) -> some View {
        HStack(spacing: 10) {
            Group {
                if let icon = row.icon {
                    Image(nsImage: icon)
                        .resizable()
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .foregroundStyle(.gray)
                }
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if row.isPlaying {
                        Circle()
                            .fill(Color.green.opacity(0.8))
                            .frame(width: 5, height: 5)
                    }
                }

                Slider(
                    value: Binding(
                        get: { row.volume },
                        set: { manager.setVolume($0, for: row.id) }
                    ),
                    in: 0...1
                )
                .disabled(!row.hasProcess && row.volume >= VolumeMixerManager.unityVolume)

                HStack {
                    Text("\(Int((row.volume * 100).rounded()))%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.gray)

                    Spacer()

                    if row.volume < VolumeMixerManager.unityVolume {
                        Button("Reset") {
                            manager.resetVolume(for: row.id)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9))
                        .foregroundStyle(.gray)
                    }
                }
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1))
        }
    }
}
