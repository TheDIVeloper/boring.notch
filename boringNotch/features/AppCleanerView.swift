//
//  AppCleanerView.swift
//  boringNotch
//
//  Tools: app cleaner tab. Pick an app, review leftovers, trash them.
//

import Defaults
import SwiftUI

struct AppCleanerView: View {
    @StateObject private var model = AppCleanerManager()
    @State private var searchText = ""

    var body: some View {
        Group {
            if model.selectedApp == nil {
                listView
            } else {
                detailView
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if model.apps.isEmpty {
                model.loadApps()
            }
        }
    }

    // MARK: - App list

    private var listView: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Cleaner")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(model.apps.count) apps")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
            }

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(6)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.08))
                }
                .foregroundStyle(.white)

            if model.apps.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 20)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(filteredApps) { app in
                            Button {
                                model.select(app)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(nsImage: app.icon)
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                    Text(app.name)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.gray)
                                }
                                .padding(6)
                                .background {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.06))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }

            Text("Everything selected is moved to the Trash, so nothing is lost permanently.")
                .font(.system(size: 9))
                .foregroundStyle(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var filteredApps: [InstalledApp] {
        guard !searchText.isEmpty else { return model.apps }
        return model.apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Detail

    private var detailView: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    model.deselect()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)

                if let app = model.selectedApp {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(app.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                if let size = model.appSize {
                    Text(byteString(size))
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if model.isScanning {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning for leftovers…")
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            } else {
                HStack {
                    Button("Select all") {
                        model.selectAll(true)
                    }
                    Button("None") {
                        model.selectAll(false)
                    }
                    Spacer()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
                .foregroundStyle(.gray)

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.leftovers) { item in
                            leftoverRow(item)
                        }
                    }
                }
                .frame(maxHeight: 170)
            }

            if let message = model.statusMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }

            HStack {
                Text("\(model.selectedCount) item(s), \(byteString(model.selectedSize))")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    model.trashSelection()
                } label: {
                    if model.isTrashing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Move to Trash")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red.opacity(0.7))
                .disabled(model.isScanning || model.isTrashing || model.selectedCount == 0)
            }
        }
    }

    private func leftoverRow(_ item: LeftoverItem) -> some View {
        Button {
            model.toggle(item)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(item.isSelected ? Color.blue : Color.gray)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.path.lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.category + (item.strongMatch ? "" : ", name match"))
                        .font(.system(size: 8))
                        .foregroundStyle(.gray)
                }

                Spacer()

                Text(byteString(item.size))
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
            }
            .padding(5)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.05))
            }
        }
        .buttonStyle(.plain)
    }

    private func byteString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
