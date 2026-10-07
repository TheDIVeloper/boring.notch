//
//  ClipboardHistoryView.swift
//  boringNotch
//
//  Tools: clipboard history tab. Click a row to copy it back.
//

import Defaults
import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var manager = ClipboardHistoryManager.shared
    @State private var justCopiedID: UUID?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Clipboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                if !manager.entries.isEmpty {
                    Button("Clear") {
                        manager.clearAll()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                }
            }

            if !Defaults[.featureClipboardHistory] {
                Text("Clipboard history is off. Turn it on in Settings, Tools.")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else if manager.entries.isEmpty {
                Text("Nothing copied yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(manager.entries) { entry in
                            row(for: entry)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(for entry: ClipboardEntry) -> some View {
        Button {
            manager.copy(entry)
            justCopiedID = entry.id
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                justCopiedID = nil
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: justCopiedID == entry.id ? "checkmark" : "doc.on.clipboard")
                    .font(.system(size: 11))
                    .foregroundStyle(justCopiedID == entry.id ? .green : .gray)
                    .frame(width: 16)

                Text(entry.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Text(entry.copiedAt, style: .time)
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(justCopiedID == entry.id ? 0.16 : 0.08))
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove") {
                manager.remove(entry)
            }
        }
    }
}
